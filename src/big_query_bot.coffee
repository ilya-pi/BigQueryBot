
_ = require 'lodash'
async = require 'async'
fs = require 'fs'
googleapis = require 'googleapis'
md5 = require 'MD5'

bigquery = googleapis.bigquery 'v2'

EventEmitter = (require 'events').EventEmitter

# -----------------------------------------------------------------------------
# BigQueryBot implements a neat way to chain Big Queries with `async` library
# It exposes a number of methods that return async-ready functions, such as:
# - `load`
# - `query`
# - `extract`

module.exports.BigQueryBot =
class BigQueryBot extends EventEmitter

    scope: ['https://www.googleapis.com/auth/bigquery']

    constructor: (@serviceAccount, @privateKeyPath, @config) ->
        @config.botId ?= "_tmp"
        @config.startTime ?= Date.now()

        # Required to keep track of the events
        @intervals =
            "jobId": "intervalId"

        # Authenticate with Google Api
        @jwt = new googleapis.auth.JWT @serviceAccount, @privateKeyPath, null, @scope, null
        @jwt.authorize (e, r) =>
            if e
                console.error e
                console.error "Failed to authenticate with #{@serviceAccount} and #{@privateKeyPath}"
            else
                @emit 'ready'

    source: (source) ->
        () ->
            (_.last arguments) null, source

    with: (postfix) ->
        (source, cb) ->
            cb null, _.flatten [source, postfix]


    flatten: (source, cb) ->
        cb null, _.flatten source


    # Flow controll function, takes in array of arrays of steps. Launches waterfall
    # processing of each array in parallel to each other on the top level
    # i.e.
    # bot.parallel [
    #   [
    #       step1_1
    #       step1_2
    #       step1_3
    #   ]
    #   [
    #       step2_1
    #       step2_2
    #   ]
    # ]
    # results in [ <`step1_3` output>, <`step2_2` output>]
    parallel: (jobs) ->
        (source, cb) ->
            wiredJobs = []
            ((_waterfall) ->
                wiredWaterfall = []
                wiredWaterfall.push (_cb) -> (_.first _waterfall) source, _cb
                wiredWaterfall.push job for job in _.rest _waterfall

                wiredJobs.push (_cb) ->
                    async.waterfall wiredWaterfall, _cb)(waterfall) for waterfall in jobs

            async.parallel wiredJobs, cb


    generateTableName: (input) ->
        @config.botId + '_' + md5(input)

    # Fully Qualified Table Name
    fqtn: (table) =>
        "[#{@config.datasetId}.#{table}]"

    # Runs `load` job, that fetches data from gs:// with a given schema
    # Currently only supports deprecated schema format, the "oneliner"
    load: (options) ->

        options = _.defaults options,
            schema: ''
            overwrite: false
            delimiter: '\t'
            sourceFormat: 'CSV'
            maxBadRecords: 1000
            skipLeadingRows: 0

        options.name ?= @generateTableName options.gsPaths + options.schema

        @_trackDeps options.gsPaths, options.name

        request = (opts) =>
            configuration:
                load:
                    allowJaggedRows: false
                    allowQuotedNewlines: false
                    createDisposition: 'CREATE_IF_NEEDED'
                    destinationTable:
                        projectId: @config.projectId
                        datasetId: @config.datasetId
                        tableId: opts.name
                    encoding: 'UTF-8'
                    fieldDelimiter: opts.delimiter
                    ignoreUnknownValues: true
                    maxBadRecords: opts.maxBadRecords
                    sourceFormat: opts.sourceFormat
                    schemaInline: opts.schema # xxx move to the new 'fields' format
                    sourceUris: opts.gsPaths
                    skipLeadingRows: opts.skipLeadingRows
                    writeDisposition: 'WRITE_APPEND'

        # usually only receives a call back, but it should not break if it also receives a source as first arg
        () =>
            cb = _.last arguments

            if arguments.length > 1
                options.gsPaths ?= arguments[0]

            logEnrichedCb = (e, r) =>
                if not e
                    console.log "Saved #{options.gsPaths} as #{(@fqtn options.name)}"
                cb?(e, r)

            @_getLatestUpdate options.name, (e, updated) =>
                # if it doesn't exists or overwrite is forced,... start the import
                if e or options.overwrite
                    console.log "Starting import of #{options.gsPaths}. #{if updated? then "Overwriting" else "Creating"} #{(@fqtn options.name)}"
                    @_job (request options), options.name, logEnrichedCb
                else
                    console.log "Table #{(@fqtn options.name)} exists, skipping import of #{options.gsPaths}. Latest update was #{Math.round((Date.now() - updated)/60000)} minutes ago"
                    cb(null, options.name)


    _renderQuery: (sql, source) ->
        if (_.isArray source) and (sql.indexOf '<in>') > 0
            (sql.replace /<in>/g, ((_.map source, @fqtn).join ', '))
        else if _.isArray source
            res = sql
            for i,val of source
                res = res.replace (new RegExp "<in#{i}>",'g'), (@fqtn val)
            res
        else
            (sql.replace /<in>/g, (@fqtn source))


    # Runs `query` on top of `table` with query name/target table name `name`
    # options.name - name of the query and part of the destination table name
    # options.source - either a single table name or array of table names
    # options.overwrite - force overwriting the existing table in any case
    query: (options = {}) ->

        options = _.defaults options,
            sql: ''
            overwrite: false
            source: null

        if options.file?
            options.sql = fs.readFileSync options.file, 'utf8'

        options.name ?= @generateTableName options.sql
        
        request = (source) =>
            @_trackDeps source, options.name
            configuration:
                query:
                    allowLargeResults: true
                    destinationTable:
                        projectId: @config.projectId
                        datasetId: @config.datasetId
                        tableId: options.name
                    useQueryCache: true
                    writeDisposition: 'WRITE_TRUNCATE'
                    createDisposition: 'CREATE_IF_NEEDED'
                    query: (@_renderQuery options.sql, source)

        metaJob = (source, cb) =>
            requestObj = (request source)

            logEnrichedCb = (e, r) =>
                if not e
                    console.log "Saved as #{(@fqtn options.name)}"
                cb?(e, r)

            # check if the source table was updated during the execution of the flow
            @_getLatestUpdate source, (e, updated) =>
                if e
                    console.error "Error accessing source table:", e
                    cb e 
                else
                    sourceUpdated = updated > @config.startTime

                    # check if the desitination table already exists
                    @_getLatestUpdate options.name, (e, updated) =>
                        # if it doesn't exists, or the source was updated or overwrite is forced,... start the query
                        if e or sourceUpdated or options.overwrite
                            console.log "#{if sourceUpdated then "Source updated. " else ""}Starting query. #{if updated? then "Overwriting" else "Creating"} #{(@fqtn options.name)}"
                            @_job requestObj, options.name, logEnrichedCb
                        else
                            console.log "Table #{(@fqtn options.name)} exists, skipping query. Latest update was #{Math.round((Date.now() - updated)/60000)} minutes ago"
                            cb(null, options.name)

        # retry the query if too many queries are running simultaneously
        retryJob = (source, maxtries, cb) =>
            retries = 0

            metaCb = (e, r) ->
                if retries < maxtries and e?.reason? and e.reason is 'rateLimitExceeded'
                    retries++
                    console.log "Retry nr #{retries} in #{retries * 5} seconds"
                    setTimeout (() -> metaJob source, metaCb), retries * 5000
                else
                    cb e, r

            metaJob source, metaCb



        # return a function that either receives just a callback (if no previous step passes on a source)
        # or a source and a callback
        () ->
            cb = _.last arguments

            if arguments.length > 1
                options.source ?= arguments[0]

            if options.source
                # retry querying 20 times, max 1046 seconds > [1..20].reduce (p, c) -> p + (c * 5)
                retryJob options.source, 20, cb
            else
                cb "no source defined or passed on for #{options.name}" 


    # Runs table `extract` from Big Query into Google Cloud Storage
    extract: (gsPaths, table) ->
        request = (source) =>
            @_trackDeps source, gsPath for gsPath in gsPaths
            configuration:
                extract:
                    compression: 'GZIP'
                    destinationUris: gsPaths
                    fieldDelimiter: '\t'
                    sourceTable:
                        projectId: @config.projectId
                        datasetId: @config.datasetId
                        tableId: source
        metaJob = (source, cb) =>
            requestObj = (request source)
            logEnrichedCb = (e, r) =>
                if not e
                    console.log "Saved #{(@fqtn source)} as #{gsPaths}"
                cb?(e, r)
            console.log "Extracting #{(@fqtn source)}"
            @_job requestObj, gsPaths, logEnrichedCb
        if table?
            (cb) =>
                (metaJob table, cb)
        else
            (source, cb) =>
                (metaJob source, cb)

    _trackDeps: (source, dest) ->
        @trackedDeps ?= []
        @trackedDeps.push
            source: source
            dest: dest

    withTableInfo: (table, cb) ->
        bigquery.tables.get { 
            auth: @jwt
            projectId: @config.projectId
            datasetId: @config.datasetId
            tableId: table
        }, cb

    _getLatestUpdate: (tables, cb) ->
        if typeof tables is 'string' then tables = [tables]

        results = 0
        updated = Date.now()

        for i, table of tables
            @withTableInfo table, (e, r) ->
                if e
                    cb e
                else
                    results++
                    updated = Math.min updated, r.lastModifiedTime
                    if results >= tables.length then cb null, updated

    _niceStatus: (status) ->
        (do (status.charAt 0).toUpperCase) + (do (status.slice 1).toLowerCase)

    _job: (jobConf, passOnArgument, cb) ->
        job =
            auth: @jwt
            projectId: @config.projectId
        job.resource = jobConf
        bigquery.jobs.insert job, (e, r) =>
            if e
                console.error e
                cb e
                return
            isCompleted = (jobId, _cb) =>
                bigquery.jobs.get { auth: @jwt, projectId: @config.projectId, jobId: jobId }, (_e, r) =>
                    if _e
                        console.info "Got error on job status fetch: #{_e}"
                        console.info 'Skipping'
                    else
                        if r?.status?.state is 'DONE'
                            ## Clear interval performing all the checks
                            if @intervals[jobId]?
                                clearInterval @intervals[jobId]
                                delete @intervals[jobId]
                                _cb?(r.status.errorResult)
                            else
                                # xxx glitch? how come it is sometimes called twice
                        else
                            if r?.statistics?.startTime?
                                elapsed = (new Date).getTime() - r.statistics.startTime
                                console.log "#{(@_niceStatus r.status?.state)} #{passOnArgument} (#{r.jobReference.jobId}) #{elapsed / 1000}"
                            else
                                console.log "#{(@_niceStatus r.status?.state)} #{passOnArgument} (#{r.jobReference.jobId})"

            intervalId = setInterval isCompleted, 2000, r.jobReference.jobId, (error) =>
                if not error
                    console.log "#{r.jobReference.jobId} returned #{passOnArgument}" ## this wont work, need a better reporting tool here that we have finished
                else
                    console.error error

                ## Notify the callback, that controls the flow, passing in the table name
                cb?(error, passOnArgument)

            @intervals[r.jobReference.jobId] = intervalId


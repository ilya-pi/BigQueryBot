
_ = require 'lodash'
$m = require './misc'

async = require 'async'
crypto = require 'crypto'
googleapis = require 'googleapis'
fs = require 'fs'
jade = require 'jade'
mandrill = require 'mandrill-api/mandrill'
http = require 'http'
https = require 'https'

storage = googleapis.storage 'v1'

BigQueryBot = (require './big_query_bot').BigQueryBot
Uploader = (require 's3-streaming-upload').Uploader

# -----------------------------------------------------------------------------------
# ExtendedBigQueryBot extends Big Query Bot functionality with actions not specific
# to BigQuery engine.
#
# In order to do so it might rely on otehr thirdrparty providers,
# such as Mandrill (for e-mail notification)
#

module.exports.ExtendedBigQueryBot =
class ExtendedBigQueryBot extends BigQueryBot

    scope: @__super__.scope.concat ['https://www.googleapis.com/auth/devstorage.read_only']

    constructor: (@queryBotConfig, @extendedBotConfig) ->
        super @queryBotConfig.serviceAccount, @queryBotConfig.privateKeyPath, @queryBotConfig
        @mandrill = new mandrill.Mandrill @extendedBotConfig.mandrill.key
        # CSS, JS and html template file used later on in graph generation
        @graphTemplate =
            template: fs.readFileSync (__dirname + '/views/dependency/template.html'), 'utf8'
            css: fs.readFileSync (__dirname + '/views/dependency/style.css'), 'utf8'
            js: fs.readFileSync (__dirname + '/views/dependency/d3-graph.js'), 'utf8'


    signurl: (gsPaths) ->
        expiry = (new Date).getTime() + 2 * 24 * 60 * 60 * 1000 # 48 hours
        accessId = @serviceAccount
        privateKey = fs.readFileSync @privateKeyPath, 'utf8'
        genUrls = (_gsPaths) =>
            url = (path) =>
                matched = /gs:\/\/([a-z\-\_]*)\/(.*)/.exec path
                if matched
                    key = matched[2]
                    bucketName = matched[1]
                    stringPolicy = "GET\n\n\n#{expiry}\n/#{bucketName}/#{key}"
                    signature = encodeURIComponent (((crypto.createSign 'sha256').update stringPolicy).sign privateKey, 'base64')
                    "https://#{bucketName}.commondatastorage.googleapis.com/#{key}?GoogleAccessId=#{accessId}&Expires=#{expiry}&Signature=#{signature}";
            if _.isArray _gsPaths
                (url path) for path in _gsPaths
            else
                (url _gsPaths)
        if gsPaths
            (cb) ->
                cb?(null, (genUrls gsPaths))
        else
            (_gsPaths, cb) ->
                cb?(null, (genUrls _gsPaths))


    # Filters exising days with Google Cloud Storage, incoming configuraiton is as follows
    #
    #   bucket: 'my-bucket'
    #   prefix: 'some/path/in/bucket'
    #   delimiter: '/'
    #   getDate: (path) -> path.substr 3, 8
    #   dates: ['20141125', '20141126'] -- might be chained from the previous steps
    existing: (options) ->
        metaExists = (opts, cb) =>
            opts.delimiter ?= '/'
            opts.getDate ?= (s) -> s

            req =
                auth: @jwt
                bucket: opts.bucket
                prefix: opts.prefix
                delimiter: opts.delimiter

            storage.objects.list req, (err, folders) ->
                if err
                    console.error err
                    cb err, null
                else
                    if not (Array.isArray folders.prefixes)
                        console.error 'No prefixes returned by GCS'
                        cb 'No prefixes returned by GCS', null
                    else
                        available = (opts.getDate prefix for prefix in folders.prefixes)
                        debugger
                        cb null, (_.intersection available, opts.dates)
                        
        # return a function that either receives just a callback (if no previous step passes on a source)
        # or a source and a callback
        () =>
            cb = _.last arguments
            options.dates ?= if arguments.length > 1 then arguments[0]

            if options.dates
                metaExists options, cb
            else
                cb 'No incoming dates in `existing` step'


    # Lists all path on Google Storage that match given wildcard
    #
    # i. e.:
    # bot.ls
    #    path: 'gs://lala/la*.tsv.gz'
    #
    # will give all files like:
    # gs://lala/la1.tsv.gz
    # gs://lala/la2.tsv.gz
    # gs://lala/la3.tsv.gz
    # ...
    # if they are present
    #
    ls: (options) ->
        metaLs = (opts, cb) =>
            path = opts.path
            bucket = (/gs:\/\/([^\/]*)/g.exec path)[1]
            prefix = (/gs:\/\/[^\/]*\/([^\*]*)/g.exec path)[1]
            req =
                auth: @jwt
                bucket: bucket
                prefix: prefix
            storage.objects.list req, (err, gsResult) ->
                if err
                    console.error err
                    cb err, null
                else
                    if not (Array.isArray gsResult.items)
                        console.error 'No items returned by GCS'
                        cb 'No items returned by GCS', null
                    else
                        cb null, ("gs://#{item.bucket}/#{item.name}" for item in gsResult.items)
        # return a function that either receives just a callback (if no previous step passes on a source)
        # or a source and a callback
        () =>
            cb = _.last arguments
            if not options?
                options = {}
            options.path ?= if arguments.length > 1 then arguments[0]

            if options.path
                metaLs options, cb
            else
                cb 'No incoming path passed to `ls` step'


    email: (recepient, hint, links) ->
        sendEMail = (links, cb) =>
            context = if _.isArray links then links else [links]
            message =
                subject: 'Notification'
                from_email: @extendedBotConfig.mandrill.from
                from_name: 'Big Query Bot'
                to: [
                    email: recepient
                    name: ''
                ]
                inline_css: true
            message.html = @report { result: context, hint: hint }
            @mandrill.messages.send
                message: message
                async: no
                ip_pool: 'Main Pool'
                send_at: null
            , (_r) ->
                    # Pass on the links, so they might be processed further down the pipe
                    cb?(null, links)
            , (e) ->
                    cb?(e, null)
        if links?
            (cb) ->
                console.log "Sending #{links} to #{recepient}"
                sendEMail links, cb
        else
            (_links, cb) ->
                console.log "Sending #{_links} to #{recepient}"
                sendEMail _links, cb

    report: jade.compileFile './src/views/report.jade'

    uploadToS3: (options) ->
        metaUpload = (opts, cb) =>
            uploadSingleUrl = (url, postfix, _cb) =>
                protocol = if (url.indexOf 'https') >=0 then https else http
                uploading = protocol.get url, (stream) =>
                    dest = opts.objectName.replace '\*', postfix
                    console.info "Uploading to s3://#{opts.bucket}/#{dest}"

                    upload = new Uploader
                        accessKey: @extendedBotConfig.s3.accessKey
                        secretKey: @extendedBotConfig.s3.secretKey
                        bucket: opts.bucket
                        objectName: dest
                        stream: stream
                    upload.setMaxListeners 0

                    upload.on 'completed', (err, res) ->
                        _cb null, url

                    upload.on 'failed', (err) ->
                        console.error 'Failed upload'
                        console.error err
                        _cb err, null

                uploading.on 'error', (e) ->
                    console.error 'Failed upload with error'
                    console.error e
                    _cb e.message, null

            if _.isArray opts.links
                uploadJobs = []
                for i, url of opts.links
                    ((_url, _prefix) ->
                        uploadJobs.push (_cb) ->
                            uploadSingleUrl _url, _prefix, _cb
                    )(url, i)
                async.series uploadJobs, cb
            else
                uploadSingleUrl opts.links, '', cb

        # return a function that either receives just a callback (if no previous step passes on a source)
        # or a source and a callback
        () =>
            cb = _.last arguments
            options.links ?= if arguments.length > 1 then arguments[0]

            if options.links
                metaUpload options, cb
            else
                cb 'No links to upload to s3'


    ## Generates an html file depicting all the dependencies there are in the graph
    graph: (filepath, passOn) ->
        writeGraph = (_cb, _passOn) =>
            nodes = []
            for edge in @trackedDeps
                nodes.push edge.dest
                if _.isArray edge.source
                    nodes.push d for d in edge.source
                else
                    nodes.push edge.source
            nodes = $m.unique nodes

            graphLinks = []
            for edge in @trackedDeps
                if _.isArray edge.source
                    graphLinks.push { target: (nodes.indexOf fromNode) , source: (nodes.indexOf edge.dest)} for fromNode in edge.source
                else
                    graphLinks.push { target: (nodes.indexOf edge.source) , source: (nodes.indexOf edge.dest)}

            graphNodes = []
            safeName = (name) ->
                ((name.replace /\//g, '_').replace /:/g, '_').replace /\*/g, '_'
            graphNodes.push { id: (safeName node) } for node in nodes

            graphData =
                directed: true
                multigraph: false
                graph: []
                nodes: graphNodes
                links: graphLinks

            data =
                css: @graphTemplate.css
                js : @graphTemplate.js
                title : 'Dependencies inbetween tables'
                graphData: JSON.stringify graphData, null

            fs.writeFile filepath, (_.template @graphTemplate.template, data), (err) ->
                if not err
                    console.log "Wrote #{nodes.length} nodes to graph at #{filepath}"
                _cb?(err, _passOn)

        if  passOn?
            (cb) =>
                writeGraph cb, passOn
        else
            (_passOn, cb) =>
                writeGraph cb, _passOn




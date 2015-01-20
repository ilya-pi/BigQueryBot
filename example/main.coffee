
async = require 'async'

ExtendedBigQueryBot = (require 'big-query-bot').ExtendedBigQueryBot

config =
    QueryBotConfiguration:

        serviceAccount: 'xxxxxxxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx@developer.gserviceaccount.com'
        privateKeyPath: './example/Your-Project-Name-xxxxxxxxxxxx.pem'
        projectId: 'your-project-id'

        datasetId: 'your-dataset-id' # You would normally override these two variables
        botId: 'your-bot-id'


    ExtendedBotConfiguration:

        mandrill:
            key: 'XXXXXXXXXXXXXXXXXXXXXX'   # API key to send e-mail through Mandrill
            from: 'no-reply@syour.company'     # e-mail that is used in a `from field`

        s3:
            accessKey: 'XXXXXXXXXXXXXXXXXXXX' # Amazon AWS Credentials
            secretKey: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'


bot = new ExtendedBigQueryBot config.QueryBotConfiguration, config.ExtendedBotConfiguration

timestamp = () ->
    do (new Date).getTime

## Full stack sample

bot.on 'ready', () ->
    async.waterfall [
        bot.load
            # name:       'import'
            gsPaths:    ['gs://biq-query-bot-sample/*']
            schema:     'line:STRING'

        bot.query
            #name:       'step1'
            sql:        'SELECT * FROM <in> LIMIT 200000'
            #source:     'sniper_by_ip'

        bot.query
            #name:       'step2'
            sql:        'SELECT * FROM <in> LIMIT 100000'
            #overwrite:  true

        bot.query
            # name:       'step3'
            sql:        'SELECT * FROM <in> LIMIT 50000'

        bot.graph './graphs/simple1.html'

        #bot.extract ["gs://biq-query-bot-sample/result#{do timestamp}.tsv.gz"]

        #do bot.signurl

        #bot.email 'rubengersons@screen6.io', null

    ], (_, _r) ->
        console.log 'Done'


## Parallel execution example

#bot.on 'ready', () ->
#    async.parallel [
#        bot.load
#            name:       'parallel_step_1'
#            gsPaths:    ['gs://biq-query-bot-sample/*']
#            schema:     'line:STRING'
#
#        bot.load
#            name:       'parallel_step_2'
#            gsPaths:    ['gs://biq-query-bot-sample/*']
#            schema:     'line:STRING'
#
#    ], (e, r) ->
#
#        async.waterfall [
#            #bot.email 'ilya.pimenov@gmail.com', 'sniper logs, imported from gs://', r
#
#            bot.query
#                sql:    'SELECT * FROM <in0>, <in1> LIMIT 200000'
#
#            bot.query
#                sql:    'SELECT * FROM <in> LIMIT 50000'
#
#            bot.graph './graphs/parallel1.html'
#
#            #bot.extract ["gs://biq-query-bot-sample/result#{do timestamp}.tsv.gz"]
#
#            #do bot.signurl
#
#        ], (_, _r) ->
#            console.log "Done, result url #{_r}"


## Sniper ETL

#bot.on 'ready', () ->
#    async.waterfall [
#        bot.load
#            gsPaths: ['gs://biq-query-bot-sample/*']
#            schema: 'line:STRING'
#
#        bot.query
#            file: './src/queries/etl/sniper/01-read-lines.sql'
#
#        bot.query
#            file: './src/queries/etl/sniper/02-add-geo-meta.sql'
#
#        bot.query
#            file: './src/queries/etl/sniper/03-join-with-geo.sql'
#
#        bot.graph './graphs/etl1.html'
#
#        bot.email 'ilya.pimenov@gmail.com', 'sniper etl data for period 10-11.2014 ...'
#
#    ], (_, _r) ->
#        console.log 'Done'

#async.waterfall [
#    sniper_etl
#    dedup
#], (_, _r) ->
#    console.log 'Done'


# % example with e-mail in the middle of the process
# % example with parallel exports with e-mails
# % example with file-queries

# .
# . try dedup on the sniper data, with export
# .
# . add excludes to all sensitive data/files and move to a separate repo
# . publish to npm (https://gist.github.com/coolaj86/1318304)
# . write suffisticated github documentation in markdown .README file
# .
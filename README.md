# BigQueryBot

BigBueryBot makes it easier to automate your query execution on top of Google Big Query.

## Setup

``` Bash
npm install big-query-bot

# or

"big-query-bot": "~0.2.x  >=0.2.0"

```

## Quick Example


``` CoffeeScript

BigQueryBot = (require 'big-query-bot').BigQueryBot

bot = BigQueryBot '<service-account>',
    '<path-to-pem-file (convert your .p12 to .pem following https://cloud.google.com/storage/docs/authentication)>',
    { projectId: '<projectId>', datasetId: '<datasetId>' }

bot.on 'ready', () ->
    async.waterfall [
        # Import all files from a given gs: path into a temporary table with name `import`
        bot.load
            name:       'import'
            gsPaths:    ['gs://biq-query-bot-sample/*']
            schema:     'line:STRING'

        # Run some query on top of table imported in the previous step
        bot.query
            name:       'step1'
            sql:        'SELECT * FROM <in> LIMIT 200000'
            #source:     'sniper_by_ip' <-- uncomment to make this step use a different table instead the one created at the previoud step

        bot.query
            #name:       'step2'
            sql:        'SELECT * FROM <in> LIMIT 100000'
            #overwrite:  true <-- uncommment to overwrite the table even if already exists

        bot.query
            # name:       'step3'
            sql:        'SELECT * FROM <in> LIMIT 50000'

        # Extract resulting table from the previous step back to Google Cloud Storage
        bot.extract ["gs://biq-query-bot-sample/result#{do timestamp}.tsv.gz"]

    ], (_, _r) ->
        console.log 'Done'
```

## Extended Example with Parallel execution, execution graph, e-mail notification and 48h signed url

``` CoffeeScript
bot.on 'ready', () ->
    async.parallel [
        # Load lines from first file in parallel
        bot.load
            gsPaths:    ['gs://biq-query-bot-sample/*']
            schema:     'line:STRING'

        # Load lines from second file in parallel
        bot.load
            gsPaths:    ['gs://biq-query-bot-sample/*']
            schema:     'line:STRING'

    ], (e, r) ->

        async.waterfall [
            # Notify me that the lines were imported from the Google Cloud Storager
            # with an e-mail containing custom message and tablenemas
            # for the imported lines
            bot.email 'ilya.XXX.pimenov@gmail.com', 'Logs, imported from gs://', r

            # Run query that takes both tables as input
            bot.query
                sql:    'SELECT * FROM <in0>, <in1> LIMIT 200000'

            # Run query that is stored elsewhere on the filesystem
            bot.query
                file: './my-query.sql'

            # Render an .html graphs of all the dependencies
            bot.graph './graphs/parallel.html'

            # Estract resulting table to a tsv.gz file on Google Cloud Storage
            bot.extract ["gs://biq-query-bot-sample/result#{do timestamp}.tsv.gz"]

            # Created a signed url with the a 48 hours available link to the exported tsv.gz file
            do bot.signurl

        ], (_, _r) ->
            console.log "Done, result url #{_r}"
```

## Documentation

### BigQueryBot

**BigQueryBot** provides [async](https://github.com/caolan/async) ready functions to control you [Big Query](https://cloud.google.com/bigquery/) execution flow.

``` CoffeeScript

BigQueryBot = (require 'big-query-bot').BigQueryBot

bot = BigQueryBot '<service-account>',
    '<path-to-pem-file (convert your .p12 to .pem following https://cloud.google.com/storage/docs/authentication)>',
    { projectId: '<projectId>', datasetId: '<datasetId>' }
```

Features:

* [`load`](#load)
* [`query`](#query)
* [`extract`](#extract)

### ExtendedBigQueryBot

**ExtendedBigQueryBot** provides [async](https://github.com/caolan/async) ready functions that extend your [Big Query](https://cloud.google.com/bigquery/) execution flow.

``` CoffeeScript

ExtendedBigQueryBot = (require 'big-query-bot').ExtendedBigQueryBot

QueryBotConfiguration =
    serviceAccount: '<service-account>'
    privateKeyPath: '<path-to-pem-file (convert your .p12 to .pem following https://cloud.google.com/storage/docs/authentication)>'
    projectId: '<your project id>'
    datasetId: '<your dataset id>'

ExtendedBotConfiguration =
    mandrill: # [Optional] Only if you want to send e-mail notifications
        key: '<your mandrill key>'
        from: '<email to send emails from>'

    s3: # [Optional] Only if you want to upload results to Amazon S3
        accessKey: 'XXXXXXXXXXXXXXXXXXXX' # Amazon AWS Credentials
        secretKey: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'

bot = new ExtendedBigQueryBot QueryBotConfiguration, ExtendedBotConfiguration
```

--

## BigQueryBot

<a name="load" />
### load

<a name="query" />
### query


<a name="extract" />
### extract


## ExtendedBigQueryBot
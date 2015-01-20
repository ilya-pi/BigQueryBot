# BigQueryBot

BigQueryBot makes it easier to automate your query execution on top of Google Big Query.

Based on [Big Query API v2](https://cloud.google.com/bigquery/docs/reference/v2)

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

* [`source`](#source)
* [`with`](#with)
* [`flatten`](#flatten)
* [`parallel`](#parallel)
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

<a name="source" />
### source(['table1', 'table2', ...])

Throw `['table1', 'table2', ...]` as source for current context, they will be passed on to the next statement.

```
bot.on 'ready', () ->
    async.waterfall [

        bot.source 'my-lovely-initial-table'

        ...

    ]
```

Use an array or a single string item.

<a name="with" />
### with(['some-other-table'])

Throw in `['some-other-table']` into current context. So if you had `table1` in there,
after you will have `['table1', 'some-other-table']`. Always appended at the end of
current array of string in the context.

```
bot.on 'ready', () ->
    async.waterfall [

        ...

        bot.with 'my-second-lovely-initial-table'

        ...

    ]
```

Use an array or a single string item.

<a name="flatten" />
### flatten

Flattens current array in the context. With a mix of sequential and parallel statements, veyr often you might
end up with a structure like `['table1', 'table2', ['table21', 'table22', ['table31'], 'table23']]`, this will
flatten it into `['table1', 'table2', 'table21', 'table22', 'table31', 'table23']` which will enable it in further
query substitutions.

```
bot.on 'ready', () ->
    async.waterfall [

        ...

        bot.flatten

        ...

    ]
```

<a name="parallel" />
### parallel

Flow control helper, to take away the burden of writing parallel query exeuction on Big Query.

Takes in array of arrays of steps. Launches waterfall processing of each array in parallel to each other on the top level.

i.e.

```
bot.on 'ready', () ->
    async.waterfall [

        bot.source 'some-initial-table'

        bot.parallel [
            [
                step1_1
                step1_2
                step1_3
            ]
            [
                step2_1
                step2_2
            ]
        ]

        ...

    ]
```

results in `[ <step1_3 output>, <step2_2 output>]`

Each first step in the array of parallel steps (`step1_1` and `step2_1` in the example) receives the same current
context (which is 'some-initial-table' in the example).

<a name="load" />
### load

Runs `load` job, that fetches data from gs:// with a given schema
Currently only supports deprecated schema format, the "oneliner".

```
bot.on 'ready', () ->
    async.waterfall [

        bot.load
            name:   'initial-import' # [Optional] If not provided will be generated by Big Query Bot
            gsPaths:    ['gs://biq-query-bot-sample/*'] # [Optional/Required] Google Cloud Storage paths to import from.
                                                        # If not provided, the current context (array of strings or a string,
                                                        # depending on what is in the context) will be used as a source
            schema:     'line:STRING' # [Required] Schema, otherwise an empty schema is assumed, which results in an empty table

        ...

    ]
```

Current defaults (all can be overriden with incoming arguments) are:

| name | value|
|:----:|:----:|
| schema | '' |
| overwrite | false |
| delimiter | '\t' |
| sourceFormat | 'CSV' |
| maxBadRecords | 1000 |
| skipLeadingRows | 0 |

For a better insight on these arguments refer to the [Big Query API v2: Jobs: Load](https://cloud.google.com/bigquery/docs/reference/v2/jobs#configuration.load)

<a name="query" />
### query

Runs `query` on top of `source` with query name/target table name `name`

```
bot.on 'ready', () ->
    async.waterfall [

        bot.query
            name:   'my-query' # [Optional] name of the query and part of the destination table name
            source: 'source-table' # [Optional/Required] Tables that will be substituted into the query itself
                                   # If not present, current context will be assumed as source
            overwrite: false # Whether to overwrite existing table or not, comes very handy on repeated calculations
            sql: 'SELECT * FROM <in> LIMIT 100000' # [Optional/Required] Either `sql:` of `file:` should be present
            file: 'file-with-my-query.sql' # [Optional/Required] Either `sql:` or `file:` should be present

        ...

    ]
```

For a better insight on the function refer to [Big Query API v2: Jobs: Query](https://cloud.google.com/bigquery/docs/reference/v2/jobs#configuration.query)

<a name="extract" />
### extract

Runs table `extract` from Big Query into Google Cloud Storage

```
bot.on 'ready', () ->
    async.waterfall [

        ...

        bot.extract ["gs://bqb_export/my-extract-name_*.tsv.gz"]

    ]
```

Puts extract destionation into the context.

## ExtendedBigQueryBot

<a name="source" />
### source

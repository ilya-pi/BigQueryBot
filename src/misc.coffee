
fs = require 'fs'
http = require 'http'
https = require 'https'


module.exports.unique =
unique = (array) ->
    output = {}
    output[array[key]] = array[key] for key in [0...array.length]
    value for key, value of output

module.exports.download =
download = (url, dest, cb) ->
    file = fs.createWriteStream dest
    protocol = if (url.indexOf 'https') >=0 then https else http
    protocol.get url, (response) ->
        response.pipe file
        file.on 'finish', () ->
            file.close cb

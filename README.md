# New Relic Logstash Output Plugin

This is a plugin for [Logstash](https://github.com/elastic/logstash) that outputs logs to New Relic.


## Installation

* Tell Logstash where to find our plugin
  * Find the Logstash Gemfile (For example: `/usr/share/logstash/Gemfile` in some Linux installs)
  * Add the following to the top of Logstash's Gemfile: `source "https://1keEQc-cII8DjYRJVdpUXAw6DUPV6JmjpE@repo.fury.io/nrsf"`
* Install the plugin: `logstash-plugin install --no-verify logstash-output-newrelic-internal`

## Configuration

Add the following block to your logstash.conf (with your specific API Insert key), then restart Logstash.
There are other optional configuration properties, see below.

Example:
```rb
output {
  newrelic_internal {
    api_key => "<API_INSERT_KEY>"
  }
}
```

Getting the API Insert Key:
`https://insights.newrelic.com/accounts/<ACCOUNT_ID>/manage/api_keys`


### Required plugin configuration

| Property | Description |
|---|---|
| api_key | your New Relic API Insert key |

### Optional plugin configuration

| Property | Description | Default value |
|---|---|---|
| concurrent_requests | The number of threads to make requests from | 1 |
| retries | The maximum number of times to retry a failed request, exponentially increasing delay between each retry | 5 |
| retry_seconds | The inital delay between retries, in seconds | 5 |
| max_delay | The maximum delay between retries, in seconds | 30 |
| base_uri | New Relic ingestion endpoint | https://log-api.newrelic.com/log/v1 |

## Testing

An easy way to test the plugin is to make sure Logstash is getting input from a log file you can write to. Something like this in your logstash.conf:
```
input {
  file {
    path => "/path/to/your/log/file"
  }
}
```
* Restart Logstash
* Append a test log message to your log file: `echo "test message" >> /path/to/your/log/file`
* Search New Relic Logs for `"test message"`

## Notes

This plugin will attempt to parse any 'message' attribute as JSON -- if it is JSON, its JSON attributes will be added to the event.

For example, the events:
```
[{
  "message": "some message",
  "timestamp": 1531414060739
},
{
  {"message":"some_message","timestamp":"12897439", "compound" :"{\"a\":111, \"b\":222}"},
}]
```

Will be output as:
```
[{  "message": "{\"key\": \"value1\", \"compound\": {\"sub_key\": \"value2\"}}",
  "key": "value1",
  "compound": {
    "sub_key": "value2"
  },
  "other": "other value"
}]
```

## Development

See [DEVELOPER.md](DEVELOPER.md)

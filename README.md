# New Relic Logstash Output Plugin

This is a plugin for [Logstash](https://github.com/elastic/logstash) that outputs logs to New Relic.

## Installation
Install the New Relic Logstash plugin, use the following command:</br>
`logstash-plugin install logstash-output-newrelic-logging`

## Configuration

Add the following block to your logstash.conf (with your specific API Insert key), then restart Logstash.
There are other optional configuration properties, see below.

Get your API Insert Key:
`https://insights.newrelic.com/accounts/<ACCOUNT_ID>/manage/api_keys`

Example:
```rb
output {
  newrelic_internal {
    api_key => "<API_INSERT_KEY>"
  }
}
```


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
| base_uri | New Relic ingestion endpoint | insights-collector.newrelic.com/logs/v1 |
| event_type | The New Relic event type | 'log' |

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
  "other": "other value"
},
{
  "message": "{\"key\": \"value1\", \"compound\": {\"sub_key\": \"value2\"}}",
  "other": "other value"
}]
```

Will be output as:
```
[{
  "message": "some message",
  "other": "other value"
},
{
  "message": "{\"key\": \"value1\", \"compound\": {\"sub_key\": \"value2\"}}",
  "key": "value1",
  "compound": {
    "sub_key": "value2"
  },
  "other": "other value"
}]
```

## Development

See [DEVELOPER.md](DEVELOPER.md)

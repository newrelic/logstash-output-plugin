# New Relic Logstash Output Plugin

This is a plugin for [Logstash](https://github.com/elastic/logstash) that outputs logs to New Relic.

## Installation
Install the New Relic Logstash plugin using the following command:</br>
`logstash-plugin install logstash-output-newrelic`

### Versions
Versions of this plugin less than 1.0.0 are unsupported.

## Configuration

Add one of the following blocks to your logstash.conf (with your specific key), then restart Logstash.
There are other optional configuration properties, see below.

### Using API Insert Key

Get your API Insert Key:
`https://insights.newrelic.com/accounts/<ACCOUNT_ID>/manage/api_keys`

Example:
```rb
output {
  newrelic {
    api_key => "<API_INSERT_KEY>"
  }
}
```

### Using License Key

Get your License Key:
`https://rpm.newrelic.com/accounts/<ACCOUNT_ID>`

Example:
```rb
output {
  newrelic {
    license_key => "<LICENSE_KEY>"
  }
}
```

### Required plugin configuration

Exactly one of the following:

| Property | Description |
|---|---|
| api_key | your New Relic API Insert key |
| license_key | your New Relic License key |

### Optional plugin configuration

| Property | Description | Default value |
|---|---|---|
| concurrent_requests | The number of threads to make requests from | 1 |
| base_uri | New Relic ingestion endpoint | https://log-api.newrelic.com/log/v1 |
| enable_retry | Enable/Disable retry policy | true |
| max_retry | Number of retries made every second before dropping logs. | 3 |

### EU plugin configuration

When using this plugin in the EU override the base_uri with `https://log-api.eu.newrelic.com/log/v1`

## Testing

An easy way to test the plugin is to make sure Logstash is getting input from a log file you 
can write to. Something like this in your logstash.conf:
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

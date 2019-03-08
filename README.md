# New Relic Logstash Output Plugin

This is a plugin for [Logstash](https://github.com/elastic/logstash) that outputs logs to New Relic.

## Installation

```sh
bin/logstash-plugin install logstash-output-newrelic.gem
```

## Configuration

### Add to Logstash

Add the following block to your logstash.conf (with your specific account ID and API key), then restart Logstash.

Example:
```rb
output {
  newrelic {
    account_id => "12345"
    api_key => "k01bkEka882bkj21340ndfinsENatSQ9"
  }
}
```

### Required plugin configuration

| Property | Description |
|---|---|
| api_key | your New Relic API key |
| account_id | your New Relic account ID |

### Optional plugin configuration

| Property | Description | Default value |
|---|---|---|
| concurrent_requests | The number of threads to make requests from | 1 |
| retries | The maximum number of times to retry a failed request, exponentially increasing delay between each retry | 5 |
| retry_seconds | The inital delay between retries, in seconds | 5 |
| max_delay | The maximum delay between retries, in seconds | 30 |
| base_uri | New Relic ingestion endpoint | 'insights-collector.newrelic.com/logs/v1' |
| event_type | The New Relic event type | 'log' |


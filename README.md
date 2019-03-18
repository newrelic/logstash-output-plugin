# New Relic Logstash Output Plugin

This is a plugin for [Logstash](https://github.com/elastic/logstash) that outputs logs to New Relic.

## Installation

```sh
logstash-plugin install logstash-output-newrelic-<VERSION_NUMBER>.gem
```

## Configuration

Add the following block to your logstash.conf (with your specific account ID and API key), then restart Logstash.
There are other optional configuration properties, see below.

Example:
```rb
output {
  newrelic {
    account_id => "<ACCOUNT_ID>"
    api_key => "<API_INSERT_KEY>"
  }
}
```

Getting the API Insert Key:
`https://staging-insights.newrelic.com/accounts/<ACCOUNT_ID>/manage/api_keys`


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

## Development 

See [DEVELOPER.md](DEVELOPER.md)

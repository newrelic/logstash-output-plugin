[![Community Plus header](https://github.com/newrelic/opensource-website/raw/master/src/images/categories/Community_Plus.png)](https://opensource.newrelic.com/oss-category/#community-plus)

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

### Use license key

Get your [license key](https://docs.newrelic.com/docs/apis/getting-started/intro-apis/understand-new-relic-api-keys#ingest-license-key):
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

Requires: 

| Property | Description |
|---|---|
| license_key | your New Relic [license key](https://docs.newrelic.com/docs/apis/getting-started/intro-apis/understand-new-relic-api-keys#ingest-license-key) |

### Optional plugin configuration

| Property | Description | Default value |
|---|---|---|
| concurrent_requests | The number of threads to make requests from | 1 |
| base_uri | New Relic ingestion endpoint | https://log-api.newrelic.com/log/v1 |
| max_retries | Maximum number attempts to retry to send a message. If set to 0, no re-attempts will be made. | 3 |

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

## Community

New Relic hosts and moderates an online forum where customers can interact with New Relic employees as well as other customers to get help and share best practices. Like all official New Relic open source projects, there's a related Community topic in the New Relic Explorers Hub: [Log forwarding](https://discuss.newrelic.com/tag/log-forwarding)

## A note about vulnerabilities

As noted in our [security policy](../../security/policy), New Relic is committed to the privacy and security of our customers and their data. We believe that providing coordinated disclosure by security researchers and engaging with the security community are important means to achieve our security goals.

If you believe you have found a security vulnerability in this project or any of New Relic's products or websites, we welcome and greatly appreciate you reporting it to New Relic through [HackerOne](https://hackerone.com/newrelic).

If you would like to contribute to this project, review [these guidelines](https://opensource.newrelic.com/code-of-conduct/).

## License
logstash-output-plugin is licensed under the [Apache 2.0](http://apache.org/licenses/LICENSE-2.0.txt) License.

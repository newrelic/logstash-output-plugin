# Developing the plugin

**TODO: this needs to be fleshed out, make sure it works**
 
* To get started, you'll need JRuby with the Bundler gem installed.
  * `rbenv `
  * `gem install bundle`
* Install dependencies: `bundle install`
* Run tests: `bundle exec rspec`
* Build: `gem build logstash-output-newrelic.gemspec`

## Installation

```sh
bin/logstash-plugin install logstash-output-newrelic.gem
```
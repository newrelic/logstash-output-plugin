# Developing the plugin
 
* To get started, you'll need JRuby with the Bundler gem installed.
  * `rbenv install jruby-9.2.5.0`
  * `jruby -S gem install bundler`
* Install dependencies: `jruby -S bundle install`
* Run tests: `jruby -S bundle exec rspec`
* Build: `jruby -S gem build logstash-output-newrelic.gemspec`

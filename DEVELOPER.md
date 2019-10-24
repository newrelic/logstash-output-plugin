# Developing the plugin

# Getting started

* Install JRuby: `rbenv install jruby-9.2.5.0`
* Use that JRuby: `rbenv local jruby-9.2.5.0`
* Install Bundler gem: `jruby -S gem install bundler`

# Developing

* Install dependencies: `jruby -S bundle install`
* Write tests and production code!
* Bump version: edit version file `version.rb`
* Run tests: `jruby -S bundle exec rspec`
* Build the gem: `jruby -S gem build logstash-output-newrelic.gemspec`

# Testing it with a local Logstash install

Note: you may need to run the following commands outside of your checkout, since these should not
be run with the JRuby version that you've configured your checkout to use (by using rbenv). 

* Remove previous version: `logstash-plugin remove logstash-output-newrelic`
* Add new version: `logstash-plugin install logstash-output-newrelic-<version>.gem`
* Restart logstash: For Homebrew: `brew services restart logstash`
* Cause a change that you've configured Logstash to pick up (for instance, append to a file you're having it monitor)
* Look in `https://one.newrelic.com/launcher/logger.log-launcher` for your log message
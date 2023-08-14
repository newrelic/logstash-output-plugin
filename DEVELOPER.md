# Developing the plugin

# Getting started

**NOTE for Mac M1 users: ** note that `jruby-9.3.3.0` is the first jruby compatible with Mac M1 processors. In order to
develop the plugin locally, we recommend using this version. Nevertheless, when building the gem file (in the GH workflows),
we keep using jruby 9.2.13.0 in order to be backwards-compatible with older Logstash versions.

* Install RVM:
  * `command curl -sSL https://rvm.io/pkuczynski.asc | gpg --import -`
  * `\curl -sSL https://get.rvm.io | bash -s stable`
  * Reopen the terminal for `rvm` command to be available
* Install JRuby: `rvm install jruby-9.2.13.0`.
* Use that JRuby: `rvm use jruby-9.2.13.0`
* Ensure your terminal is using Java 11.
* Install Bundler gem: `jruby -S gem install bundler`

# Developing

* Ensure you have `logstash` installed locally (required for unit testing): `brew install logstash`
* Ensure your `logstash` path matches the one in `Gemfile` 
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
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
* Build the gem: `jruby -S gem build logstash-output-newrelic-internal.gemspec`

## Pushing changes to the public repo
After updating the New Relic repo with changes, changes will need to be pushed to the public GitHub repo at: https://github.com/newrelic/newrelic-fluent-bit-output

* `git remote add public git@github.com:newrelic/newrelic-fluent-bit-output.git`
* `git push public master:name-of-branch-to-create`
* Create a PR from that branch in https://github.com/newrelic/newrelic-fluent-bit-output
* Get the PR reviewed, merged, and delete the branch!

# Testing it with a local Logstash install

* Remove previous version: `logstash-plugin remove logstash-output-newrelic-internal`
* Add new version: `logstash-plugin install logstash-output-newrelic-internal-<version>.gem `
* Restart logstash: For Homebrew: `brew services restart logstash`
* Cause a change that you've configured Logstash to pick up (for instance, append to a file you're having it monitor)
* Look in `https://staging-one.newrelic.com/launcher/logger.log-launcher` for your log message

# Push changes to RubyGems
After updating the source code and gem version in `version.rb`, push the changes to RubyGems. Note, you must be a gem owner to publish changes on [RubyGems.org](https://rubygems.org/profiles/NR-LOGGING)

* Build the gem: `gem build logstash-output-newrelic.gemspec`
* Publish the gem: `gem push logstash-output-newrelic-logging-<VERSION>.gem` with the updated version (ex: `gem push logstash-output-newrelic-logging-0.2.16.gem`)

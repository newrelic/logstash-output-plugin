# Developing the plugin
 
# Getting started

* Install JRuby: `rbenv install jruby-9.2.5.0`
* Install Bundler gem: `jruby -S gem install bundler`

# Developing

* Install dependencies: `jruby -S bundle install`
* Write tests and production code!
* Bump version: edit version field in `logstash-output-newrelic-internal.gemspec`
* Run tests: `jruby -S bundle exec rspec`
* Build the gem: `jruby -S gem build logstash-output-newrelic-internal.gemspec`

# Testing it with a local Logstash install
* Remove previous version: `logstash-plugin remove logstash-output-newrelic-internal`
* Add new version: `logstash-plugin install logstash-output-newrelic-internal-<version>.gem `
* Restart logstash: For Homebrew: `brew services restart logstash`
* Cause a change that you've configured Logstash to pick up (for instance, append to a file you're having it monitor)
* Look in `https://wanda-ui.staging-service.newrelic.com/launcher/logger.log-launcher` for your log message

# Deploying to Gemfury

After merging to master you must also push the code to Gemfury, which is where customers will get our gem from.
* Get the version you just merged to master in Github
  * `git checkout master`
  * `git pull`
* Push the new master to Gemfury
   * Add Gemfury as remote (only needs to be done once): `git remote add fury https://<your-gemfury-username>@git.fury.io/nrsf/logstash-output-newrelic.git`
   * Push the new commits to Gemfury: `git push fury master`
   * For the password, use the "Personal full access token" seen here https://manage.fury.io/manage/newrelic/tokens/shared
   * Make sure you see your new code show up here: `https://manage.fury.io/dashboard/nrsf`
   * TODO: should this be part of the build step in Jenkins?
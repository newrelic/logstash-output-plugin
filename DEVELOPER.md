# Developing the plugin
 
* To get started, you'll need JRuby with the Bundler gem installed.
  * `rbenv install jruby-9.2.5.0`
  * `jruby -S gem install bundler`
* Install dependencies: `jruby -S bundle install`
* Run tests: `jruby -S bundle exec rspec`
* Build: `jruby -S gem build logstash-output-newrelic.gemspec`
* Push code to Gemfury:
  * `git remote add fury https://<your-gemfury-username>@git.fury.io/nrsf/logstash-output-newrelic.git`
  * `git push fury master`
  * For the password, use the "Personal full access token" seen here https://manage.fury.io/manage/newrelic/tokens/shared
  * TODO: should this be part of the build step in Jenkins?

source 'https://rubygems.org'
gemspec

# The following is required to locally develop this plugin. Note that this Gemfile is NOT used when building the gem
# file for this plugin (see merge-to-master.yml), only when unit testing. When unit-testing, we need to have logstash-core
# in our local machine, given that the logstash-core GEM has not been published since 5.6.0.
# See: https://github.com/elastic/logstash/pull/14229 https://github.com/elastic/logstash/issues/14203
# And: https://github.com/elastic/logstash/pull/14229

logstash_path = ENV['LOGSTASH_PATH'] || '/opt/homebrew/Cellar/logstash/8.9.0/libexec'

if Dir.exist?(logstash_path)
  gem 'logstash-core', :path => "#{logstash_path}/logstash-core"
  gem 'logstash-core-plugin-api', :path => "#{logstash_path}/logstash-core-plugin-api"
end

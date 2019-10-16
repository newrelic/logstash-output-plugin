lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'logstash/outputs/newrelic_version/version'

Gem::Specification.new do |s|
  s.name          = 'logstash-output-newrelic'
  s.version       = LogStash::Outputs::NewRelicVersion::VERSION
  s.licenses      = ['Apache-2.0']
  s.summary       = "Sends Lostash events to New Relic"
  s.homepage      = 'https://github.com/newrelic/logstash-output-plugin'
  s.authors       = ['New Relic Logging Team']
  s.email         = 'logging-team@newrelic.com'
  s.require_paths = ['lib']

  # Files
  s.files = Dir['lib/**/*','spec/**/*','vendor/**/*','*.gemspec','*.md','CONTRIBUTORS','Gemfile','LICENSE','NOTICE.TXT']
   # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "output" }

  # Gem dependencies
  s.add_runtime_dependency "logstash-core-plugin-api", "~> 2.0"
  s.add_runtime_dependency "logstash-codec-plain"
  s.add_development_dependency "logstash-devutils"
  s.add_development_dependency "webmock"
  s.add_development_dependency "rspec"
  s.add_development_dependency "rspec-wait"
  s.add_development_dependency "rspec_junit_formatter"
end

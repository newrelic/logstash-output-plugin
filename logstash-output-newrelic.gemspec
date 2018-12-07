Gem::Specification.new do |s|
  s.name          = 'logstash-output-newrelic'
  s.version       = '0.1.4'
  s.licenses      = ['Apache-2.0']
  s.summary       = 'Forwards logs as custom events to insights'
  s.description   = 'Gzips up to and decorates logstash events to be properly formatted as custom events'
  s.homepage      = 'https://source.datanerd.us/ifridge/logstash-output-newrelic'
  s.authors       = ['Ian Fridge']
  s.email         = 'ifridge@newrelic.com'
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
end

# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/newrelic"
require "logstash/codecs/plain"
require "logstash/event"
require "webmock/rspec"

describe LogStash::Outputs::Newrelic do

  let (:api_key) { 'someAccountKey' }
  let (:account_id) { '123' }
  let (:base_uri) { 'https://testing-example-collector.com' }
  let (:simple_config) {
    {
      'api_key' => api_key,
      'account_id' => account_id,
      'base_uri' => base_uri
    }
  }

   before { 
     @newrelic_output = LogStash::Plugin.lookup('output', 'newrelic').new(simple_config)
     @newrelic_output.register
   }

   after { 
     @newrelic_output&.shutdown
   }

  context 'simple event' do
      it 'makes POST call to collector' do
          stub_request(:any, base_uri).
            to_return(status: 200)

          event = LogStash::Event.new({'message' => 'Test message'})
          @newrelic_output.multi_receive([event])

          wait_for(a_request(:post, base_uri)).to have_been_made
      end
  end
end

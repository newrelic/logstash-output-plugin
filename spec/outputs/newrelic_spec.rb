# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/newrelic"
require "logstash/codecs/plain"
require "logstash/event"
require "webmock/rspec"


describe LogStash::Outputs::Newrelic do

  let (:api_key) { 'lH7pIMEpl5oCbNs8g1jTN4VllAITqtxQ' }
  let (:account_id) { '756053' }
  let (:base_uri) { 'https://testing-insights-collector.newrelic.com' }

  let (:simple_config) {
    {
      'api_key' => api_key,
      'account_id' => account_id,
      'base_uri' => base_uri
    }
  }


  let (:event) {
    LogStash::Event.new(
    {
      'message' => 'Test message - Brian456789098999'
    })
   }

  context 'simple call' do
      it 'does not blow up' do
          stub_request(:any, base_uri).
            to_return(body: "abc", status: 500)

          newrelic_output = LogStash::Plugin.lookup('output', 'newrelic')
                  .new(simple_config)
          newrelic_output.register
          newrelic_output.multi_receive([event])
          newrelic_output.shutdown
          sleep 5
          expect(a_request(:post, base_uri)).to have_been_made
      end
  end
end

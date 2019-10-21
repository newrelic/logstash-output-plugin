# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/newrelic"
require "logstash/outputs/newrelic_version/version"
require "logstash/codecs/plain"
require "logstash/event"
require "webmock/rspec"
require "zlib"

describe LogStash::Outputs::NewRelic do
  let (:base_uri) { "https://testing-example-collector.com" }
  let (:retry_seconds) { 0 }
  # Don't sleep in tests, to keep tests fast. We have a test for the method that produces the sleep duration between retries.
  let (:max_delay) { 0 }
  let (:retries) { 3 }
  let (:license_key) { 'cool-guy' }
  let (:simple_config) {
    {
      "base_uri" => base_uri,
      "license_key" => license_key
    }
  }


  before(:each) do
    @newrelic_output = LogStash::Plugin.lookup("output", "newrelic").new(simple_config)
    @newrelic_output.register
  end

  after(:each) do
    if @newrelic_output
      @newrelic_output.shutdown
    end
  end
  context "license key tests" do
    it "sets license key when given in the header" do
      stub_request(:any, base_uri).to_return(status: 200)

      event = LogStash::Event.new({:message => "Test message" })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)
        .with(headers: {
                "X-License-Key" => license_key,
                "X-Event-Source" => "logs",
                "Content-Encoding" => "gzip",
              })).to have_been_made
    end
  end
end

describe LogStash::Outputs::NewRelic do
  let (:api_key) { "someAccountKey" }
  let (:base_uri) { "https://testing-example-collector.com" }
  let (:retry_seconds) { 0 }
  # Don't sleep in tests, to keep tests fast. We have a test for the method that produces the sleep duration between retries.
  let (:max_delay) { 0 }
  let (:retries) { 3 }
  let (:simple_config) {
    {
      "api_key" => api_key,
      "base_uri" => base_uri,
    }
  }

  # An arbitrary time to use in these tests, with different representations
  class FixedTime
    MILLISECONDS = 1562888528123
    ISO_8601_STRING_TIME = '2019-07-11T23:42:08.123Z'
    LOGSTASH_TIMESTAMP = LogStash::Timestamp.coerce(ISO_8601_STRING_TIME)
  end

  def gunzip(bytes)
    gz = Zlib::GzipReader.new(StringIO.new(bytes))
    gz.read
  end

  def single_gzipped_message(body)
    message = JSON.parse(gunzip(body))[0]['logs']
    expect(message.length).to equal(1)
    message[0]
  end

  def multiple_gzipped_messages(body)
    JSON.parse(gunzip(body))
  end

  def now_in_milliseconds()
    (Time.now.to_f * 1000).to_i # to_f gives seconds with a fractional portion
  end

  def within_five_seconds_of(time_in_millis, expected_in_millis)
    five_seconds_in_millis = 5 * 1000
    (time_in_millis - expected_in_millis).abs < five_seconds_in_millis
  end


  before(:each) do
    @newrelic_output = LogStash::Plugin.lookup("output", "newrelic").new(simple_config)
    @newrelic_output.register
  end

  after(:each) do
    if @newrelic_output
      @newrelic_output.shutdown
    end
  end

  context "validation of config" do
    it "requires api_key" do
      no_api_key_config = {
      }
      output =  LogStash::Plugin.lookup("output", "newrelic").new(no_api_key_config)
      expect { output.register }.to raise_error LogStash::ConfigurationError
    end
  end

  context "request headers" do
    it "all present" do
      stub_request(:any, base_uri).to_return(status: 200)

      event = LogStash::Event.new({:message => "Test message" })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)
        .with(headers: {
                "X-Insert-Key" => api_key,
                "X-Event-Source" => "logs",
                "Content-Encoding" => "gzip",
              })).to have_been_made
    end
  end

  context "request body" do

    it "message contains plugin information" do
      stub_request(:any, base_uri).to_return(status: 200)

      event = LogStash::Event.new({ :message => "Test message" })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)
      .with { |request|
        data = multiple_gzipped_messages(request.body)[0]
        data['common']['attributes']['plugin']['type'] == 'logstashes' &&
        data['common']['attributes']['plugin']['version'] == LogStash::Outputs::NewRelicVersion::VERSION })
      .to have_been_made
    end

    it "all other fields passed through as is" do
      stub_request(:any, base_uri).to_return(status: 200)

      event = LogStash::Event.new({ :message => "Test message", :other => "Other value" })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)
        .with { |request|
          message = single_gzipped_message(request.body)
          message['message'] == 'Test message' &&
          message['attributes']['other'] == 'Other value' })
        .to have_been_made
    end

    it "JSON object 'message' field is not parsed" do
      stub_request(:any, base_uri).to_return(status: 200)

      message_json = '{ "in-json-1": "1", "in-json-2": "2", "sub-object": {"in-json-3": "3"} }'
      event = LogStash::Event.new({ :message => message_json, :other => "Other value" })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)
        .with { |request|
          message = single_gzipped_message(request.body)
          message['message'] == message_json &&
          message['attributes']['other'] == 'Other value' })
        .to have_been_made
    end

    it "JSON array 'message' field is not parsed, left as is" do
      stub_request(:any, base_uri).to_return(status: 200)

      message_json_array = '[{ "in-json-1": "1", "in-json-2": "2", "sub-object": {"in-json-3": "3"} }]'
      event = LogStash::Event.new({ :message => message_json_array, :other => "Other value" })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)
        .with { |request|
          message = single_gzipped_message(request.body)
          message['message'] == message_json_array &&
          message['attributes']['other'] == 'Other value' })
        .to have_been_made
    end

    it "JSON string 'message' field is not parsed, left as is" do
      stub_request(:any, base_uri).to_return(status: 200)

      message_json_string = '"I can be parsed as JSON"'
      event = LogStash::Event.new({ :message => message_json_string, :other => "Other value" })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)
        .with { |request|
          message = single_gzipped_message(request.body)
          message['message'] == message_json_string &&
          message['attributes']['other'] == 'Other value' })
        .to have_been_made
    end

    it "other JSON fields are not parsed" do
      stub_request(:any, base_uri).to_return(status: 200)

      other_json = '{ "key": "value" }'
      event = LogStash::Event.new({ :message => "Test message", :other => other_json })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)
        .with { |request|
          message = single_gzipped_message(request.body)
          message['message'] == 'Test message' &&
          message['attributes']['other'] == other_json })
        .to have_been_made
    end

    it "handles messages without a 'message' field" do
      stub_request(:any, base_uri).to_return(status: 200)

      event = LogStash::Event.new({ :other => 'Other value' })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)
      .with { |request|
        message = single_gzipped_message(request.body)
        message['attributes']['other'] == 'Other value' })
      .to have_been_made
    end

    it "zero events should not cause an HTTP call" do
      stub_request(:any, base_uri).to_return(status: 200)

      @newrelic_output.multi_receive([])

      # Shut down the plugin so that it has the chance to send a request
      # (since we're verifying that nothing is sent)
      @newrelic_output.shutdown

      expect(a_request(:post, base_uri))
          .not_to have_been_made
    end

    it "multiple events" do
      stub_request(:any, base_uri).to_return(status: 200)

      event1 = LogStash::Event.new({ "message" => "Test message 1" })
      event2 = LogStash::Event.new({ "message" => "Test message 2" })
      @newrelic_output.multi_receive([event1, event2])

      wait_for(a_request(:post, base_uri)
        .with { |request|
          messages = multiple_gzipped_messages(request.body)[0]['logs']
          messages.length == 2 &&
          messages[0]['message'] == 'Test message 1' &&
          messages[1]['message'] == 'Test message 2' })
        .to have_been_made
    end
  end

  context "error handling" do
    it "continues through errors, future calls should still succeed" do
      stub_request(:any, base_uri)
        .to_raise(StandardError.new("from test"))
        .to_return(status: 200)

      event1 = LogStash::Event.new({ "message" => "Test message 1" })
      event2 = LogStash::Event.new({ "message" => "Test message 2" })
      @newrelic_output.multi_receive([event1])
      @newrelic_output.multi_receive([event2])

      wait_for(a_request(:post, base_uri)
        .with { |request| single_gzipped_message(request.body)['message'] == 'Test message 2' })
        .to have_been_made
    end
  end
end

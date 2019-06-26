# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/newrelic"
require "logstash/outputs/newrelic_version/version"
require "logstash/codecs/plain"
require "logstash/event"
require "webmock/rspec"
require "zlib"

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
      "retries" => retries,
      "retry_seconds" => retry_seconds,
      "max_delay" => max_delay,
    }
  }

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

  before(:each) do
    @newrelic_output = LogStash::Plugin.lookup("output", "newrelic").new(simple_config)
    @newrelic_output.register
  end

  after(:each) do
    @newrelic_output&.shutdown
  end

  context "validation of config" do
    it "requires api_key" do
      no_api_key_config = {
      }

      expect { LogStash::Plugin.lookup("output", "newrelic").new(no_api_key_config) }.to raise_error LogStash::ConfigurationError
    end
  end

  context "request headers" do
    it "all present" do
      stub_request(:any, base_uri).to_return(status: 200)

      event = LogStash::Event.new({ "message" => "Test message" })
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

      event = LogStash::Event.new({ :message => "Test message", :@timestamp => '123' })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)
      .with { |request|
        data = multiple_gzipped_messages(request.body)[0]
        data['common']['attributes']['plugin']['type'] == 'logstash' &&
        data['common']['attributes']['plugin']['version'] == LogStash::Outputs::NewRelicVersion::VERSION })
      .to have_been_made
    end

    # TODO: why is this field always removed?
    it "'@timestamp' field is removed" do
      stub_request(:any, base_uri).to_return(status: 200)

      event = LogStash::Event.new({ :message => "Test message", :@timestamp => '123' })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)
        .with { |request| single_gzipped_message(request.body)['@timestamp'] == nil })
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
          message['other'] == 'Other value' })
        .to have_been_made
    end

    it "JSON object 'message' field is parsed, removed, and its data merged as attributes" do
      stub_request(:any, base_uri).to_return(status: 200)

      message_json = '{ "in-json-1": "1", "in-json-2": "2", "sub-object": {"in-json-3": "3"} }'
      event = LogStash::Event.new({ :message => message_json, :other => "Other value" })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)
        .with { |request|
          message = single_gzipped_message(request.body)
          message['in-json-1'] == '1' &&
          message['in-json-2'] == '2' &&
          message['sub-object'] == {"in-json-3" => "3"} &&
          message['other'] == 'Other value' })
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
          message['other'] == 'Other value' })
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
          message['other'] == 'Other value' })
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
          message['other'] == other_json })
        .to have_been_made
    end

    it "handles messages without a 'message' field" do
      stub_request(:any, base_uri).to_return(status: 200)

      event = LogStash::Event.new({ :other => 'Other value' })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)
      .with { |request|
        message = single_gzipped_message(request.body)
        message['other'] == 'Other value' })
      .to have_been_made
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

  context "retry" do
    it "sleep periods double each time up to max time" do
      specific_config = simple_config.clone
      # Use non-trivial times -- they can be big, since this test doesn't do any sleeping, just
      # tests the sleep duration
      specific_config["max_delay"] = 60
      specific_config["retry_seconds"] = 5

      # Create a new plugin with this specific config that has longer retry sleep
      # configuration than we normally want
      @newrelic_output&.shutdown
      @newrelic_output = LogStash::Plugin.lookup("output", "newrelic").new(specific_config)
      @newrelic_output.register

      expect(@newrelic_output.sleep_duration(0)).to equal(5)
      expect(@newrelic_output.sleep_duration(1)).to equal(10)
      expect(@newrelic_output.sleep_duration(2)).to equal(20)
      expect(@newrelic_output.sleep_duration(3)).to equal(40)
      expect(@newrelic_output.sleep_duration(4)).to equal(60)
      expect(@newrelic_output.sleep_duration(5)).to equal(60) # Never gets bigger than this
    end

    it "first call fails, should retry" do
      stub_request(:any, base_uri)
        .to_return(status: 500)
        .to_return(status: 200)

      event = LogStash::Event.new({ "message" => "Test message" })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)).to have_been_made.times(2)
    end

    it "first two calls fail, should retry" do
      stub_request(:any, base_uri)
        .to_return(status: 500)
        .to_return(status: 500)
        .to_return(status: 200)

      event = LogStash::Event.new({ "message" => "Test message" })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)).to have_been_made.times(3)
    end

    it "all calls fails, should stop retrying at some point" do
      stub_request(:any, base_uri)
        .to_return(status: 500)

      event = LogStash::Event.new({ "message" => "Test message" })
      @newrelic_output.multi_receive([event])

      # This may not fail if the wait_for is called exactly when there have been 'retries' calls.
      # However, with zero sleep time (max_delay=0), on a laptop the POST was done 2000+ times by the
      # time this was executed
      wait_for(a_request(:post, base_uri)).to have_been_made.times(retries)
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

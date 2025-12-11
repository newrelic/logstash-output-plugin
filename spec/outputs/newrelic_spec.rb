# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/newrelic"
require "logstash/outputs/newrelic_version/version"
require "logstash/codecs/plain"
require "logstash/event"
require "thread"
require "manticore"
require "webmock/rspec"
require "zlib"
require "rspec/wait"

# Configure WebMock to work with Manticore
WebMock.disable_net_connect!(allow_localhost: true)

# Ensure WebMock can intercept Manticore requests
require 'webmock/http_lib_adapters/manticore_adapter' if defined?(::Manticore)

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

  context "check https connection scheme" do
    it "uses https by default" do
      stub_request(:any, base_uri).to_return(status: 200)

      event = LogStash::Event.new({:message => "Test message" })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)
        .with(headers: {
                "X-License-Key" => license_key,
                "X-Event-Source" => "logs",
                "Content-Encoding" => "gzip",
              })).to have_been_made

      # Check if the requests were made using HTTPS
      expect(WebMock).to have_requested(:post, base_uri).with { |req| req.uri.scheme == 'https' }
      expect(WebMock).to have_requested(:post, base_uri).with { |req| req.uri.port == 443 }
    end
  end

  context "check http connection scheme" do
    it "uses http when http config is set" do
      stub_request(:any, "http://localhost:5000/").to_return(status: 200)
      @newrelic_output = LogStash::Plugin.lookup("output", "newrelic").new({
        "base_uri" => "http://localhost:5000/",
        "license_key" => license_key
      })
      @newrelic_output.register
      event = LogStash::Event.new({:message => "Test message" })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, "http://localhost:5000/")
        .with(headers: {
                "X-License-Key" => license_key,
                "X-Event-Source" => "logs",
                "Content-Encoding" => "gzip",
              })).to have_been_made

      # Check if the requests were made using HTTP to this endpoint
      expect(WebMock).to have_requested(:post, "http://localhost:5000/").with { |req| req.uri.scheme == 'http' }
      expect(WebMock).to have_requested(:post, "http://localhost:5000/").with { |req| req.uri.port == 5000 }
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
    puts "DEBUG gunzip input: bytes class = #{bytes.class}"
    return bytes if bytes.nil? || bytes.empty?
    
    # For Manticore, the body might come as a Java byte array or InputStream
    # Convert to string if needed
    if bytes.respond_to?(:java_class)
      puts "DEBUG: bytes has java_class"
      # Handle Java types (byte array, InputStream, etc)
      bytes = String.from_java_bytes(bytes) if bytes.respond_to?(:to_a)
    end
    
    bytes = bytes.to_s unless bytes.is_a?(String)
    puts "DEBUG gunzip: after conversion, bytes class = #{bytes.class}, length = #{bytes.length}"
    
    # Ensure binary encoding
    bytes.force_encoding('BINARY')
    
    byte0 = bytes.getbyte(0)
    byte1 = bytes.getbyte(1)
    puts "DEBUG gunzip: byte0 = 0x#{byte0.to_s(16)}, byte1 = 0x#{byte1.to_s(16)}"
    
    # Check for gzip magic bytes (0x1f 0x8b)
    if bytes.length >= 2 && byte0 == 0x1f && byte1 == 0x8b
      puts "DEBUG gunzip: detected gzip magic bytes, decompressing..."
      sio = StringIO.new(bytes)
      gz = Zlib::GzipReader.new(sio)
      result = gz.read
      gz.close
      puts "DEBUG gunzip: decompression successful, result length = #{result.length}"
      result
    else
      puts "DEBUG gunzip: NOT gzipped (or magic bytes don't match), returning as-is"
      # Not gzipped, return as-is
      bytes
    end
  end

  def single_gzipped_message(body)
    puts "DEBUG single_gzipped_message: body class = #{body.class}"
    puts "DEBUG single_gzipped_message: body length = #{body.to_s.length}"
    puts "DEBUG single_gzipped_message: first 10 bytes = #{body.to_s[0..9].bytes.map{|b| '%02X' % b}.join(' ')}"
    
    decompressed = gunzip(body)
    
    puts "DEBUG after gunzip: decompressed class = #{decompressed.class}"
    puts "DEBUG after gunzip: decompressed length = #{decompressed.length}"
    puts "DEBUG after gunzip: first 50 chars = #{decompressed[0..49].inspect}"
    
    message = JSON.parse(decompressed)[0]['logs']
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
      captured_body = nil
      stub_request(:any, base_uri).to_return do |request|
        captured_body = request.body
        { status: 200 }
      end

      event = LogStash::Event.new({ :message => "Test message" })
      @newrelic_output.multi_receive([event])

      wait_for { captured_body }.not_to be_nil
      data = multiple_gzipped_messages(captured_body)[0]
      expect(data['common']['attributes']['plugin']['type']).to eq('logstash')
      expect(data['common']['attributes']['plugin']['version']).to eq(LogStash::Outputs::NewRelicVersion::VERSION)
    end

    it "all other fields passed through as is" do
      captured_body = nil
      stub_request(:any, base_uri).to_return do |request|
        captured_body = request.body
        puts "DEBUG: Captured body class: #{captured_body.class}"
        puts "DEBUG: Captured body length: #{captured_body.length rescue 'N/A'}"
        puts "DEBUG: First 20 bytes: #{captured_body.to_s[0..19].bytes.map{|b| "\\x%02X" % b}.join rescue 'N/A'}"
        { status: 200 }
      end

      event = LogStash::Event.new({ :message => "Test message", :other => "Other value" })
      @newrelic_output.multi_receive([event])

      wait_for { captured_body }.not_to be_nil
      message = single_gzipped_message(captured_body)
      expect(message['message']).to eq('Test message')
      expect(message['attributes']['other']).to eq('Other value')
    end

    it "JSON object 'message' field is not parsed" do
      captured_body = nil
      stub_request(:any, base_uri).to_return do |request|
        captured_body = request.body
        { status: 200 }
      end

      message_json = '{ "in-json-1": "1", "in-json-2": "2", "sub-object": {"in-json-3": "3"} }'
      event = LogStash::Event.new({ :message => message_json, :other => "Other value" })
      @newrelic_output.multi_receive([event])

      wait_for { captured_body }.not_to be_nil
      message = single_gzipped_message(captured_body)
      expect(message['message']).to eq(message_json)
      expect(message['attributes']['other']).to eq('Other value')
    end

    it "JSON array 'message' field is not parsed, left as is" do
      captured_body = nil
      stub_request(:any, base_uri).to_return do |request|
        captured_body = request.body
        { status: 200 }
      end

      message_json_array = '[{ "in-json-1": "1", "in-json-2": "2", "sub-object": {"in-json-3": "3"} }]'
      event = LogStash::Event.new({ :message => message_json_array, :other => "Other value" })
      @newrelic_output.multi_receive([event])

      wait_for { captured_body }.not_to be_nil
      message = single_gzipped_message(captured_body)
      expect(message['message']).to eq(message_json_array)
      expect(message['attributes']['other']).to eq('Other value')
    end

    it "JSON string 'message' field is not parsed, left as is" do
      captured_body = nil
      stub_request(:any, base_uri).to_return do |request|
        captured_body = request.body
        { status: 200 }
      end

      message_json_string = '"I can be parsed as JSON"'
      event = LogStash::Event.new({ :message => message_json_string, :other => "Other value" })
      @newrelic_output.multi_receive([event])

      wait_for { captured_body }.not_to be_nil
      message = single_gzipped_message(captured_body)
      expect(message['message']).to eq(message_json_string)
      expect(message['attributes']['other']).to eq('Other value')
    end

    it "other JSON fields are not parsed" do
      captured_body = nil
      stub_request(:any, base_uri).to_return do |request|
        captured_body = request.body
        { status: 200 }
      end

      other_json = '{ "key": "value" }'
      event = LogStash::Event.new({ :message => "Test message", :other => other_json })
      @newrelic_output.multi_receive([event])

      wait_for { captured_body }.not_to be_nil
      message = single_gzipped_message(captured_body)
      expect(message['message']).to eq('Test message')
      expect(message['attributes']['other']).to eq(other_json)
    end

    it "handles messages without a 'message' field" do
      captured_body = nil
      stub_request(:any, base_uri).to_return do |request|
        captured_body = request.body
        { status: 200 }
      end

      event = LogStash::Event.new({ :other => 'Other value' })
      @newrelic_output.multi_receive([event])

      wait_for { captured_body }.not_to be_nil
      message = single_gzipped_message(captured_body)
      expect(message['attributes']['other']).to eq('Other value')
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
      captured_body = nil
      stub_request(:any, base_uri).to_return do |request|
        captured_body = request.body
        { status: 200 }
      end

      event1 = LogStash::Event.new({ "message" => "Test message 1" })
      event2 = LogStash::Event.new({ "message" => "Test message 2" })
      @newrelic_output.multi_receive([event1, event2])

      wait_for { captured_body }.not_to be_nil
      messages = multiple_gzipped_messages(captured_body)[0]['logs']
      expect(messages.length).to eq(2)
      expect(messages[0]['message']).to eq('Test message 1')
      expect(messages[1]['message']).to eq('Test message 2')
    end
  end

  context "error handling and retry logic" do
    it "continues through errors, future calls should still succeed" do
      captured_body = nil
      stub_request(:any, base_uri)
        .to_raise(StandardError.new("from test"))
        .to_return do |request|
          captured_body = request.body
          { status: 200 }
        end

      event1 = LogStash::Event.new({ "message" => "Test message 1" })
      event2 = LogStash::Event.new({ "message" => "Test message 2" })
      @newrelic_output.multi_receive([event1])
      @newrelic_output.multi_receive([event2])

      wait_for { captured_body }.not_to be_nil
      message = single_gzipped_message(captured_body)
      expect(message['message']).to eq('Test message 2')
    end

    [
      { "returned_status_code" => 200, "expected_to_retry" => false },
      { "returned_status_code" => 202, "expected_to_retry" => false },
      { "returned_status_code" => 400, "expected_to_retry" => false },
      { "returned_status_code" => 404, "expected_to_retry" => false },
      { "returned_status_code" => 408, "expected_to_retry" => true },
      { "returned_status_code" => 429, "expected_to_retry" => true },
      { "returned_status_code" => 500, "expected_to_retry" => true },
      { "returned_status_code" => 502, "expected_to_retry" => true },
      { "returned_status_code" => 503, "expected_to_retry" => true },
      { "returned_status_code" => 504, "expected_to_retry" => true },
      { "returned_status_code" => 599, "expected_to_retry" => true }
    ].each do |test_case|
      returned_status_code = test_case["returned_status_code"]
      expected_to_retry = test_case["expected_to_retry"]

      it "should #{expected_to_retry ? "" : "not"} retry on status code #{returned_status_code}" do
        request_count = 0
        captured_body = nil
        stub_request(:any, base_uri)
          .to_return do |request|
            captured_body = request.body
            request_count += 1
            { status: request_count == 1 ? returned_status_code : 200 }
          end

        logstash_event = LogStash::Event.new({ "message" => "Test message" })
        @newrelic_output.multi_receive([logstash_event])

        expected_retries = expected_to_retry ? 2 : 1
        wait_for { request_count }.to eq(expected_retries)
        message = single_gzipped_message(captured_body)
        expect(message['message']).to eq('Test message')
      end
    end

    it "does not retry when max_retries is set to 0" do
      @newrelic_output = LogStash::Plugin.lookup("output", "newrelic").new(
        { "base_uri" => base_uri, "license_key" => api_key, "max_retries" => '0' }
      )
      @newrelic_output.register
      request_count = 0
      captured_body = nil
      stub_request(:any, base_uri).to_return do |request|
        captured_body = request.body
        request_count += 1
        { status: 500 }
      end

      event1 = LogStash::Event.new({ "message" => "Test message 1" })
      @newrelic_output.multi_receive([event1])
      # Due the async behavior we need to wait to be sure that the method was not called more than 1 time
      sleep(2)
      expect(request_count).to eq(1)
      message = single_gzipped_message(captured_body)
      expect(message['message']).to eq('Test message 1')
    end

    it "retries when receive a not expected exception" do
      request_count = 0
      captured_body = nil
      stub_request(:any, base_uri).to_return do |request|
        captured_body = request.body
        request_count += 1
        raise StandardError.new("from test") if request_count == 1
        { status: 200 }
      end

      event1 = LogStash::Event.new({ "message" => "Test message 1" })
      @newrelic_output.multi_receive([event1])
      wait_for { request_count }.to eq(2)
      message = single_gzipped_message(captured_body)
      expect(message['message']).to eq('Test message 1')
    end

    it "performs the configured amount of retries, no more, no less" do
      @newrelic_output = LogStash::Plugin.lookup("output", "newrelic").new(
        { "base_uri" => base_uri, "license_key" => api_key, "max_retries" => '3' }
      )
      @newrelic_output.register
      request_count = 0
      captured_body = nil
      stub_request(:any, base_uri).to_return do |request|
        captured_body = request.body
        request_count += 1
        { status: request_count <= 3 ? 500 : 200 }
      end

      event1 = LogStash::Event.new({ "message" => "Test message" })
      @newrelic_output.multi_receive([event1])

      wait_for { request_count }.to eq(3)
      message = single_gzipped_message(captured_body)
      expect(message['message']).to eq('Test message')
    end
  end

  context "JSON serialization" do
    it "serializes floating point numbers as floating point numbers" do
      captured_body = nil
      stub_request(:any, base_uri).to_return do |request|
        captured_body = request.body
        { status: 200 }
      end

      event = LogStash::Event.new({ "floatingpoint" => 0.12345 })
      @newrelic_output.multi_receive([event])

      wait_for { captured_body }.not_to be_nil
      message = single_gzipped_message(captured_body)
      expect(message['attributes']['floatingpoint']).to eq(0.12345)
    end

    it "serializes BigDecimals as floating point numbers" do
      captured_body = nil
      stub_request(:any, base_uri).to_return do |request|
        captured_body = request.body
        { status: 200 }
      end

      event = LogStash::Event.new({ "bigdecimal" => BigDecimal('0.12345') })
      @newrelic_output.multi_receive([event])

      wait_for { captured_body }.not_to be_nil
      message = single_gzipped_message(captured_body)
      expect(message['attributes']['bigdecimal']).to eq(0.12345)
    end

    it "serializes NaN as null" do
      captured_body = nil
      stub_request(:any, base_uri).to_return do |request|
        captured_body = request.body
        { status: 200 }
      end

      event = LogStash::Event.new({ "nan" => BigDecimal('NaN') })
      @newrelic_output.multi_receive([event])

      wait_for { captured_body }.not_to be_nil
      message = single_gzipped_message(captured_body)
      expect(message['attributes']['nan']).to be_nil
    end
  end

  context "payload splitting" do

    def stub_requests_and_capture_msg_ids(captured_msg_ids_accumulator)
      mutex = Mutex.new
      stub_request(:any, base_uri).to_return do |request|
        mutex.synchronize do
          captured_msg_ids_accumulator.concat(extract_msg_ids(request.body))
        end
        { status: 200 }
      end
    end

    # Tests using this method expect log messages to contain a field "msgId" in their logs
    def extract_msg_ids(body)
      JSON.parse(gunzip(body))[0]['logs'].map do |log|
        log['attributes']['msgId']
      end
    end

    def expect_msg_ids(captured_msg_ids, msgIdsCount)
      wait_for { captured_msg_ids.length }.to eq(msgIdsCount), "Expected a total of #{msgIdsCount} logs, but found #{captured_msg_ids.length}"
      sorted_captured_msg_ids = captured_msg_ids.sort
      for i in 0...msgIdsCount do
        expect(sorted_captured_msg_ids[i]).to eq(i), "msgId #{i} not found"
      end
    end

    it "splits logs into up to 1MB payloads" do
      captured_msg_ids = []
      stub_requests_and_capture_msg_ids(captured_msg_ids)

      # This file contains 17997 random log record messages that upon compressed ends up being about 2.68MB
      # Each log record is pretty small (no single log exceeds 1MB alone), so, we expect it to perform 4 requests to the API
      # with
      file_path = 'spec/outputs/input_17997_messages_resulting_in_2680KB_compressed_payload.json'

      logstash_events =  File.readlines(file_path).map do |line|
        LogStash::Event.new(JSON.parse(line))
      end

      @newrelic_output.multi_receive(logstash_events)

      # Verify number of requests matches exactly 4. Note that .times() unexpectedly behaves as .at_least_times(), so we
      # are forced to do this double verification to check the exact number of calls.
      wait_for(a_request(:post, base_uri)).to have_been_made.at_least_times(4)
      wait_for(a_request(:post, base_uri)).to have_been_made.at_most_times(4)

      # Verify all expected msgIds were received
      expect_msg_ids(captured_msg_ids, 17997)
    end

    it "does not split a log and does not perform any request if it exceeds 1MB once compressed" do
      stub_request(:any, base_uri).to_return(status: 200)

      # This file contains a SINGLE random log record that upon compressed ends up being about 1.8MB
      # This payload cannot be further split, so we expect no call being made to the Logs API
      file_path = 'spec/outputs/single_input_message_exceeeding_1MB_once_compressed.json'

      logstash_events = []
      File.foreach(file_path) do |line|
        logstash_events << LogStash::Event.new(JSON.parse(line))
      end

      @newrelic_output.multi_receive(logstash_events)

      wait_for(a_request(:post, base_uri)).not_to have_been_made
    end

    it "does a single request when the payload is below 1MB" do
      captured_msg_ids = []
      stub_requests_and_capture_msg_ids(captured_msg_ids)

      # This file contains 5000 random log record messages that upon compressed ends up being about 0.74MB
      # Given that this is below the 1MB allowed by the Logs API, a single request will be made
      file_path = 'spec/outputs/input_5000_messages_resulting_in_740KB_compressed_payload.json'

      logstash_events = []
      File.foreach(file_path) do |line|
        logstash_events << LogStash::Event.new(JSON.parse(line))
      end

      @newrelic_output.multi_receive(logstash_events)

      # Verify number of requests matches exactly 1. Note that .times() unexpectedly behaves as .at_least_times(), so we
      # are forced to do this double verification to check the exact number of calls.
      wait_for(a_request(:post, base_uri)).to have_been_made.at_least_times(1)
      wait_for(a_request(:post, base_uri)).to have_been_made.at_most_times(1)

      # Verify all expected msgIds were received
      expect_msg_ids(captured_msg_ids, 5000)
    end
  end
end

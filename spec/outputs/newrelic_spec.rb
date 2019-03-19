# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/newrelic"
require "logstash/codecs/plain"
require "logstash/event"
require "webmock/rspec"
require "zlib"

describe LogStash::Outputs::Newrelic do
  let (:api_key) { "someAccountKey" }
  let (:account_id) { "123" }
  let (:base_uri) { "https://testing-example-collector.com" }
  let (:retry_seconds) { 0 }
  # Don't sleep in tests, to keep tests fast. We have a test for the method that produces the sleep duration between retries.
  let (:max_delay) { 0 } 
  let (:retries) { 3 }
  let (:simple_config) {
    {
      "api_key" => api_key,
      "account_id" => account_id,
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
        "account_id" => account_id,
      }

      expect { LogStash::Plugin.lookup("output", "newrelic").new(no_api_key_config) }.to raise_error LogStash::ConfigurationError
    end

    it "requires account_id" do
      no_account_id_config = {
        "api_key" => api_key,
      }

      expect { LogStash::Plugin.lookup("output", "newrelic").new(no_account_id_config) }.to raise_error LogStash::ConfigurationError
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

  ###########################################################################
  # Doesn't  currently work -- need to use hash_including
  ###########################################################################
  # context "request body" do
  #   it "single event with 'message' field" do
  #     stub_request(:any, base_uri).to_return(status: 200)

  #     event = LogStash::Event.new({ :message => "Test message" })
  #     @newrelic_output.multi_receive([event])

  #     wait_for(a_request(:post, base_uri)
  #       .with { |req|
  #       # puts gunzip(req.body)
  #       # puts JSON.parse(gunzip(req.body))
  #       JSON.parse(gunzip(req.body)) == { :message => "Test message" }
  #     }).to have_been_made
  #   end
  # end

  context "request body" do
    it "makes POST call to collector" do
      stub_request(:any, base_uri).to_return(status: 200)

      event = LogStash::Event.new({ "message" => "Test message" })
      @newrelic_output.multi_receive([event])

      wait_for(a_request(:post, base_uri)).to have_been_made
    end
  end

  context "multiple events" do
    it "makes POST call to collector" do
      stub_request(:any, base_uri).to_return(status: 200)

      event1 = LogStash::Event.new({ "message" => "Test message 1" })
      event2 = LogStash::Event.new({ "message" => "Test message 2" })
      @newrelic_output.multi_receive([event1, event2])

      wait_for(a_request(:post, base_uri)).to have_been_made
    end
  end

  context "retry" do
    it "sleep periods double each time up to max time" do
      specific_config = simple_config.clone
      # Use non-trivial times -- they can be big, since this test doesn't do any sleeping, just 
      # tests the sleep duration
      specific_config["max_delay"] = 60
      specific_config["retry_seconds"] = 5

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
end

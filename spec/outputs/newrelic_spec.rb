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
  let (:simple_config) {
    {
      "api_key" => api_key,
      "account_id" => account_id,
      "base_uri" => base_uri,
    }
  }

  def gunzip(bytes)
    # Zlib::Inflate.inflate(bytes)
    gz = Zlib::GzipReader.new(StringIO.new(bytes))
    gz.read
  end

  before {
    @newrelic_output = LogStash::Plugin.lookup("output", "newrelic").new(simple_config)
    @newrelic_output.register
  }

  after {
    @newrelic_output&.shutdown
  }

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
end

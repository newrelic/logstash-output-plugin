# encoding: utf-8
require "logstash/outputs/base"
require "logstash/outputs/newrelic_version/version"
require 'net/http'
require 'uri'
require 'zlib'
require 'json'
require 'java'

class LogStash::Outputs::NewRelic < LogStash::Outputs::Base
  java_import java.util.concurrent.Executors;
  java_import java.util.concurrent.Semaphore;

  config_name "newrelic"

  config :api_key, :validate => :password, :required => false
  config :license_key, :validate => :password, :required => false
  config :concurrent_requests, :validate => :number, :default => 1
  config :base_uri, :validate => :string, :default => "https://log-api.newrelic.com/log/v1"

  public

  def register
    @end_point = URI.parse(@base_uri)
    if @api_key.nil? && @license_key.nil?
      raise LogStash::ConfigurationError, "Must provide a license key or api key", caller
    end
    auth = {
      @api_key.nil? ? 'X-License-Key': 'X-Insert-Key' => 
      @api_key.nil? ? @license_key.value : @api_key.value
    }
    @header = {
        'X-Event-Source' => 'logs',
        'Content-Encoding' => 'gzip'
    }.merge(auth).freeze
    @executor = java.util.concurrent.Executors.newFixedThreadPool(@concurrent_requests)
    @semaphor = java.util.concurrent.Semaphore.new(@concurrent_requests)
  end

  # Used by tests so that the test run can complete (background threads prevent JVM exit)
  def shutdown
    if @executor
      @executor.shutdown
      # We want this long enough to not have threading issues
      terminationWaitInSeconds = 10
      terminatedInTime = @executor.awaitTermination(terminationWaitInSeconds, java.util.concurrent.TimeUnit::SECONDS)
      if !terminatedInTime
        raise "Did not shut down within #{terminationWaitInSeconds} seconds"
      end
    end
  end

  def time_to_logstash_timestamp(time)
    begin
      LogStash::Timestamp.coerce(time)
    rescue
      nil
    end
  end


  def encode(event_hash)
    log_message_hash = {
        # non-intrinsic attributes get put into 'attributes'
        :attributes => event_hash
    }

    # intrinsic attributes go at the top level
    if event_hash['message']
      log_message_hash['message'] = event_hash['message']
      log_message_hash[:attributes].delete('message')
    end
    if event_hash['timestamp']
      log_message_hash['timestamp'] = event_hash['timestamp']
      log_message_hash[:attributes].delete('timestamp')
    end

    log_message_hash
  end

  def multi_receive(events)
    if events.size == 0
      return
    end

    payload = []
    events.each do |event|
      payload.push(encode(event.to_hash))
    end
    payload = {
        :common => {
            :attributes => {
                :plugin => {
                    :type => 'logstash',
                    :version => LogStash::Outputs::NewRelicVersion::VERSION,
                }
            }
        },
        :logs => payload
    }
    @semaphor.acquire()
    execute = @executor.java_method :submit, [java.lang.Runnable]
    execute.call do
      begin
        io = StringIO.new
        gzip = Zlib::GzipWriter.new(io)
        gzip << [payload].to_json
        gzip.close
        nr_send(io.string)
      ensure
        @semaphor.release()
      end
    end
  end

  def handle_response(response)
    if !(200 <= response.code.to_i && response.code.to_i < 300)
      @logger.error("Request returned " + response.code + " " + response.body)
    end
  end

  def nr_send(payload)
    http = Net::HTTP.new(@end_point.host, 443)
    request = Net::HTTP::Post.new(@end_point.request_uri)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    @header.each {|k, v| request[k] = v}
    request.body = payload
    handle_response(http.request(request))
  end
end # class LogStash::Outputs::NewRelic

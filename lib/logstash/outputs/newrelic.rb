# encoding: utf-8
require "logstash/outputs/base"
require "logstash/outputs/newrelic_version/version"
require 'net/http'
require 'uri'
require 'zlib'
require 'json'
require 'java'
require 'set'
require_relative './config/bigdecimal_patch'
require_relative './exception/error'

class LogStash::Outputs::NewRelic < LogStash::Outputs::Base
  java_import java.util.concurrent.Executors;
  java_import java.util.concurrent.Semaphore;

  NON_RETRYABLE_CODES = Set[401, 403]

  config_name "newrelic"

  config :api_key, :validate => :password, :required => false
  config :license_key, :validate => :password, :required => false
  config :concurrent_requests, :validate => :number, :default => 1
  config :base_uri, :validate => :string, :default => "https://log-api.newrelic.com/log/v1"
  config :max_retries, :validate => :number, :default => 3
  # Only used for E2E testing
  config :custom_ca_cert, :validate => :string, :required => false

  public

  def register
    @end_point = URI.parse(@base_uri)
    if @api_key.nil? && @license_key.nil?
      raise LogStash::ConfigurationError, "Must provide a license key or api key", caller
    end
    auth = {
      @api_key.nil? ? 'X-License-Key' : 'X-Insert-Key' =>
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
      raise Error::BadResponseCodeError.new(response.code.to_i, @base_uri)
    end
  end

  def nr_send(payload)
    retries = 0
    begin
      http = Net::HTTP.new(@end_point.host, 443)
      request = Net::HTTP::Post.new(@end_point.request_uri)
      request['Content-Type'] = 'application/json'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      if !@custom_ca_cert.nil?
        store = OpenSSL::X509::Store.new
        ca_cert = OpenSSL::X509::Certificate.new(File.read(@custom_ca_cert))
        store.add_cert(ca_cert)
        http.cert_store = store
      end
      @header.each { |k, v| request[k] = v }
      request.body = payload
      handle_response(http.request(request))
    rescue Error::BadResponseCodeError => e
      @logger.error(e.message)
      if (should_retry(retries) && is_retryable_code(e))
        retries += 1
        sleep(1)
        retry
      end
    rescue => e
      # Stuff that should never happen
      # For all other errors print out full issues
      if (should_retry(retries))
        retries += 1
        @logger.warn(
          "An unknown error occurred sending a bulk request to NewRelic. Retrying...",
          :retries => "attempt #{retries} of #{@max_retries}",
          :error_message => e.message,
          :error_class => e.class.name,
          :backtrace => e.backtrace
        )
        sleep(1)
        retry
      else
        @logger.error(
          "An unknown error occurred sending a bulk request to NewRelic. Maximum of attempts reached, dropping logs.",
          :error_message => e.message,
          :error_class => e.class.name,
          :backtrace => e.backtrace
        )
      end
    end
  end

  def should_retry(retries)
    retries < @max_retries
  end

  def is_retryable_code(response_error)
    error_code = response_error.response_code
    !NON_RETRYABLE_CODES.include?(error_code)
  end
end # class LogStash::Outputs::NewRelic

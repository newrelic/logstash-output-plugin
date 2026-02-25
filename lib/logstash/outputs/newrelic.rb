# encoding: utf-8
require "logstash/outputs/base"
require "logstash/outputs/newrelic_version/version"
require 'manticore'
require 'uri'
require 'zlib'
require 'json'
require 'java'
require 'set'
require 'stringio'
require_relative './config/bigdecimal_patch'
require_relative './exception/error'

class LogStash::Outputs::NewRelic < LogStash::Outputs::Base

  RETRIABLE_CODES = Set[408, 429, 500, 502, 503, 504, 599]

  MAX_PAYLOAD_SIZE_BYTES = 1_000_000

  config_name "newrelic"

  config :api_key, :validate => :password, :required => false
  config :license_key, :validate => :password, :required => false
  config :concurrent_requests, :validate => :number, :default => 1
  config :base_uri, :validate => :string, :default => "https://log-api.newrelic.com/log/v1"
  config :max_retries, :validate => :number, :default => 3
  config :connect_timeout_seconds, :validate => :number, :default => 30
  config :socket_timeout_seconds, :validate => :number, :default => 30
  # Only used for E2E testing
  config :custom_ca_cert, :validate => :string, :required => false

  public

  def register
    @end_point = URI.parse(@base_uri)
    if @api_key.nil? && @license_key.nil?
      raise LogStash::ConfigurationError, "Must provide a license key or api key", caller
    end
    @logger.debug("Registering logstash-output-newrelic", :version => LogStash::Outputs::NewRelicVersion::VERSION, :target => @base_uri)
    auth = {
      @api_key.nil? ? 'X-License-Key' : 'X-Insert-Key' =>
        @api_key.nil? ? @license_key.value : @api_key.value
    }
    @header = {
      'X-Event-Source' => 'logs',
      'Content-Encoding' => 'gzip',
      'Content-Type' => 'application/json'
    }.merge(auth).freeze

    client_options = {
      :pool_max => @concurrent_requests,
      :pool_max_per_route => @concurrent_requests,
      :connect_timeout => @connect_timeout_seconds,
      :socket_timeout => @socket_timeout_seconds
    }

    # Only configure SSL if using HTTPS
    if @end_point.scheme == 'https'
      client_options[:ssl] = {
        :verify => :default
      }
      
      if !@custom_ca_cert.nil?
        # Load the custom CA certificate and add it to the SSL options for the HTTP client
        client_options[:ssl][:ca_file] = @custom_ca_cert
      end
    end

    @client = Manticore::Client.new(client_options)

    # We use a semaphore to ensure that at most there are @concurrent_requests inflight Logstash requests being processed
    # by our plugin at the same time. Without this semaphore, given that @executor.submit() is an asynchronous method, it
    # would cause that an unbounded amount of inflight requests may be processed by our plugin. Logstash then believes
    # that our plugin has processed the request, and keeps reading more inflight requests in memory. This causes a memory
    # leak and results in an OutOfMemoryError.
    @executor = java.util.concurrent.Executors.newFixedThreadPool(@concurrent_requests)
    @semaphore = java.util.concurrent.Semaphore.new(@concurrent_requests)
    @shutdown_complete = false
  end

  # Shutdown hook called by Logstash 5.x and 6.x versions during pipeline shutdown
  def stop
    shutdown
  end

  # Shutdown hook called by Logstash 7.x+ versions during pipeline shutdown
  def close
    shutdown
  end

  # Additional shutdown hook for cleanup, called by some Logstash versions
  def teardown
    shutdown
  end

  # Used by tests so that the test run can complete (background threads prevent JVM exit)
  def shutdown
    return if @shutdown_complete

    if @executor
      @logger.debug("Draining outstanding New Relic requests")
      @executor.shutdown
      # We want this long enough to not have threading issues
      terminationWaitInSeconds = 10
      terminatedInTime = @executor.awaitTermination(terminationWaitInSeconds, java.util.concurrent.TimeUnit::SECONDS)
      if !terminatedInTime
        raise "Did not shut down within #{terminationWaitInSeconds} seconds"
      end
    end

    if defined?(@client) && @client
      @logger.debug("Closing New Relic HTTP client")
      @client.close
    end

    @shutdown_complete = true
  end

  def time_to_logstash_timestamp(time)
    begin
      LogStash::Timestamp.coerce(time)
    rescue
      nil
    end
  end

  def to_nr_logs(logstash_events)
    logstash_events.map do |logstash_event|
      event_hash = logstash_event.to_hash

      nr_log_message_hash = {
        # non-intrinsic attributes get put into 'attributes'
        :attributes => event_hash
      }

      # intrinsic attributes go at the top level
      if event_hash['message']
        nr_log_message_hash['message'] = event_hash['message']
        nr_log_message_hash[:attributes].delete('message')
      end
      if event_hash['timestamp']
        nr_log_message_hash['timestamp'] = event_hash['timestamp']
        nr_log_message_hash[:attributes].delete('timestamp')
      end

      nr_log_message_hash
    end
  end

  def multi_receive(logstash_events)
    if logstash_events.empty?
      return
    end

    nr_logs = to_nr_logs(logstash_events)

    @logger.debug("Submitting logs to New Relic", :event_count => nr_logs.length)

    submit_logs_to_be_sent(nr_logs)
  end

  def submit_logs_to_be_sent(nr_logs)
    @semaphore.acquire()
    execute = @executor.java_method :submit, [java.lang.Runnable]
    execute.call do
      begin
        package_and_send_recursively(nr_logs)
      ensure
        @semaphore.release()
      end
    end
  end

  def package_and_send_recursively(nr_logs)
    payload = {
      :common => {
        :attributes => {
          :plugin => {
            :type => 'logstash',
            :version => LogStash::Outputs::NewRelicVersion::VERSION,
          }
        }
      },
      :logs => nr_logs
    }

    payload_json = [payload].to_json
    compressed_payload = gzip_compress(payload_json, Zlib::DEFAULT_COMPRESSION)
    compressed_size = compressed_payload.bytesize
    log_record_count = nr_logs.length

    if compressed_size >= MAX_PAYLOAD_SIZE_BYTES && log_record_count == 1
      @logger.error("Can't compress record below required maximum packet size and it will be discarded.")
    elsif compressed_size >= MAX_PAYLOAD_SIZE_BYTES && log_record_count > 1
      @logger.debug("Compressed payload size exceeds maximum packet size, splitting payload", :compressed_size => compressed_size)
      split_index = log_record_count / 2
      @logger.debug("Splitting payload", :split_index => split_index, :first_half => split_index, :second_half => log_record_count - split_index)
      package_and_send_recursively(nr_logs[0...split_index])
      package_and_send_recursively(nr_logs[split_index..-1])
    else
      nr_send(compressed_payload)
    end
  end

  def handle_response(response)
    if !(200 <= response.code && response.code < 300)
      raise Error::BadResponseCodeError.new(response.code, @base_uri)
    end
  end

  # Compresses a given payload string using GZIP.
  #
  # @param payload [String] The string payload to be compressed.
  # @param compression_level [Integer] The GZIP compression level to use.
  # @return [String] The GZIP-compressed binary string.
  def gzip_compress(payload, compression_level)
    string_io = StringIO.new
    string_io.set_encoding("BINARY")
    Zlib::GzipWriter.wrap(string_io, compression_level) do |gz|
      gz.write(payload)
    end
    string_io.string
  end

  def nr_send(payload)
    retries = 0
    retry_duration = 1

    begin
      @logger.debug("Dispatching payload to New Relic", :endpoint => @base_uri, :payload_size => payload.bytesize)
      response = @client.post(@base_uri, :body => payload, :headers => @header)
      @logger.debug("Received response from New Relic", :code => response.code, :message => response.message)
      handle_response(response)
      if (retries > 0)
        @logger.warn("Successfully sent logs at retry #{retries}")
      else
        @logger.debug("Successfully sent logs to New Relic", :response_code => response.code)
      end
    rescue Error::BadResponseCodeError => e
      @logger.error(e.message)
      if (should_retry(retries) && is_retryable_code(e))
        retries += 1
        sleep(retry_duration)
        retry_duration *= 2
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
        sleep(retry_duration)
        retry_duration *= 2
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
    RETRIABLE_CODES.include?(error_code)
  end
end # class LogStash::Outputs::NewRelic

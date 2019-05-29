# encoding: utf-8
require "logstash/outputs/base"
require "logstash/outputs/newrelic_internal_version/version"
require 'net/http'
require 'uri'
require 'zlib'
require 'json'
require 'java'

class LogStash::Outputs::NewRelicInternal < LogStash::Outputs::Base
  java_import java.util.concurrent.Executors;
  java_import java.util.concurrent.Semaphore;

  config_name "newrelic_internal"

  config :api_key, :validate => :password, :required => true
  config :retry_seconds, :validate => :number, :default => 5
  config :max_delay, :validate => :number, :default => 30
  config :retries, :validate => :number, :default => 5
  config :concurrent_requests, :validate => :number, :default => 1
  config :base_uri, :validate => :string, :default => "https://insights-collector.newrelic.com/logs/v1"

  # TODO: do we need to define "concurrency"? https://www.elastic.co/guide/en/logstash/current/_how_to_write_a_logstash_output_plugin.html

  public

  def register
    @end_point = URI.parse(@base_uri)
    @header = {
        'X-Insert-Key' => @api_key.value,
        'X-Event-Source' => 'logs',
        'Content-Encoding' => 'gzip'
    }.freeze
    @executor = java.util.concurrent.Executors.newFixedThreadPool(@concurrent_requests)
    @semaphor = java.util.concurrent.Semaphore.new(@concurrent_requests)
  end

  # Used by tests so that the test run can complete (background threads prevent JVM exit)
  def shutdown
    @executor&.shutdown
  end

  def encode(event_hash)
    event_hash['plugin'] = {
      'type' => 'logstash',
      'version' => LogStash::Outputs::NewRelicInternalVersion::VERSION,
    }
    event_hash.delete('@timestamp')
    event_hash = maybe_parse_message_json(event_hash)
    event_hash
  end

  def maybe_parse_message_json(event_hash)
    if event_hash.has_key?('message')
      message = event_hash['message']
      event_hash = event_hash.merge(maybe_parse_json(message))
    end
    event_hash
  end

  def maybe_parse_json(message)
    begin
      parsed = JSON.parse(message)
      if Hash === parsed
        return parsed
      end
    rescue JSON::ParserError
    end
    return {}
  end

  def multi_receive(events)
    payload = []
    events.each do |event|
      payload.push(encode(event.to_hash))
    end
    @semaphor.acquire()
    execute = @executor.java_method :submit, [java.lang.Runnable]
    execute.call do
      begin
        io = StringIO.new
        gzip = Zlib::GzipWriter.new(io)
        gzip << payload.to_json
        gzip.close
        attempt_send(io.string, 0)
      ensure
        @semaphor.release()
      end
    end
  end

  def should_retry?(attempt)
    attempt < retries
  end

  def sleep_duration(attempt) 
    [max_delay, (2 ** attempt) * retry_seconds].min
  end

  def attempt_send(payload, attempt)
    sleep sleep_duration(attempt)
    attempt_send(payload, attempt + 1) unless was_successful?(nr_send(payload)) if should_retry?(attempt)
  end

  def was_successful?(response)
    200 <= response.code.to_i && response.code.to_i < 300
  end

  def nr_send(payload)
    http = Net::HTTP.new(@end_point.host, 443)
    request = Net::HTTP::Post.new(@end_point.request_uri)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    @header.each {|k, v| request[k] = v}
    request.body = payload
    http.request(request)
  end
end # class LogStash::Outputs::NewRelicInternal

# encoding: utf-8
require "logstash/outputs/base"
require 'net/http'
require 'uri'
require 'zlib'
require 'json'
require 'java'

class LogStash::Outputs::Newrelic < LogStash::Outputs::Base
  java_import java.util.concurrent.Executors;
  java_import java.util.concurrent.Semaphore;

  config_name "newrelic"

  config :api_key, :validate => :password, :required => true
  config :account_id, :validate => :string, :required => true
  config :retry_seconds, :validate => :number, :default => 5
  config :max_delay, :validate => :number, :default => 30
  config :event_type, :validate => :string, :default => 'log'
  config :retries, :validate => :number, :default => 5
  config :default_application, :validate => :string, :default => 'UNKNOWN'
  config :concurrent_requests, :validate => :number, :default => 1
  config :base_uri, :validate => :string, :default => "https://insights-collector.newrelic.com/v1/accounts/"

  # TODO: do we need to define "concurrency"? https://www.elastic.co/guide/en/logstash/current/_how_to_write_a_logstash_output_plugin.html

  public

  def register
    puts ">>> api_key=#{api_key.value}"
    puts ">>> account_id=#{account_id}"
    @end_point = URI.parse(@base_uri)
    @header = {
        'X-Insert-Key' => @api_key.value,
        'X-Event-Source' => 'logs',
        'Content-Encoding' => 'gzip'
    }.freeze
    @executor = java.util.concurrent.Executors.newFixedThreadPool(@concurrent_requests)
    @semaphor = java.util.concurrent.Semaphore.new(@concurrent_requests)
  end

  def shutdown
    @executor&.shutdown
  end

  def encode(event)
    event.set('messageId', java.util.UUID.randomUUID.toString)
    unless event.get('@realtime_timestamp').nil?
      event.set('timestamp', event.get('@realtime_timestamp').to_i);
      event.remove('@realtime_timestamp')
    end
    event.remove('@timestamp')
    event.set('eventType', event_type)
    puts ">>> event=#{event}"
    event.to_hash
  end

  def multi_receive(events)
    payload = []
    events.each do |event|
      payload.push(encode(event))
    end
    puts '>>> 1'
    @semaphor.acquire()
    execute = @executor.java_method :submit, [java.lang.Runnable]
    execute.call do
      puts '>>> 1.5'
      io = StringIO.new
      gzip = Zlib::GzipWriter.new(io)
      gzip << payload.to_json
      gzip.close
      puts '>>> 2'
      attempt_send(io.string, 0)
      puts '>>> 5'
      @semaphor.release() # TODO: do this in a finally block?
      puts '>>> 6'
    end
  end

  def should_retry?(attempt)
    attempt < retries
  end

  def sleep_duration(attempt) 
    [max_delay, (2 ** attempt) * retry_seconds].min
  end

  def attempt_send(payload, attempt)
    puts '>>> 3'
    puts ">>> Sleeping for #{sleep_duration(attempt)} seconds"
    sleep sleep_duration(attempt)
    puts '>>> 4'
    attempt_send(payload, attempt + 1) unless was_successful?(nr_send(payload)) if should_retry?(attempt)
  end

  def was_successful?(response)
    puts ">>> ..."
    puts ">>> #{response}"
    puts ">>> ..."
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
end # class LogStash::Outputs::Newrelic
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

  public

  def register
    @end_point = URI.parse "https://insights-collector.newrelic.com/v1/accounts/#{@account_id}/events".freeze
    @header = {
        'X-Insert-Key' => @api_key.value,
        'Content-Encoding' => 'gzip'
    }.freeze
    @executor = java.util.concurrent.Executors.newFixedThreadPool(@concurrent_requests)
    @semaphor = java.util.concurrent.Semaphore.new(@concurrent_requests)
  end

  def encode(event)
    unless event.get('@timestamp').nil?
      event.set('timestamp', event.get('@timestamp').to_i);
      event.remove('@timestamp')
    end
    event.set('eventType', event_type)
    event.to_hash
  end

  def multi_receive(events)
    puts Time.now
    payload = []
    events.each do |event|
      payload.push(encode(event))
    end
    payload.each_slice([(payload.size / 2).to_i, 1000].min) do |chunk|
      unless chunk.empty?
        @semaphor.acquire()
        @executor.submit do
          io = StringIO.new
          gzip = Zlib::GzipWriter.new(io)
          gzip << chunk.to_json
          gzip.close
          attempt_send(io.string, 0)
          @semaphor.release()
        end
      end
    end
  end

  def should_retry?(attempt)
    attempt < retries
  end

  def attempt_send(payload, attempt)
    sleep [max_delay, retry_seconds ** attempt].min
    attempt_send(payload, attempt + 1) unless was_successful?(nr_send(payload))
  end

  def was_successful?(response)
    puts response
    200 <= response.code.to_i && response.code.to_i < 300
  end

  def nr_send(payload)
    http = Net::HTTP.new(@end_point.host)
    request = Net::HTTP::Post.new(@end_point.request_uri)
    @header.each {|k, v| request[k] = v}
    request.body = payload
    http.request(request)
  end
end # class LogStash::Outputs::Newrelic

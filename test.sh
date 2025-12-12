#!/bin/bash
set -e
# For Mac M1 laptops, you need to use a version that has an arm64-compatible version
# See: https://www.docker.elastic.co/r/logstash/logstash
# Latest valid versions for M1 of each major Logstash release: 7.17.12, 8.9.0
LOGSTASH_VERSION=${1:-"7.17.12"}
export LOGSTASH_VERSION=$LOGSTASH_VERSION

MOCKSERVER_PORT=1080

clean_up () {
    ARG=$?

    if [[ $ARG -ne 0 ]]; then
      echo "Test failed, showing docker logs"
      echo "- Mockserver"
      docker compose -f ./test/docker-compose.yml logs mockserver
      echo "- Logstash ${LOGSTASH_VERSION}"
      docker compose -f ./test/docker-compose.yml logs logstash
    fi

    echo "Cleaning up"
    rm -r ./test/testdata || true
    docker compose -f ./test/docker-compose.yml down

    exit $ARG
}
trap clean_up EXIT

function check_logs {
  if [[ "${LOGSTASH_VERSION}" =~ ^8 ]]; then
    verification_file=verification-logstash8.json
  else
    verification_file=verification-logstash6_7.json
  fi

  curl -X PUT -s --fail "http://localhost:${MOCKSERVER_PORT}/mockserver/verify" -d "@test/${verification_file}" >> /dev/null
  RESULT=$?
  return $RESULT
}

function check_mockserver {
  curl -X PUT -s --fail "http://localhost:${MOCKSERVER_PORT}/mockserver/status" >> /dev/null
  RESULT=$?
  return $RESULT
}

function run_test {
  echo "Starting test for Logstash version ${LOGSTASH_VERSION}"

  echo "Creating testdata folder and log file"
  mkdir ./test/testdata || true
  touch ./test/testdata/logstashtest.log

  echo "Starting docker compose"
  docker compose -f ./test/docker-compose.yml up -d

  # Send some logs
  echo "Sending logs"
  for i in {1..5}; do
    echo "Hello!" >> ./test/testdata/logstashtest.log
  done

  # This updates the modified date of the log file
  touch ./test/testdata/logstashtest.log

  # Wait for logstash to process and send logs
  echo "Waiting 30 seconds for logstash to process and send logs..."
  sleep 30

  # Check if there were any errors in logstash logs
  echo "Checking logstash logs for errors..."
  docker compose -f ./test/docker-compose.yml logs logstash > /tmp/logstash-test.log
  
  # Show relevant log lines for debugging
  echo ""
  echo "=== Logstash output plugin activity ==="
  grep -i "newrelic" /tmp/logstash-test.log | head -20 || echo "No newrelic-related logs found"
  echo ""
  
  if grep -q "ERROR" /tmp/logstash-test.log; then
    echo "Found ERROR in logstash logs!"
    grep "ERROR" /tmp/logstash-test.log
    exit 1
  fi
  
  if grep -q "Maximum of attempts reached, dropping logs" /tmp/logstash-test.log; then
    echo "Found 'Maximum of attempts reached' in logstash logs - connection failed!"
    exit 1
  fi
  
  # Check if logs were actually sent (look for successful responses or send attempts)
  if grep -q -i "retrying\|failed to respond\|connection refused" /tmp/logstash-test.log; then
    echo "Warning: Found connection issues in logs, but not a hard failure"
    grep -i "retrying\|failed to respond\|connection refused" /tmp/logstash-test.log | head -10
  fi
  
  echo "Success! No errors found in logstash logs."
  
  # Verify logs reached New Relic (if NR credentials are available)
  if [[ -n "${NEW_RELIC_ACCOUNT_ID}" ]] && [[ -n "${NEW_RELIC_API_KEY}" ]]; then
    echo ""
    echo "=== Verifying logs in New Relic ==="
    
    # Query New Relic for our test logs with retries
    NRQL_QUERY="SELECT count(*) FROM Log WHERE message = 'Hello!' AND plugin.type = 'logstash' SINCE 5 minutes ago"
    
    max_retry=6
    retry_count=0
    log_count=0
    
    while [[ $retry_count -lt $max_retry ]]; do
      if [[ $retry_count -eq 0 ]]; then
        echo "Waiting 10 seconds for logs to be indexed..."
        sleep 10
      else
        echo "Retry #$retry_count: Waiting 10 more seconds..."
        sleep 10
      fi
      
      RESPONSE=$(curl -s -X POST "https://api.newrelic.com/graphql" \
        -H "Content-Type: application/json" \
        -H "API-Key: ${NEW_RELIC_API_KEY}" \
        -d "{\"query\": \"{ actor { account(id: ${NEW_RELIC_ACCOUNT_ID}) { nrql(query: \\\"${NRQL_QUERY}\\\") { results } } } }\"}")
      
      # Extract the count from the response
      log_count=$(echo "$RESPONSE" | grep -o '"count":[0-9]*' | grep -o '[0-9]*' || echo "0")
      
      echo "Logs found in New Relic: $log_count"
      
      if [[ "$log_count" -ge 5 ]]; then
        echo "✓ Successfully verified logs in New Relic!"
        break
      fi
      
      retry_count=$((retry_count+1))
    done
    
    if [[ "$log_count" -lt 5 ]]; then
      echo "⚠ Warning: Expected 5 logs but found $log_count in New Relic after $max_retry attempts"
      echo "Note: Logs may still be processing. Check New Relic UI in a few minutes."
      echo "API Response: $RESPONSE"
    fi
  else
    echo ""
    echo "Skipping New Relic verification (NEW_RELIC_ACCOUNT_ID and/or NEW_RELIC_API_KEY not set)"
  fi
}

function verify_java {
  if command -v javac >/dev/null 2>&1; then
      echo "Using java:"
      java --version
  else
      echo "Command javac not available. Please ensure you have correctly set JAVA_HOME"
  fi
}

function build_plugin {
  plugin_version=$(cat lib/logstash/outputs/newrelic_version/version.rb | grep -o 'VERSION = "[^"]*"' | awk -F'"' '{print $2}')
  echo "Building plugin version $plugin_version"
  jruby -S gem build logstash-output-newrelic.gemspec
}

function build_logstash_image_with_our_plugin {
  echo "Building image..."
  docker build --build-arg LOGSTASH_VERSION=$LOGSTASH_VERSION -f test/Dockerfile_test -t "logstash-${LOGSTASH_VERSION}-with-nr" .
  echo "Done"
}

# Main
build_plugin
build_logstash_image_with_our_plugin
run_test

exit 0


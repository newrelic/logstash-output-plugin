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
  
  if grep -q "ERROR" /tmp/logstash-test.log; then
    echo "Found ERROR in logstash logs!"
    grep "ERROR" /tmp/logstash-test.log
    exit 1
  fi
  
  if grep -q "Maximum of attempts reached, dropping logs" /tmp/logstash-test.log; then
    echo "Found 'Maximum of attempts reached' in logstash logs - connection failed!"
    exit 1
  fi
  
  echo "Success! No errors found in logstash logs."
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


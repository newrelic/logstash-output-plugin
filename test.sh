#!/bin/bash
set -e
# For Mac M1 laptops, you need to use a version that has an arm64-compatible version
# See: https://www.docker.elastic.co/r/logstash/logstash
# Latest valid versions for M1 of each major Logstash release: 7.11.0, 8.9.0
LOGSTASH_VERSION=${1:-"7.11.0"}
export LOGSTASH_VERSION=$LOGSTASH_VERSION

MOCKSERVER_PORT=443

clean_up () {
    ARG=$?

    if [[ $ARG -ne 0 ]]; then
      echo "Test failed, showing docker logs"
      echo "- Mockserver"
      docker-compose -f ./test/docker-compose.yml logs mockserver
      echo "- Logstash ${LOGSTASH_VERSION}"
      docker-compose -f ./test/docker-compose.yml logs logstash
    fi

    echo "Cleaning up"
    rm -r ./test/testdata || true
    docker-compose -f ./test/docker-compose.yml down

    exit $ARG
}
trap clean_up EXIT

function check_logs {
  if [[ "${LOGSTASH_VERSION}" =~ ^8 ]]; then
    verification_file=@test/verification-logstash8.json
  else
    verification_file=@test/verification-logstash5_6_7.json
  fi
  curl -X PUT -s --fail "http://localhost:${MOCKSERVER_PORT}/mockserver/verify" -d "${verification_file}" >> /dev/null
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
  docker-compose -f ./test/docker-compose.yml up -d

  # Waiting mockserver to be ready
  max_retry=20
  counter=0
  until check_mockserver
  do
    echo "Waiting mockserver to be ready. Trying again in 3s. Try #$counter"
    sleep 3
    [[ $counter -eq $max_retry ]] && echo "Mockserver failed to start!" && exit 1
    counter=$((counter+1))
  done

  # Send some logs
  echo "Sending logs and waiting for them to arrive"
  for i in {1..5}; do
    echo "Hello!" >> ./test/testdata/logstashtest.log
  done

  # This updates the modified date of the log file, it should
  # be updated with the echo but looks like it doesn't. A reason
  # could be that we're putting this file as a volume and writing
  # small changes so fast, if we add more echoes it works as well.
  touch ./test/testdata/logstashtest.log

  max_retry=20
  counter=0
  until check_logs
  do
    echo "Logs not found trying again in 3s. Try #$counter"
    sleep 3
    [[ $counter -eq $max_retry ]] && echo "Logs do not reach the server!" && exit 1
    counter=$((counter+1))
  done
  echo "Success!"
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


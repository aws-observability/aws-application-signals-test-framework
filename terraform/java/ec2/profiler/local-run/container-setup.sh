#!/bin/bash
# Runs inside the local test container started by run-local.sh. Mirrors the main_service_setup and
# traffic_generator_setup provisioners in ../main.tf: the same OTel Collector, the same three
# profiler variants with the same environment, the same deploy-time context file and the same
# traffic loop. Differences from EC2, all because a container is not an EC2 instance:
#   - The apps get fake, non-working AWS credentials, so /aws-sdk-call makes a real S3 round trip
#     (rejected with InvalidAccessKeyId) like it does with the instance role, instead of failing
#     instantly in the credential lookup.
#   - There is no instance metadata, so host.id is set to "local" through OTEL_RESOURCE_ATTRIBUTES
#     and host.name is the container hostname.
# Inputs (environment): SERVICE_NAME, OTEL_COLLECTOR_VERSION, AWS_REGION and the collector's AWS
# credentials. /work holds adot.jar, main-service.jar and otel-collector-config.yaml.
set -o errexit
cd /work

dnf install -y -q tar gzip procps-ng > /dev/null

collector_arch=$([ "$(uname -m)" = "x86_64" ] && echo amd64 || echo arm64)
curl -sSL -o otelcol-contrib.tar.gz \
  "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_COLLECTOR_VERSION}/otelcol-contrib_${OTEL_COLLECTOR_VERSION}_linux_${collector_arch}.tar.gz"
tar -xzf otelcol-contrib.tar.gz otelcol-contrib
nohup ./otelcol-contrib --config ./otel-collector-config.yaml --feature-gates=service.profilesSupport &> collector.out &
sleep 10
if ! pgrep -f otelcol-contrib > /dev/null; then
  echo "OTel Collector failed to start:"
  cat collector.out
  exit 1
fi

# The apps never see the real credentials (only the collector signs); they get fake ones instead.
APP_ENV=(env -u AWS_SESSION_TOKEN
  AWS_ACCESS_KEY_ID=AKIAFAKEFAKEFAKEFAKE
  AWS_SECRET_ACCESS_KEY=fakefakefakefakefakefakefakefakefakefake
  JAVA_TOOL_OPTIONS=' -javaagent:/work/adot.jar'
  OTEL_TRACES_EXPORTER=none
  OTEL_METRICS_EXPORTER=none
  OTEL_LOGS_EXPORTER=none
  OTEL_AWS_PROFILER_ENABLED=true)
resource() { echo "service.name=$1,deployment.environment.name=ec2:profiler,host.id=local"; }

# main :8080  wall, OTLP/HTTP, aggregation=agent default (full), memory on, sampled traces
"${APP_ENV[@]}" \
  OTEL_TRACES_SAMPLER=always_on \
  OTEL_AWS_PROFILER_MODE=wall \
  OTEL_AWS_PROFILER_MEMORY_ENABLED=true \
  OTEL_AWS_PROFILER_ENDPOINT=http://127.0.0.1:4318/v1development/profiles \
  OTEL_RESOURCE_ATTRIBUTES="$(resource "$SERVICE_NAME")" \
  nohup java -XX:+UseG1GC -Xmx512m -jar main-service.jar --server.port=8080 &> nohup.out &
echo $! > main.pid

# cpu :8081  cpu, OTLP/gRPC, aggregation=full, memory off, sampled traces
"${APP_ENV[@]}" \
  OTEL_TRACES_SAMPLER=always_on \
  OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
  OTEL_AWS_PROFILER_MODE=cpu \
  OTEL_AWS_PROFILER_AGGREGATION_MODE=full \
  OTEL_AWS_PROFILER_ENDPOINT=http://127.0.0.1:4317 \
  OTEL_RESOURCE_ATTRIBUTES="$(resource "$SERVICE_NAME-cpu")" \
  nohup java -XX:+UseG1GC -Xmx512m -jar main-service.jar --server.port=8081 &> nohup-cpu.out &
echo $! > cpu.pid

# unsampled :8082  wall, OTLP/HTTP, aggregation=sum, memory off, every trace dropped
"${APP_ENV[@]}" \
  OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true \
  OTEL_AWS_SERVICE_EVENTS_ENABLED=false \
  OTEL_TRACES_SAMPLER=traceidratio \
  OTEL_TRACES_SAMPLER_ARG=0.0 \
  OTEL_AWS_PROFILER_MODE=wall \
  OTEL_AWS_PROFILER_AGGREGATION_MODE=sum \
  OTEL_AWS_PROFILER_ENDPOINT=http://127.0.0.1:4318/v1development/profiles \
  OTEL_RESOURCE_ATTRIBUTES="$(resource "$SERVICE_NAME-unsampled")" \
  nohup java -XX:+UseG1GC -Xmx512m -jar main-service.jar --server.port=8082 &> nohup-unsampled.out &
echo $! > unsampled.pid

# none :8083  wall, OTLP/HTTP, aggregation=none, memory off, sampled traces
"${APP_ENV[@]}" \
  OTEL_TRACES_SAMPLER=always_on \
  OTEL_AWS_PROFILER_MODE=wall \
  OTEL_AWS_PROFILER_AGGREGATION_MODE=none \
  OTEL_AWS_PROFILER_ENDPOINT=http://127.0.0.1:4318/v1development/profiles \
  OTEL_RESOURCE_ATTRIBUTES="$(resource "$SERVICE_NAME-none")" \
  nohup java -XX:+UseG1GC -Xmx512m -jar main-service.jar --server.port=8083 &> nohup-none.out &
echo $! > none.pid

sleep 30
wait_for_app() {
  attempt_counter=0
  until curl --output /dev/null --silent --head --fail --max-time 5 "http://localhost:$1"; do
    if [ $attempt_counter -eq 30 ]; then
      echo "Failed to connect to the app on port $1:"
      tail -n 50 "$2"
      exit 1
    fi
    attempt_counter=$((attempt_counter + 1))
    sleep 10
  done
  if ! grep -q "async-profiler loaded successfully" "$2"; then
    echo "ADOT profiler did not start for the app on port $1:"
    tail -n 50 "$2"
    exit 1
  fi
  echo "App on port $1 is up with the profiler running"
}
wait_for_app 8080 nohup.out
wait_for_app 8081 nohup-cpu.out
wait_for_app 8082 nohup-unsampled.out
wait_for_app 8083 nohup-none.out

DISTRO_VERSION=$(grep -m1 -o 'opentelemetry-javaagent - version: [^ ]*' nohup.out | awk '{print $NF}')
printf '{"mainPid":"%s","cpuPid":"%s","unsampledPid":"%s","hostId":"local","hostName":"%s","distroVersion":"%s"}\n' \
  "$(cat main.pid)" "$(cat cpu.pid)" "$(cat unsampled.pid)" "$(cat /proc/sys/kernel/hostname)" "$DISTRO_VERSION" \
  > profiler-context.json

# Traffic: the same loop as the EC2 traffic generator. Keep going if a request fails.
set +o errexit
echo "TRAFFIC_STARTED"
while true; do
  for port in 8080 8081 8082 8083; do
    curl -s -o /dev/null "http://localhost:$port/"
    curl -s -o /dev/null "http://localhost:$port/outgoing-http-call"
    curl -s -o /dev/null "http://localhost:$port/aws-sdk-call"
  done
  sleep 1
done

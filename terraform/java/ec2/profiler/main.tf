# ------------------------------------------------------------------------
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License is located at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# or in the "license" file accompanying this file. This file is distributed
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied. See the License for the specific language governing
# permissions and limitations under the License.
# -------------------------------------------------------------------------

# Java EC2 profiler e2e: the springboot sample app runs under the ADOT Java agent with the
# continuous profiler enabled. The agent exports OTLP profiles to a local OTel Collector, which
# SigV4-signs and forwards them to CloudWatch Profiles; the validator then reads them back through
# the CloudWatch Profiles query API.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Define the provider for AWS
provider "aws" {}

resource "aws_default_vpc" "default" {}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "aws_ssh_key" {
  key_name   = "instance_key-${var.test_id}"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

locals {
  ssh_key_name        = aws_key_pair.aws_ssh_key.key_name
  private_key_content = tls_private_key.ssh_key.private_key_pem

  # The validator scopes its CloudWatch Profiles queries by this service.name.
  service_name   = "java-sample-application-${var.test_id}"
  collector_arch = var.cpu_architecture == "x86_64" ? "amd64" : "arm64"
}

data "aws_ami" "ami" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["al2023-ami-minimal-*-${var.cpu_architecture}"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
  filter {
    name   = "architecture"
    values = [var.cpu_architecture]
  }
  filter {
    name   = "image-type"
    values = ["machine"]
  }
  filter {
    name   = "root-device-name"
    values = ["/dev/xvda"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "main_service_instance" {
  # Amazon Linux 2023 is glibc-based, which async-profiler needs to unwind native wall stacks.
  ami = data.aws_ami.ami.id
  # .large (8 GiB): four profiled JVMs (main, cpu, unsampled, none variants; ~0.5 GB RSS each) and the
  # collector share the instance.
  instance_type                        = var.cpu_architecture == "x86_64" ? "t3.large" : "t4g.large"
  key_name                             = local.ssh_key_name
  iam_instance_profile                 = "APP_SIGNALS_EC2_TEST_ROLE"
  vpc_security_group_ids               = [aws_default_vpc.default.default_security_group_id]
  associate_public_ip_address          = true
  instance_initiated_shutdown_behavior = "terminate"

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size = 8
  }

  tags = {
    Name = "main-service-${var.test_id}"
  }
}

# Upload a locally supplied agent jar (only when adot_jar_local_path is set).
resource "null_resource" "upload_adot_jar" {
  count = var.adot_jar_local_path != "" ? 1 : 0

  connection {
    type        = "ssh"
    user        = var.user
    private_key = local.private_key_content
    host        = aws_instance.main_service_instance.public_ip
  }

  provisioner "file" {
    source      = var.adot_jar_local_path
    destination = "/home/${var.user}/adot.jar"
  }

  depends_on = [aws_instance.main_service_instance]
}

resource "null_resource" "main_service_setup" {
  connection {
    type        = "ssh"
    user        = var.user
    private_key = local.private_key_content
    host        = aws_instance.main_service_instance.public_ip
  }

  provisioner "file" {
    content = templatefile("./otel-collector-config.yaml", {
      region            = var.aws_region
      profiles_role_arn = var.profiles_role_arn
    })
    destination = "/home/${var.user}/otel-collector-config.yaml"
  }

  # Run by the workflow after the first checks: what each agent exported, live thread counts and
  # the collector's delivery counters, for the data integrity, thread count and delivery checks.
  provisioner "file" {
    source      = "./profiler-accounting.sh"
    destination = "/home/${var.user}/profiler-accounting.sh"
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
      # Make the Terraform fail if any step throws an error
      set -o errexit

      # Install wget
      sudo yum install wget tar -y

      # Install Java
      if [[ "${var.language_version}" == "8" ]]; then
        sudo yum install java-1.8.0-amazon-corretto -y
      else
        sudo yum install java-${var.language_version}-amazon-corretto -y
      fi

      # enable ec2 instance connect for debug
      sudo yum install ec2-instance-connect -y

      # Get and run the OTel Collector. It receives the profiler's OTLP profiles on 127.0.0.1:4318 and
      # forwards them SigV4-signed (instance role credentials) to CloudWatch Profiles.
      wget -q -O otelcol-contrib.tar.gz https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${var.otel_collector_version}/otelcol-contrib_${var.otel_collector_version}_linux_${local.collector_arch}.tar.gz
      tar -xzf otelcol-contrib.tar.gz otelcol-contrib
      nohup ./otelcol-contrib --config ./otel-collector-config.yaml --feature-gates=service.profilesSupport &> collector.out &
      sleep 10
      if ! pgrep -f otelcol-contrib > /dev/null; then
        echo "OTel Collector failed to start:"
        cat collector.out
        exit 1
      fi

      # Get ADOT Java agent (a build that includes the profiler), unless one was uploaded
      ${var.adot_jar_local_path != "" ? "echo 'Using uploaded ADOT agent jar'" : var.get_adot_jar_command}

      # Get and run the sample application with configuration
      aws s3 cp ${var.sample_app_jar} ./main-service.jar

      # Four copies of the sample app, each a profiler config variant with its own port, service.name
      # and log, so one instance covers every profiler setting value at least once:
      #   main      :8080  wall, OTLP/HTTP, aggregation=agent default (full), memory on, sampled traces
      #   cpu       :8081  cpu,  OTLP/gRPC, aggregation=full, memory off, sampled traces
      #   unsampled :8082  wall, OTLP/HTTP, aggregation=sum,  memory off, every trace dropped
      #   none      :8083  wall, OTLP/HTTP, aggregation=none, memory off, sampled traces
      # Traces/metrics/logs are not exported (only the profiles pipeline is under test), but spans are
      # still created, so samples on request threads carry the request's operation.

      JAVA_TOOL_OPTIONS=' -javaagent:/home/${var.user}/adot.jar' \
      OTEL_TRACES_EXPORTER=none \
      OTEL_METRICS_EXPORTER=none \
      OTEL_LOGS_EXPORTER=none \
      OTEL_TRACES_SAMPLER=always_on \
      OTEL_AWS_PROFILER_ENABLED=true \
      OTEL_AWS_PROFILER_MODE='${var.profiler_mode}' \
      OTEL_AWS_PROFILER_MEMORY_ENABLED=true \
      ${var.profiler_aggregation_mode != "" ? "OTEL_AWS_PROFILER_AGGREGATION_MODE=${var.profiler_aggregation_mode}" : ""} \
      OTEL_AWS_PROFILER_ENDPOINT=http://127.0.0.1:4318/v1development/profiles \
      OTEL_RESOURCE_ATTRIBUTES="service.name=${local.service_name},deployment.environment.name=ec2:profiler" \
      AWS_REGION='${var.aws_region}' \
      nohup java -XX:+UseG1GC -Xmx512m -jar main-service.jar --server.port=8080 &> nohup.out &
      echo $! > main.pid

      # cpu mode over OTLP/gRPC (shared OTEL_EXPORTER_OTLP_PROTOCOL; endpoint is host:port, no path)
      # with full aggregation. cpu samples carry no thread.state.
      JAVA_TOOL_OPTIONS=' -javaagent:/home/${var.user}/adot.jar' \
      OTEL_TRACES_EXPORTER=none \
      OTEL_METRICS_EXPORTER=none \
      OTEL_LOGS_EXPORTER=none \
      OTEL_TRACES_SAMPLER=always_on \
      OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
      OTEL_AWS_PROFILER_ENABLED=true \
      OTEL_AWS_PROFILER_MODE=cpu \
      OTEL_AWS_PROFILER_AGGREGATION_MODE=full \
      OTEL_AWS_PROFILER_ENDPOINT=http://127.0.0.1:4317 \
      OTEL_RESOURCE_ATTRIBUTES="service.name=${local.service_name}-cpu,deployment.environment.name=ec2:profiler" \
      AWS_REGION='${var.aws_region}' \
      nohup java -XX:+UseG1GC -Xmx512m -jar main-service.jar --server.port=8081 &> nohup-cpu.out &
      echo $! > cpu.pid

      # Unsampled traces: App Signals keeps request spans recording (AlwaysRecordSampler) while the
      # ratio sampler drops every trace, so samples still get the operation but no trace Link.
      JAVA_TOOL_OPTIONS=' -javaagent:/home/${var.user}/adot.jar' \
      OTEL_TRACES_EXPORTER=none \
      OTEL_METRICS_EXPORTER=none \
      OTEL_LOGS_EXPORTER=none \
      OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true \
      OTEL_AWS_SERVICE_EVENTS_ENABLED=false \
      OTEL_TRACES_SAMPLER=traceidratio \
      OTEL_TRACES_SAMPLER_ARG=0.0 \
      OTEL_AWS_PROFILER_ENABLED=true \
      OTEL_AWS_PROFILER_MODE=wall \
      OTEL_AWS_PROFILER_AGGREGATION_MODE=sum \
      OTEL_AWS_PROFILER_ENDPOINT=http://127.0.0.1:4318/v1development/profiles \
      OTEL_RESOURCE_ATTRIBUTES="service.name=${local.service_name}-unsampled,deployment.environment.name=ec2:profiler" \
      AWS_REGION='${var.aws_region}' \
      nohup java -XX:+UseG1GC -Xmx512m -jar main-service.jar --server.port=8082 &> nohup-unsampled.out &
      echo $! > unsampled.pid

      # aggregation=none (kept for backwards compatibility): one OTLP sample per profiler sample, with
      # its timestamp. This is the mode most likely to exceed a backend's per-profile sample limit.
      JAVA_TOOL_OPTIONS=' -javaagent:/home/${var.user}/adot.jar' \
      OTEL_TRACES_EXPORTER=none \
      OTEL_METRICS_EXPORTER=none \
      OTEL_LOGS_EXPORTER=none \
      OTEL_TRACES_SAMPLER=always_on \
      OTEL_AWS_PROFILER_ENABLED=true \
      OTEL_AWS_PROFILER_MODE=wall \
      OTEL_AWS_PROFILER_AGGREGATION_MODE=none \
      OTEL_AWS_PROFILER_ENDPOINT=http://127.0.0.1:4318/v1development/profiles \
      OTEL_RESOURCE_ATTRIBUTES="service.name=${local.service_name}-none,deployment.environment.name=ec2:profiler" \
      AWS_REGION='${var.aws_region}' \
      nohup java -XX:+UseG1GC -Xmx512m -jar main-service.jar --server.port=8083 &> nohup-none.out &
      echo $! > none.pid

      # The applications need time to come up and reach a steady state
      sleep 30

      # Wait for an app to answer on its port, then check its profiler started. The profiler is
      # silently disabled when async-profiler's native library cannot load (e.g. a noexec data dir),
      # so fail fast here instead of timing out in every validator.
      wait_for_app() {
        attempt_counter=0
        until curl --output /dev/null --silent --head --fail --max-time 5 "http://localhost:$1"; do
          if [ $attempt_counter -eq 30 ]; then
            echo "Failed to connect to the app on port $1:"
            tail -n 50 "$2"
            exit 1
          fi
          echo "Waiting for the app on port $1 (attempt $attempt_counter of 30)"
          attempt_counter=$(($attempt_counter+1))
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

      # Trace correlation: requests whose trace IDs are known, made before the traffic loop starts.
      # Each route returns its trace ID in X-Ray form (1-<8 hex>-<24 hex>); profile samples link the
      # 32-hex OTel form. The main app's (sampled) requests must link to their traces; the unsampled
      # app's must not link to any.
      trace_id() {
        curl -s --max-time 30 "http://localhost:$1$2" | grep -o '1-[0-9a-f]\{8\}-[0-9a-f]\{24\}' | tr -d '-' | cut -c2-
      }
      MAIN_SDK_TRACE_1=$(trace_id 8080 /aws-sdk-call)
      MAIN_SDK_TRACE_2=$(trace_id 8080 /aws-sdk-call)
      MAIN_HTTP_TRACE_1=$(trace_id 8080 /outgoing-http-call)
      MAIN_HTTP_TRACE_2=$(trace_id 8080 /outgoing-http-call)
      UNSAMPLED_SDK_TRACE_1=$(trace_id 8082 /aws-sdk-call)
      UNSAMPLED_HTTP_TRACE_1=$(trace_id 8082 /outgoing-http-call)

      # Record what each app's profiles must identify as, for the identity checks: each JVM's PID,
      # the instance (host.id / host.name, as the agent's EC2 resource detector reports them from
      # instance metadata) and the agent version from its startup log.
      IMDS_TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
      HOST_ID=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
      HOST_NAME=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/hostname)
      DISTRO_VERSION=$(grep -m1 -o 'opentelemetry-javaagent - version: [^ ]*' nohup.out | awk '{print $NF}')
      printf '{"mainPid":"%s","cpuPid":"%s","unsampledPid":"%s","hostId":"%s","hostName":"%s","distroVersion":"%s","mainSdkTraceId1":"%s","mainSdkTraceId2":"%s","mainHttpTraceId1":"%s","mainHttpTraceId2":"%s","unsampledSdkTraceId1":"%s","unsampledHttpTraceId1":"%s"}\n' \
        "$(cat main.pid)" "$(cat cpu.pid)" "$(cat unsampled.pid)" "$HOST_ID" "$HOST_NAME" "$DISTRO_VERSION" \
        "$MAIN_SDK_TRACE_1" "$MAIN_SDK_TRACE_2" "$MAIN_HTTP_TRACE_1" "$MAIN_HTTP_TRACE_2" "$UNSAMPLED_SDK_TRACE_1" "$UNSAMPLED_HTTP_TRACE_1" > profiler-context.json
      cat profiler-context.json

      EOF
    ]
  }

  depends_on = [aws_instance.main_service_instance, null_resource.upload_adot_jar]
}

# Single-instance traffic generator. Keeps request threads busy so wall samples land inside request
# spans (operation label, application stack frames) and the allocation profiler sees request-driven
# allocations. /aws-sdk-call and /outgoing-http-call block on I/O, giving off-CPU (SLEEPING) samples;
# the handler work itself gives on-CPU (RUNNABLE) samples.
resource "null_resource" "traffic_generator_setup" {
  connection {
    type        = "ssh"
    user        = var.user
    private_key = local.private_key_content
    host        = aws_instance.main_service_instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
        sudo yum install tmux -y

        tmux new -s traffic-generator -d
        tmux send-keys -t traffic-generator "while true; do \
          for port in 8080 8081 8082 8083; do \
            curl -s -o /dev/null http://localhost:\$port/ ; \
            curl -s -o /dev/null http://localhost:\$port/outgoing-http-call ; \
            curl -s -o /dev/null http://localhost:\$port/aws-sdk-call ; \
          done ; \
          sleep 1 ; \
        done" C-m
      EOF
    ]
  }

  depends_on = [null_resource.main_service_setup]
}

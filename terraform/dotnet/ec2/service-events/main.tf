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

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Pin the provider to the region under test. Without an explicit region the provider falls back to
# the ambient AWS_REGION of whichever credentials the caller configured, which can place the
# instance in a different region than the one the CW agent ships signals to and the validators query.
provider "aws" {
  region = var.aws_region
}

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

  # Single source of truth for the service name. The Service Events log group name is derived from
  # service.name by the CW agent, and the validators pin aws.service_events.deployment.id to the
  # same value, so the log group resource and the SERVICE_NAME export must not drift apart.
  service_name   = "dotnet-sample-application-${var.test_id}"
  log_group_name = "/aws/service-events/${local.service_name}"
}

data "aws_ami" "ami" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["al20*-ami-minimal-*-x86_64"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
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

# Each run emits into a run-unique Service Events log group. Left to the CW agent these groups are
# created with never-expire retention and outlive the test, accumulating one orphaned group per run.
# Managing the group here gives it a one-day retention and makes `terraform destroy` remove it, so
# even a failed destroy caps storage at a day.
resource "aws_cloudwatch_log_group" "service_events" {
  name              = local.log_group_name
  retention_in_days = 1

  tags = {
    Name = "service-events-${var.test_id}"
  }
}

resource "aws_instance" "main_service_instance" {
  ami                                  = data.aws_ami.ami.id # Amazon Linux 2023 (free tier)
  instance_type                        = "t3.small"
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
    volume_size = 5
  }

  tags = {
    Name = "main-service-${var.test_id}"
  }

  # The instance emits into the managed log group. Making that relationship explicit reverses the
  # order on destroy: Terraform waits for the instance (and its CW Agent) to terminate before it
  # deletes the log group, so the agent cannot recreate the group after cleanup.
  depends_on = [aws_cloudwatch_log_group.service_events]
}

resource "null_resource" "main_service_setup" {
  connection {
    type        = "ssh"
    user        = var.user
    private_key = local.private_key_content
    host        = aws_instance.main_service_instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
      #!/bin/bash
      # Fail fast and loudly. Without this a failed distro download, a missing Service Events
      # assembly or an app that exits on startup all surface later as an opaque validator timeout
      # instead of a provisioning error.
      set -euo pipefail

      # Download an artifact from either an s3:// or https:// URI. The download logic lives here, so
      # a caller supplies only a validated URI and no caller-controlled string is ever executed on
      # the instance.
      download_artifact() {
        uri="$1"
        dest="$2"
        case "$uri" in
          s3://*)
            aws s3 cp "$uri" "$dest"
            ;;
          https://*)
            curl -fsSL -o "$dest" "$uri"
            ;;
          *)
            echo "Unsupported artifact URI (expected s3:// or https://): $uri"
            exit 1
            ;;
        esac
      }

      # Install DotNet and wget
      sudo yum install -y wget unzip
      sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
      sudo wget -O /etc/yum.repos.d/microsoft-prod.repo https://packages.microsoft.com/config/fedora/37/prod.repo
      if ! sudo dnf install -y dotnet-sdk-${var.language_version}; then
        echo "dnf install failed, falling back to dotnet-install.sh"
        sudo dnf install -y icu
        curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel ${var.language_version}
        export PATH="$HOME/.dotnet:$PATH"
      fi

      # Copy in CW Agent configuration
      agent_config='${replace(replace(file("./amazon-cloudwatch-agent.json"), "/\\s+/", ""), "$REGION", var.aws_region)}'
      echo $agent_config > amazon-cloudwatch-agent.json

      # Get and run CW agent rpm. The App Signals CW Agent config provisions the OTLP receiver on
      # 4316 and the Service Events routing that forwards signals to CloudWatch.
      download_artifact '${var.cw_agent_rpm_uri}' ./cw-agent.rpm
      sudo rpm -U ./cw-agent.rpm
      sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json

      # The agent is the only path Service Events signals take to CloudWatch, so confirm it is
      # running and that the App Signals OTLP receiver is accepting connections on 4316 before the
      # app starts emitting. A connection (any HTTP status) means the port is bound.
      sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status
      agent_attempts=0
      until curl -s -o /dev/null --max-time 2 http://127.0.0.1:4316/; do
        if [ $agent_attempts -ge 30 ]; then
          echo "CW Agent OTLP receiver is not listening on 4316 after 60s"
          sudo cat /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log || true
          exit 1
        fi
        agent_attempts=$((agent_attempts+1))
        sleep 2
      done
      echo "CW Agent OTLP receiver is listening on 4316"

      # Get ADOT .NET distro and unzip it
      download_artifact '${var.adot_distro_uri}' ./dotnet-distro.zip
      unzip -o -d dotnet-distro ./dotnet-distro.zip

      # Get and run the sample application with configuration
      download_artifact '${var.sample_app_zip}' ./dotnet-sample-app.zip
      unzip -o dotnet-sample-app.zip

      # Get Absolute Path
      current_dir=$(pwd)
      echo $current_dir

      # Service Events ships as its own assembly, though it is loaded by the base distro plugin
      # rather than being a plugin in its own right (see OTEL_DOTNET_AUTO_PLUGINS below). A distro
      # build predating the feature still starts and instruments normally, but emits no Service
      # Events signal at all, so every validator would time out with no diagnostic. Check the
      # assembly is present before launching.
      service_events_dll=$(find "$current_dir/dotnet-distro" -name 'AWS.Distro.OpenTelemetry.ServiceEvents.dll' -print -quit)
      if [ -z "$service_events_dll" ]; then
        echo "Service Events assembly AWS.Distro.OpenTelemetry.ServiceEvents.dll not found in the distro."
        echo "This distro build does not ship Service Events; the test cannot pass against it."
        exit 1
      fi
      echo "Found Service Events assembly at $service_events_dll"

      # Export environment variables for instrumentation
      cd ./asp_frontend_service
      dotnet build
      export CORECLR_ENABLE_PROFILING=1
      export CORECLR_PROFILER={918728DD-259F-4A6A-AC2B-B85E1B658318}
      export CORECLR_PROFILER_PATH=$current_dir/dotnet-distro/linux-x64/OpenTelemetry.AutoInstrumentation.Native.so
      export DOTNET_ADDITIONAL_DEPS=$current_dir/dotnet-distro/AdditionalDeps
      export DOTNET_SHARED_STORE=$current_dir/dotnet-distro/store
      export DOTNET_STARTUP_HOOKS=$current_dir/dotnet-distro/net/OpenTelemetry.AutoInstrumentation.StartupHook.dll
      export OTEL_DOTNET_AUTO_HOME=$current_dir/dotnet-distro
      # Service Events is hosted by the AWS distro plugin itself, so this is the single standard
      # entry the distro's own launch scripts set. There is deliberately no ServiceEvents-specific
      # plugin: naming one would reference a type that does not exist and fail plugin loading.
      # Keeping this list identical to the default is also what proves the customer-does-nothing
      # path works.
      export OTEL_DOTNET_AUTO_PLUGINS="AWS.Distro.OpenTelemetry.AutoInstrumentation.Plugin, AWS.Distro.OpenTelemetry.AutoInstrumentation"
      export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
      export OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4316
      export OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT=http://127.0.0.1:4316/v1/metrics
      export OTEL_METRICS_EXPORTER=none
      # Application Signals enablement bundles Service Events (Lambda excluded). This test asserts
      # that bundling, so OTEL_AWS_SERVICE_EVENTS_ENABLED is deliberately left unset: setting it
      # would force Service Events on and mask a regression in the bundled default.
      export OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true
      export OTEL_AWS_APPLICATION_SIGNALS_RUNTIME_ENABLED=false
      export OTEL_TRACES_SAMPLER=always_on
      export SERVICE_NAME='${local.service_name}'
      export OTEL_RESOURCE_ATTRIBUTES="service.name=$${SERVICE_NAME},deployment.environment.name=ec2:service-events"
      # Service Events signals export over the shared no-infix OTLP endpoints to the CW Agent's
      # 4316 receiver (not ..._SERVICE_EVENTS_..._ENDPOINT).
      export OTEL_AWS_OTLP_LOGS_ENDPOINT=http://127.0.0.1:4316/v1/logs
      export OTEL_AWS_OTLP_METRICS_ENDPOINT=http://127.0.0.1:4316/v1/metrics
      # Service Events configuration
      export OTEL_AWS_SERVICE_EVENTS_FUNCTION_INSTRUMENT_ENABLED=true
      export OTEL_AWS_SERVICE_EVENTS_SAMPLING_MODE=always
      # Flush cadences. The Service Events MeterProvider runs a fixed 60s periodic reader and does
      # not honor OTEL_METRIC_EXPORT_INTERVAL, so without these a signal can take a full window to
      # surface and every validator spends its retry budget waiting on a timer.
      export OTEL_AWS_SERVICE_EVENTS_ENDPOINT_FLUSH_INTERVAL=2000
      export OTEL_AWS_SERVICE_EVENTS_FUNCTION_CALL_FLUSH_INTERVAL=2000
      export OTEL_AWS_SERVICE_EVENTS_INCIDENT_SNAPSHOT_FLUSH_INTERVAL=2000
      # Incident rate limiting is three-layered: per-flush batch dedup, a per-error-signature
      # ceiling per minute, and a global ceiling per minute. The traffic generator replays one
      # identical exception every 5s for the whole run, so the default ceilings would suppress the
      # snapshots this test validates.
      export OTEL_AWS_SERVICE_EVENTS_INCIDENT_SNAPSHOT_MAX_PER_MINUTE=1000
      export OTEL_AWS_SERVICE_EVENTS_INCIDENT_SNAPSHOT_MAX_SAME_ERROR=100
      # Function instrumentation scope: framework Activity source names (HttpClient), not user code.
      export OTEL_AWS_SERVICE_EVENTS_PACKAGES_INCLUDE='${var.service_events_packages_include}'
      # Per-endpoint latency thresholds: drives the trigger_type="latency" IncidentSnapshot.
      export OTEL_AWS_SERVICE_EVENTS_LATENCY_THRESHOLDS='${var.service_events_latency_thresholds}'
      # Deployment identifier: the SDK stamps aws.service_events.deployment.id from this value; the
      # validators pin it to the service name, so source it from SERVICE_NAME.
      export OTEL_AWS_SERVICE_EVENTS_DEPLOYMENT_ID="$${SERVICE_NAME}"
      # VCS provenance: stamps vcs.ref.head.revision / vcs.repository.url.full on every event.
      export OTEL_AWS_SERVICE_EVENTS_GIT_COMMIT_SHA='${var.service_events_git_commit_sha}'
      export OTEL_AWS_SERVICE_EVENTS_GIT_REPO_URL='${var.service_events_git_repo_url}'
      # All traffic is generated on this instance and the validators query CloudWatch rather than
      # the app, so bind to loopback instead of publishing the app on the instance's public
      # interface through the default security group.
      export ASPNETCORE_URLS=http://127.0.0.1:8080
      nohup dotnet bin/Debug/netcoreapp${var.language_version}/asp_frontend_service.dll &> nohup.out &
      app_pid=$!

      # The application needs time to come up and reach a steady state, this should not take longer than 30 seconds
      sleep 30

      # A crash on startup (bad profiler path, incompatible distro, plugin type-load failure) leaves
      # the endpoint checks below failing for 5 minutes with no explanation. Check the process first
      # and surface its output.
      if ! kill -0 "$app_pid" 2>/dev/null; then
        echo "Sample app exited during startup. Application output:"
        cat nohup.out || true
        exit 1
      fi

      # A plugin named in OTEL_DOTNET_AUTO_PLUGINS that cannot be resolved is reported by the
      # auto-instrumentation loader and otherwise silently yields an app with no Service Events.
      if grep -Eqi 'Failed to load plugin|Error loading plugin|Unable to load type' nohup.out; then
        echo "The auto-instrumentation loader failed to load a configured plugin:"
        grep -Ei 'Failed to load plugin|Error loading plugin|Unable to load type' nohup.out || true
        exit 1
      fi

      # Check if the application is up. If it is not up, then exit 1.
      attempt_counter=0
      max_attempts=30
      until $(curl --output /dev/null --silent --fail --max-time 5 $(echo "http://127.0.0.1:8080/health" | tr -d '"')); do
        if [ $attempt_counter -eq $max_attempts ];then
          echo "Failed to connect to endpoint. Application output:"
          cat nohup.out || true
          exit 1
        fi
        echo "Attempting to connect to the main endpoint. Tried $attempt_counter out of $max_attempts"
        attempt_counter=$((attempt_counter+1))
        sleep 10
      done

      echo "Successfully connected to main endpoint"

      # Every signal this test validates is gated on a specific route returning a specific status.
      # Assert those contracts here so a sample-app artifact that predates these routes fails
      # provisioning with a clear message instead of failing five validators 30 minutes later.
      check_route() {
        route="$1"
        expected="$2"
        actual=$(curl -s -o /dev/null -w '%%{http_code}' --max-time 15 "http://127.0.0.1:8080$route")
        if [ "$actual" != "$expected" ]; then
          echo "Route $route returned HTTP $actual, expected $expected."
          echo "The deployed sample-app artifact is probably missing this route."
          exit 1
        fi
        echo "Route $route returned HTTP $actual as expected"
      }
      check_route /health 200
      check_route /success 200
      check_route /failed-call 200
      check_route /exception 500

      EOF
    ]
  }

  depends_on = [aws_instance.main_service_instance, aws_cloudwatch_log_group.service_events]
}

# Single-instance traffic generator. Unlike the default test there is no remote service:
# Service Events emits autonomously from the instrumented frontend, so we only need to drive the
# frontend's own endpoints. The /exception route throws (HTTP 500 with a captured exception),
# which gates the exception IncidentSnapshot and the EndpointErrorMetric `count` data point. The
# /success route makes an in-process HttpClient call to the app's own /health route (HTTP 200),
# producing the FunctionCall (service.function.duration) data point and — via the 1ms per-endpoint
# latency threshold — the latency-triggered IncidentSnapshot. Driving a loopback route rather than
# a public site keeps both signals independent of DNS, TLS and egress from the test VPC.
# The DeploymentEvent is emitted on startup.
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
        set -euo pipefail

        sudo yum install tmux -y

        tmux new -s traffic-generator -d
        tmux send-keys -t traffic-generator "while true; do \
          curl -s -o /dev/null http://127.0.0.1:8080/ ; \
          curl -s -o /dev/null http://127.0.0.1:8080/success ; \
          curl -s -o /dev/null http://127.0.0.1:8080/failed-call ; \
          curl -s -o /dev/null http://127.0.0.1:8080/exception ; \
          sleep 5 ; \
        done" C-m

        # tmux new -d succeeds even if the session dies immediately, which would leave the app
        # receiving no traffic and every validator failing for the wrong reason.
        sleep 5
        if ! tmux has-session -t traffic-generator 2>/dev/null; then
          echo "Traffic generator tmux session is not running."
          exit 1
        fi
        echo "Traffic generator is running"
      EOF
    ]
  }

  depends_on = [null_resource.main_service_setup]
}

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
}

data "aws_ami" "ami" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["al20*-ami-minimal-*-${var.cpu_architecture}"]
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
  ami                                  = data.aws_ami.ami.id # Amazon Linux 2023 (free tier)
  instance_type                        = var.cpu_architecture == "x86_64" ? "t3.small" : "t4g.small"
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
      # Make the Terraform fail if any step throws an error
      set -o errexit

      # Set up environment
      sudo yum install unzip wget tmux aws-cli -y

      # Install nvm
      wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm

      # Install the specified Node.js version, or use the system's version if 'none'
      if [[ "${var.language_version}" != "none" ]]; then
        nvm install ${var.language_version}
        nvm use ${var.language_version}
      else
        sudo yum install nodejs -y
        echo "Using the default Node.js version provided by the OS"
      fi

      echo "Node version in use: $(node -v)"

      # enable ec2 instance connect for debug
      sudo yum install ec2-instance-connect -y

      # Copy in CW Agent configuration
      agent_config='${replace(replace(file("./amazon-cloudwatch-agent.json"), "/\\s+/", ""), "$REGION", var.aws_region)}'
      echo $agent_config > amazon-cloudwatch-agent.json

      # Get and run CW agent rpm. Enabling the Application Signals receiver provisions the OTLP
      # endpoint on localhost:4316 and the /aws/service-events/<service.name> log group that the
      # Service Events log signals (DeploymentEvent + IncidentSnapshot) are routed to.
      ${var.get_cw_agent_rpm_command}
      sudo rpm -U ./cw-agent.rpm
      sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json

      # Get and unzip the sample application. node-sample-app.zip is the multi-app Node bundle
      # (frontend-service/, remote-service/, serviceevents-express/); the Service Events test uses
      # the serviceevents-express app (app.js + helpers.js + package.json).
      aws s3 cp ${var.sample_app_zip} ./node-sample-app.zip
      unzip -o node-sample-app.zip
      cd serviceevents-express

      # Install the sample application dependencies (express)
      npm install

      # Get ADOT instrumentation and install it. The released distro carries the serviceevents code.
      ${var.get_adot_instrumentation_command}

      # The ADOT distro auto-instruments via the --require register hook. Service Events is bundled
      # with Application Signals: enabling App Signals turns it on (Lambda excluded). When App Signals
      # is enabled the Service Events OTLP endpoints default to the bundled CW Agent receiver on
      # localhost:4316 (/v1/logs + /v1/metrics), so no Service-Events-specific endpoint env vars are
      # needed. PACKAGES_INCLUDE scopes function instrumentation to helpers.js so the FunctionCall
      # metric (service.function.duration) is emitted. The latency threshold on /slow fires the
      # latency-triggered IncidentSnapshot. Run under tmux so it survives the SSH connection close.
      tmux new-session -d -s frontend bash
      tmux send-keys -t frontend 'export OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true' C-m
      tmux send-keys -t frontend 'export OTEL_AWS_APPLICATION_SIGNALS_RUNTIME_ENABLED=false' C-m
      tmux send-keys -t frontend 'export OTEL_METRICS_EXPORTER=none' C-m
      tmux send-keys -t frontend 'export OTEL_TRACES_EXPORTER=otlp' C-m
      tmux send-keys -t frontend 'export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:4316/v1/traces' C-m
      tmux send-keys -t frontend 'export OTEL_EXPORTER_OTLP_TRACES_PROTOCOL=http/protobuf' C-m
      tmux send-keys -t frontend 'export OTEL_TRACES_SAMPLER=always_on' C-m
      tmux send-keys -t frontend 'export OTEL_AWS_SERVICE_EVENTS_SAMPLING_MODE=always' C-m
      tmux send-keys -t frontend "export OTEL_AWS_SERVICE_EVENTS_PACKAGES_INCLUDE='${var.service_events_packages_include}'" C-m
      tmux send-keys -t frontend "export OTEL_AWS_SERVICE_EVENTS_DEPLOYMENT_ID='node-sample-application-${var.test_id}'" C-m
      tmux send-keys -t frontend 'export OTEL_AWS_SERVICE_EVENTS_FUNCTION_INSTRUMENT_ENABLED=true' C-m
      tmux send-keys -t frontend "export OTEL_AWS_SERVICE_EVENTS_GIT_COMMIT_SHA='${var.service_events_git_commit_sha}'" C-m
      tmux send-keys -t frontend "export OTEL_AWS_SERVICE_EVENTS_GIT_REPO_URL='${var.service_events_git_repo_url}'" C-m
      tmux send-keys -t frontend "export OTEL_AWS_SERVICE_EVENTS_LATENCY_THRESHOLDS='${var.service_events_latency_thresholds}'" C-m
      tmux send-keys -t frontend "export OTEL_RESOURCE_ATTRIBUTES='service.name=node-sample-application-${var.test_id},deployment.environment.name=ec2:service-events'" C-m
      tmux send-keys -t frontend "export OTEL_SERVICE_NAME='node-sample-application-${var.test_id}'" C-m
      tmux send-keys -t frontend "export AWS_REGION='${var.aws_region}'" C-m
      tmux send-keys -t frontend 'node --require "@aws/aws-distro-opentelemetry-node-autoinstrumentation/register" app.js' C-m

      # The application needs time to come up and reach a steady state, this should not take longer than 30 seconds
      sleep 30

      # Check if the application is up. If it is not up, then exit 1.
      attempt_counter=0
      max_attempts=30
      until $(curl --output /dev/null --silent --head --fail --max-time 5 $(echo "http://localhost:8080/health" | tr -d '"')); do
        if [ $attempt_counter -eq $max_attempts ];then
          echo "Failed to connect to endpoint."
          exit 1
        fi
        echo "Attempting to connect to the main endpoint. Tried $attempt_counter out of $max_attempts"
        attempt_counter=$(($attempt_counter+1))
        sleep 10
      done

      echo "Successfully connected to main endpoint"

      EOF
    ]
  }

  depends_on = [aws_instance.main_service_instance]
}

# Single-instance traffic generator. Unlike the default test there is no remote service:
# Service Events emits autonomously from the instrumented Express app, so we only drive the
# app's own endpoints. /exception throws a ValueError from the instrumented helpers.validateInput
# (HTTP 500 with a captured exception) — the gate for the EndpointErrorMetric `count` data point
# and the exception-triggered IncidentSnapshot. /success exercises the instrumented helpers
# (processData/computeResult) for the FunctionCall metric, and /slow busy-waits past the latency
# threshold for the latency-triggered IncidentSnapshot. DeploymentEvent is emitted on startup.
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
          curl -s -o /dev/null http://localhost:8080/success ; \
          curl -s -o /dev/null http://localhost:8080/slow ; \
          curl -s -o /dev/null http://localhost:8080/fault ; \
          curl -s -o /dev/null http://localhost:8080/exception ; \
          sleep 5 ; \
        done" C-m
      EOF
    ]
  }

  depends_on = [null_resource.main_service_setup]
}

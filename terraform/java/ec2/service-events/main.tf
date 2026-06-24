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
  instance_type                        = var.cpu_architecture == "x86_64" ? "t3.micro" : "t4g.micro"
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

      # Install wget
      sudo yum install wget -y

      # Install Java
      if [[ "${var.language_version}" == "8" ]]; then
        sudo yum install java-1.8.0-amazon-corretto -y
      else
        sudo yum install java-${var.language_version}-amazon-corretto -y
      fi

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

      # Get ADOT Java agent
      ${var.get_adot_jar_command}

      # Get and run the sample application with configuration
      aws s3 cp ${var.sample_app_jar} ./main-service.jar

      # The Java agent attaches via -javaagent and auto-loads the AWS configurator. Service Events is
      # bundled with Application Signals: enabling App Signals turns it on (Lambda excluded). When
      # App Signals is enabled the Service Events OTLP endpoints default to the bundled CW Agent
      # receiver on localhost:4316 (/v1/logs + /v1/metrics), so no Service-Events-specific endpoint
      # env vars are needed. Trace/metric exporters point at 4316 to match the rest of the Java fleet.
      JAVA_TOOL_OPTIONS=' -javaagent:/home/ec2-user/adot.jar' \
      OTEL_METRICS_EXPORTER=none \
      OTEL_LOGS_EXPORT=none \
      OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true \
      OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT=http://localhost:4316/v1/metrics \
      OTEL_EXPORTER_OTLP_TRACES_PROTOCOL=http/protobuf \
      OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:4316/v1/traces \
      OTEL_TRACES_SAMPLER=always_on \
      OTEL_INSTRUMENTATION_COMMON_EXPERIMENTAL_CONTROLLER_TELEMETRY_ENABLED=true \
      OTEL_AWS_SERVICE_EVENTS_SAMPLING_MODE=always \
      OTEL_AWS_SERVICE_EVENTS_FUNCTION_INSTRUMENT_ENABLED=true \
      OTEL_AWS_SERVICE_EVENTS_PACKAGES_INCLUDE='${var.service_events_packages_include}' \
      OTEL_AWS_SERVICE_EVENTS_DEPLOYMENT_ID='java-sample-application-${var.test_id}' \
      OTEL_AWS_SERVICE_EVENTS_GIT_COMMIT_SHA='${var.service_events_git_commit_sha}' \
      OTEL_AWS_SERVICE_EVENTS_GIT_REPO_URL='${var.service_events_git_repo_url}' \
      OTEL_AWS_SERVICE_EVENTS_LATENCY_THRESHOLDS='${var.service_events_latency_thresholds}' \
      OTEL_RESOURCE_ATTRIBUTES="service.name=java-sample-application-${var.test_id},deployment.environment.name=ec2:service-events" \
      AWS_REGION='${var.aws_region}' \
      nohup java -XX:+UseG1GC -jar main-service.jar &> nohup.out &

      # The application needs time to come up and reach a steady state, this should not take longer than 30 seconds
      sleep 30

      # Check if the application is up. If it is not up, then exit 1.
      attempt_counter=0
      max_attempts=30
      until $(curl --output /dev/null --silent --head --fail --max-time 5 $(echo "http://localhost:8080" | tr -d '"')); do
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
# Service Events emits autonomously from the instrumented frontend, so we only need to drive
# the frontend's own endpoints. The /mysql route throws an unhandled exception when the RDS_*
# env vars are unset, so the springboot app returns HTTP 500 with a captured exception. The exact
# exception class depends on the deployed jar: the current source rethrows a RuntimeException from
# the caught SQLException, while older jars NullPointerException on the null connection. The
# validator accepts either class. That 5xx + captured-exception is exactly the gate for the
# EndpointErrorMetric `count` data point and the exception-triggered IncidentSnapshot. The healthy
# routes drive FunctionCall + the latency-triggered IncidentSnapshot (/aws-sdk-call).
# DeploymentEvent is emitted on startup.
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
          curl -s -o /dev/null http://localhost:8080/ ; \
          curl -s -o /dev/null http://localhost:8080/outgoing-http-call ; \
          curl -s -o /dev/null http://localhost:8080/aws-sdk-call ; \
          curl -s -o /dev/null http://localhost:8080/mysql ; \
          sleep 5 ; \
        done" C-m
      EOF
    ]
  }

  depends_on = [null_resource.main_service_setup]
}

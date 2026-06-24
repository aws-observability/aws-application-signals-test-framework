# ------------------------------------------------------------------------
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# -------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

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
  ami                                  = data.aws_ami.ami.id
  instance_type                        = var.cpu_architecture == "x86_64" ? "t3.micro" : "t4g.micro"
  key_name                             = local.ssh_key_name
  iam_instance_profile                 = var.iam_instance_profile
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
      set -o errexit

      sudo yum install wget -y
      sudo yum install unzip -y

      if [[ "${var.language_version}" == "8" ]]; then
        sudo yum install java-1.8.0-amazon-corretto -y
      else
        sudo yum install java-${var.language_version}-amazon-corretto -y
      fi

      sudo yum install ec2-instance-connect -y

      agent_config='${replace(replace(file("./amazon-cloudwatch-agent.json"), "/\\s+/", ""), "$REGION", var.aws_region)}'
      echo $agent_config > amazon-cloudwatch-agent.json

      ${var.get_cw_agent_rpm_command}
      sudo rpm -U ./cw-agent.rpm
      sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json

      ${var.get_adot_jar_command}

      aws s3 cp ${var.sample_app_jar} ./main-service.jar

      # Start the sample app under the ADOT Java agent with Dynamic Instrumentation enabled.
      # Env is kept aligned with the Python adot-di test: only the DI vars + service identity, NO
      # OTEL_AWS_APPLICATION_SIGNALS_ENABLED / OTLP exporter endpoints. App Signals is intentionally
      # left off because (a) DI emits snapshots through the local CloudWatch agent independently of
      # the App Signals pipeline, matching Python, and (b) enabling it also turns on ServiceEvents,
      # which emits unrelated logs into the same /aws/service-events/<service> log group.
      # We also do NOT set OTEL_AWS_DYNAMIC_INSTRUMENTATION_API_URL — the agent reaches the control
      # plane via the local CW agent (its default), not the public endpoint directly. Poll intervals
      # are dropped to 15s (vs the 60s/600s defaults) so the test doesn't wait minutes for configs.
      JAVA_TOOL_OPTIONS=' -javaagent:/home/ec2-user/adot.jar' \
      OTEL_METRICS_EXPORTER=none \
      OTEL_LOGS_EXPORT=none \
      OTEL_AWS_DYNAMIC_INSTRUMENTATION_ENABLED=true \
      OTEL_AWS_DYNAMIC_INSTRUMENTATION_PROBE_POLL_INTERVAL=15 \
      OTEL_AWS_DYNAMIC_INSTRUMENTATION_BREAKPOINT_POLL_INTERVAL=15 \
      OTEL_SERVICE_NAME=${var.service_name_prefix}-${var.test_id} \
      OTEL_RESOURCE_ATTRIBUTES="deployment.environment.name=${var.di_environment}" \
      AWS_REGION='${var.aws_region}' \
      nohup java -XX:+UseG1GC -jar main-service.jar &> /tmp/sdk.log &

      sleep 30

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
        sudo yum install nodejs aws-cli unzip tmux -y

        aws s3 cp ${var.traffic_generator_zip} ./traffic-generator.zip
        unzip ./traffic-generator.zip -d ./

        npm install

        tmux new -s traffic-generator -d
        tmux send-keys -t traffic-generator "export MAIN_ENDPOINT=\"localhost:8080\"" C-m
        # The traffic generator gates on REMOTE_ENDPOINT being set even though the DI test has no
        # remote service. Point it at localhost so the generator unblocks and hits the breakpoint
        # targets (/outgoing-http-call, /aws-sdk-call, /remote-service, /mysql). The /remote-service
        # call will fail with a connection error, which is fine — each URL is fired independently.
        tmux send-keys -t traffic-generator "export REMOTE_ENDPOINT=\"localhost\"" C-m
        tmux send-keys -t traffic-generator "export ID=\"${var.test_id}\"" C-m
        tmux send-keys -t traffic-generator "npm start" C-m

      EOF
    ]
  }

  depends_on = [null_resource.main_service_setup]
}

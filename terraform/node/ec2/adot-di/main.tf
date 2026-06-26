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

# Shared DI environment variables, rendered as bash `export` lines and consumed in the
# EC2 user-data below. Lives in one place so python/java/node adot-di modules stay in sync.
module "di_env" {
  source       = "../../../common/di-env"
  service_name = "${var.service_name_prefix}-${var.test_id}"
  environment  = var.di_environment
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

      agent_config='${replace(replace(file("./amazon-cloudwatch-agent.json"), "/\\s+/", ""), "$REGION", var.aws_region)}'
      echo $agent_config > amazon-cloudwatch-agent.json

      ${var.get_cw_agent_rpm_command}
      sudo rpm -U ./cw-agent.rpm
      sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json

      aws s3 cp ${var.sample_app_zip} ./node-sample-app.zip
      unzip -o node-sample-app.zip

      # Enter appropriate service folder
      cd frontend-service

      # Install sample application
      npm install

      # Get ADOT instrumentation and install it
      ${var.get_adot_instrumentation_command}

      # Start the sample app under the ADOT Node agent with Dynamic Instrumentation enabled.
      # Env is kept aligned with the Python/Java adot-di tests: only the DI vars + service identity,
      # NO OTEL_AWS_APPLICATION_SIGNALS_ENABLED / OTLP exporter endpoints. App Signals is intentionally
      # left off because DI emits snapshots through the local CloudWatch agent independently of the App
      # Signals pipeline, matching Python/Java, and enabling it also turns on ServiceEvents, which emits
      # unrelated logs into the same /aws/service-events/<service> log group.
      # We also do NOT set OTEL_AWS_DYNAMIC_INSTRUMENTATION_API_URL — the agent reaches the control
      # plane via the local CW agent proxy (default http://localhost:2000), not the public endpoint.
      # The shared DI env vars come from the common terraform/common/di-env module so they stay
      # identical across python/java/node.
      tmux new-session -d -s frontend bash
      ${join("\n      ", [for line in split("\n", module.di_env.export_lines) : "tmux send-keys -t frontend '${line}' C-m"])}
      tmux send-keys -t frontend "export AWS_REGION='${var.aws_region}'" C-m
      tmux send-keys -t frontend "export TESTING_ID='${var.test_id}'" C-m
      tmux send-keys -t frontend 'cd /home/ec2-user/frontend-service' C-m
      tmux send-keys -t frontend 'node --require "@aws/aws-distro-opentelemetry-node-autoinstrumentation/register" index.js' C-m

      sleep 30

      attempt_counter=0
      max_attempts=30
      until $(curl --output /dev/null --silent --head --fail --max-time 5 $(echo "http://localhost:8000/healthcheck" | tr -d '"')); do
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
        aws s3 cp ${var.traffic_generator_zip} ./traffic-generator.zip
        unzip ./traffic-generator.zip -d ./

        npm install

        tmux new -s traffic-generator -d
        tmux send-keys -t traffic-generator "export MAIN_ENDPOINT=\"localhost:8000\"" C-m
        # The traffic generator gates on REMOTE_ENDPOINT being set even though the DI test has no
        # remote service. Point it at localhost so the generator unblocks and hits the breakpoint
        # targets. The /remote-service call will fail with a connection error, which is fine —
        # each URL is fired independently.
        tmux send-keys -t traffic-generator "export REMOTE_ENDPOINT=\"localhost\"" C-m
        tmux send-keys -t traffic-generator "export ID=\"${var.test_id}\"" C-m
        tmux send-keys -t traffic-generator "npm start" C-m

      EOF
    ]
  }

  depends_on = [null_resource.main_service_setup]
}

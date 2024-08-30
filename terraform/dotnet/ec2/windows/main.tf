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

data "aws_ami" "ami" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base-*"]
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
    values = ["/dev/sda1"]
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

locals {
  ssh_key_name        = aws_key_pair.aws_ssh_key.key_name
  private_key_content = tls_private_key.ssh_key.private_key_pem
}

resource "aws_instance" "main_service_instance" {
  ami                                  = data.aws_ami.ami.id
  instance_type                        = "t3.large"
  key_name                             = local.ssh_key_name
  iam_instance_profile                 = "APP_SIGNALS_EC2_TEST_ROLE"
  vpc_security_group_ids               = [aws_default_vpc.default.default_security_group_id]
  associate_public_ip_address          = true
  instance_initiated_shutdown_behavior = "terminate"
  metadata_options {
    http_tokens = "required"
  }
  get_password_data = true

  tags = {
    Name = "main-service-${var.test_id}"
  }

  user_data = <<-EOF
  <powershell>
      $file = $env:SystemRoot + "\Temp\" + (Get-Date).ToString("MM-dd-yy-hh-mm") + ".log"
      New-Item $file -ItemType file
      Start-Transcript -Path $file -Append
      Write-Host "Block RDP"
      Get-NetFirewallRule -DisplayName "Remote Desktop - User Mode (TCP-In)" | Set-NetFirewallRule -Enabled False
      Get-Service -Name TermService | Select-Object -ExpandProperty DependentServices | ForEach-Object { Stop-Service -Name $_.Name -Force }
      Stop-Service -Name TermService -Force
      Set-Service -Name TermService -StartupType Disabled
      Write-Host "Install AWS CLI"
      msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi /qn
      Write-Host "Finish execution"
      Stop-Transcript
  </powershell>
  <persist>true</persist>
  EOF
}

resource "aws_instance" "remote_service_instance" {
  ami                                  = data.aws_ami.ami.id
  instance_type                        = "t3.large"
  key_name                             = local.ssh_key_name
  iam_instance_profile                 = "APP_SIGNALS_EC2_TEST_ROLE"
  vpc_security_group_ids               = [aws_default_vpc.default.default_security_group_id]
  associate_public_ip_address          = true
  instance_initiated_shutdown_behavior = "terminate"
  metadata_options {
    http_tokens = "required"
  }
  get_password_data = true

  tags = {
    Name = "remote-service-${var.test_id}"
  }

  user_data = <<-EOF
  <powershell>
      $file = $env:SystemRoot + "\Temp\" + (Get-Date).ToString("MM-dd-yy-hh-mm") + ".log"
      New-Item $file -ItemType file
      Start-Transcript -Path $file -Append
      Write-Host "Block RDP"
      Get-NetFirewallRule -DisplayName "Remote Desktop - User Mode (TCP-In)" | Set-NetFirewallRule -Enabled False
      Get-Service -Name TermService | Select-Object -ExpandProperty DependentServices | ForEach-Object { Stop-Service -Name $_.Name -Force }
      Stop-Service -Name TermService -Force
      Set-Service -Name TermService -StartupType Disabled
      Write-Host "Install AWS-CLI"
      msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi /qn
      Write-Host "Finish execution"
      Stop-Transcript
  </powershell>
  <persist>true</persist>
  EOF
}

# Create SSM Document for main service setup
resource "aws_ssm_document" "main_service_setup" {
  name          = "main_service_setup_${var.test_id}"
  document_type = "Command"

  content = <<-DOC
  {
    "schemaVersion": "2.2",
    "description": "Setup main service instance",
    "mainSteps": [
      {
        "action": "aws:runPowerShellScript",
        "name": "setupMainService",
        "inputs": {
          "runCommand": [
            "curl -o amazon-cloudwatch-agent.json https://raw.githubusercontent.com/aws-observability/aws-application-signals-test-framework/dotnetMergeBranch-windows/terraform/dotnet/ec2/windows/amazon-cloudwatch-agent.json",
            "powershell -Command \"(Get-Content -Path 'amazon-cloudwatch-agent.json') -replace 'REGION', 'us-east-1' | Set-Content -Path 'amazon-cloudwatch-agent.json'\"",
            "curl -o dotnet-ec2-win-default-setup.ps1 https://raw.githubusercontent.com/aws-observability/aws-application-signals-test-framework/dotnetMergeBranch-windows/terraform/dotnet/ec2/windows/dotnet-ec2-win-default-setup.ps1",
            "powershell -ExecutionPolicy Bypass -File ./dotnet-ec2-win-default-setup.ps1 -GetCloudwatchAgentCommand \"${var.get_cw_agent_rpm_command}\" -GetAdotDistroCommand \"${var.get_adot_distro_command}\" -GetSampleAppCommand \"${var.sample_app_zip}\" -TestId \"${var.test_id}\""
          ]
        }
      }
    ]
  }
  DOC
}

# Create SSM Association for main service instance
resource "aws_ssm_association" "main_service_association" {
  name = aws_ssm_document.main_service_setup.name
  targets {
    key    = "InstanceIds"
    values = [aws_instance.main_service_instance.id]
  }

  depends_on = [aws_instance.main_service_instance]
}

# Create SSM Document for remote service setup
resource "aws_ssm_document" "remote_service_setup" {
  name          = "remote_service_setup_${var.test_id}"
  document_type = "Command"

  content = <<-DOC
  {
    "schemaVersion": "2.2",
    "description": "Setup remote service instance",
    "mainSteps": [
      {
        "action": "aws:runPowerShellScript",
        "name": "setupRemoteService",
        "inputs": {
          "runCommand": [
            "curl -o amazon-cloudwatch-agent.json https://raw.githubusercontent.com/aws-observability/aws-application-signals-test-framework/dotnetMergeBranch-windows/terraform/dotnet/ec2/windows/amazon-cloudwatch-agent.json",
            "powershell -Command \"(Get-Content -Path 'amazon-cloudwatch-agent.json') -replace 'REGION', 'us-east-1' | Set-Content -Path 'amazon-cloudwatch-agent.json'\"",
            "curl -o dotnet-ec2-win-default-remote-setup.ps1 https://raw.githubusercontent.com/aws-observability/aws-application-signals-test-framework/dotnetMergeBranch-windows/terraform/dotnet/ec2/windows/dotnet-ec2-win-default-remote-setup.ps1",
            "powershell -ExecutionPolicy Bypass -File ./dotnet-ec2-win-default-remote-setup.ps1 -GetCloudwatchAgentCommand \"${var.get_cw_agent_rpm_command}\" -GetAdotDistroCommand \"${var.get_adot_distro_command}\" -GetSampleAppCommand \"${var.sample_app_zip}\" -TestId \"${var.test_id}\""
          ]
        }
      }
    ]
  }
  DOC
}

# Create SSM Association for remote service instance
resource "aws_ssm_association" "remote_service_association" {
  name = aws_ssm_document.remote_service_setup.name
  targets {
    key    = "InstanceIds"
    values = [aws_instance.remote_service_instance.id]
  }
  depends_on = [aws_instance.remote_service_instance]
}

resource "aws_ssm_document" "traffic_generator_setup" {
  name          = "traffic_generator_setup_${var.test_id}"
  document_type = "Command"

  content = <<-DOC
  {
    "schemaVersion": "2.2",
    "description": "Setup traffic generator",
    "mainSteps": [
      {
        "action": "aws:runPowerShellScript",
        "name": "setupTrafficGenerator",
        "inputs": {
          "runCommand": [
            "curl -o traffic-generator-setup.ps1 https://raw.githubusercontent.com/aws-observability/aws-application-signals-test-framework/dotnetMergeBranch-windows/terraform/dotnet/ec2/windows/traffic-generator-setup.ps1",
            "powershell -ExecutionPolicy Bypass -File traffic-generator-setup.ps1 -RemoteServicePrivateEndpoint \"${aws_instance.remote_service_instance.private_ip}\" -TestID \"${var.test_id}\" -TestCanaryType \"${var.canary_type}\""
          ]
        }
      }
    ]
  }
  DOC
}
#
#resource "aws_ssm_association" "traffic_generator_association" {
#  name = aws_ssm_document.traffic_generator_setup.name
#
#  targets {
#    key    = "InstanceIds"
#    values = [aws_instance.main_service_instance.id]
#  }
#
#  depends_on = [
#    aws_ssm_association.main_service_association,
#    aws_ssm_association.remote_service_association
#  ]
#}
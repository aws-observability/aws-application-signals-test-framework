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
    values = ["Windows_Server-2022-English-Full-Base-*"]
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

  root_block_device {
    volume_size = 35
  }

  tags = {
    Name = "main-service-${var.test_id}"
  }

  user_data = <<-EOF
  <powershell>
      Write-Host "Block RDP"
      Get-NetFirewallRule -DisplayName "Remote Desktop - User Mode (TCP-In)" | Set-NetFirewallRule -Enabled False
      Get-Service -Name TermService | Select-Object -ExpandProperty DependentServices | ForEach-Object { Stop-Service -Name $_.Name -Force }
      Stop-Service -Name TermService -Force
      Set-Service -Name TermService -StartupType Disabled
      msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi /qn
      $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
      $awsCliInstalled = Get-Command aws -ErrorAction SilentlyContinue

      while (-not $awsCliInstalled) {
          Write-Host "Waiting for AWS CLI"
          $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
          $awsCliInstalled = Get-Command aws -ErrorAction SilentlyContinue
          Write-Host "Waiting"
          Start-Sleep -Seconds 5
      }
      Write-Host "AWS CLI Installed"
      Write-Host "Finish execution"
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

  root_block_device {
    volume_size = 35
  }

  tags = {
    Name = "remote-service-${var.test_id}"
  }

  user_data = <<-EOF
  <powershell>
      Write-Host "Block RDP"
      Get-NetFirewallRule -DisplayName "Remote Desktop - User Mode (TCP-In)" | Set-NetFirewallRule -Enabled False
      Get-Service -Name TermService | Select-Object -ExpandProperty DependentServices | ForEach-Object { Stop-Service -Name $_.Name -Force }
      Stop-Service -Name TermService -Force
      Set-Service -Name TermService -StartupType Disabled
      msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi /qn
      $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
      $awsCliInstalled = Get-Command aws -ErrorAction SilentlyContinue

      while (-not $awsCliInstalled) {
          Write-Host "Waiting for AWS CLI"
          $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
          $awsCliInstalled = Get-Command aws -ErrorAction SilentlyContinue
          Write-Host "Waiting"
          Start-Sleep -Seconds 5
      }
      Write-Host "AWS CLI Installed"
      Write-Host "Finish execution"
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
            "aws s3 cp s3://aws-appsignals-sample-app-prod-${var.aws_region}/amazon-cloudwatch-agent.json ./amazon-cloudwatch-agent.json",
            "powershell -Command \"(Get-Content -Path 'amazon-cloudwatch-agent.json') -replace 'REGION', 'us-east-1' | Set-Content -Path 'amazon-cloudwatch-agent.json'\"",
            "aws s3 cp s3://aws-appsignals-sample-app-prod-${var.aws_region}/dotnet-ec2-win-main-setup.ps1 ./dotnet-ec2-win-main-setup.ps1",
            "powershell -ExecutionPolicy Bypass -File ./dotnet-ec2-win-main-setup.ps1 -GetCloudwatchAgentCommand \"${var.get_cw_agent_msi_command}\" -GetAdotDistroCommand \"${var.get_adot_distro_command}\" -GetSampleAppCommand \"${var.sample_app_zip}\" -TestId \"${var.test_id}\" -RemoteServicePrivateEndpoint \"${aws_instance.remote_service_instance.private_ip}\" -AWSRegion \"${var.aws_region}\""
          ]
        }
      }
    ]
  }
  DOC
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
            "aws s3 cp s3://aws-appsignals-sample-app-prod-${var.aws_region}/amazon-cloudwatch-agent.json ./amazon-cloudwatch-agent.json",
            "powershell -Command \"(Get-Content -Path 'amazon-cloudwatch-agent.json') -replace 'REGION', 'us-east-1' | Set-Content -Path 'amazon-cloudwatch-agent.json'\"",
            "aws s3 cp s3://aws-appsignals-sample-app-prod-${var.aws_region}/dotnet-ec2-win-remote-setup.ps1 ./dotnet-ec2-win-remote-setup.ps1",
            "powershell -ExecutionPolicy Bypass -File ./dotnet-ec2-win-remote-setup.ps1 -GetCloudwatchAgentCommand \"${var.get_cw_agent_msi_command}\" -GetAdotDistroCommand \"${var.get_adot_distro_command}\" -GetSampleAppCommand \"${var.sample_app_zip}\" -TestId \"${var.test_id}\""
          ]
        }
      }
    ]
  }
  DOC
}
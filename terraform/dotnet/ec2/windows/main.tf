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
            "$ProgressPreference = 'SilentlyContinue'",
            "wget -O dotnet-install.ps1 https://dot.net/v1/dotnet-install.ps1",
            ".\\dotnet-install.ps1 -Version 8.0.302",
            "Invoke-Expression '${var.get_cw_agent_msi_command}'",
            "Write-Host 'Installing Cloudwatch Agent'",
            "msiexec /i amazon-cloudwatch-agent.msi",
            "$timeout = 30",
            "$interval = 5",
            "$call_cloudwatch = & 'C:\\Program Files\\Amazon\\AmazonCloudWatchAgent\\amazon-cloudwatch-agent-ctl.ps1'",
            "$elapsedTime = 0",
            "while ($elapsedTime -lt $timeout) {",
            "    if ($call_cloudwatch) {",
            "        Start-Sleep -Seconds $interval",
            "        Write-Host 'Install Finished'",
            "        break",
            "    } else {",
            "        $call_cloudwatch = & 'C:\\Program Files\\Amazon\\AmazonCloudWatchAgent\\amazon-cloudwatch-agent-ctl.ps1'",
            "        Write-Host 'Cloudwatch Agent not found. Checking again in $interval seconds...'",
            "        Start-Sleep -Seconds $interval",
            "        $elapsedTime += $interval",
            "    }",
            "}",
            "if ($elapsedTime -ge $timeout) {",
            "    Write-Host 'CloudWatch not found after $timeout seconds.'",
            "}",
            "& 'C:\\Program Files\\Amazon\\AmazonCloudWatchAgent\\amazon-cloudwatch-agent-ctl.ps1' -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json",
            "Invoke-Expression '${var.get_adot_distro_command}'",
            "Invoke-Expression '${var.sample_app_zip}'",
            "Expand-Archive -Path .\\dotnet-sample-app.zip -DestinationPath .\\ -Force",
            "$current_dir = Get-Location",
            "Write-Host $current_dir",
            "Set-Location -Path './asp_frontend_service'",
            "$env:CORECLR_ENABLE_PROFILING = '1'",
            "$env:CORECLR_PROFILER = '{918728DD-259F-4A6A-AC2B-B85E1B658318}'",
            "$env:CORECLR_PROFILER_PATH = '$current_dir\\dotnet-distro\\win-x64\\OpenTelemetry.AutoInstrumentation.Native.dll'",
            "$env:DOTNET_ADDITIONAL_DEPS = '$current_dir\\dotnet-distro\\AdditionalDeps'",
            "$env:DOTNET_SHARED_STORE = '$current_dir\\dotnet-distro\\store'",
            "$env:DOTNET_STARTUP_HOOKS = '$current_dir\\dotnet-distro\\net\\OpenTelemetry.AutoInstrumentation.StartupHook.dll'",
            "$env:OTEL_DOTNET_AUTO_HOME = '$current_dir\\dotnet-distro'",
            "$env:OTEL_DOTNET_AUTO_PLUGINS = 'AWS.Distro.OpenTelemetry.AutoInstrumentation.Plugin, AWS.Distro.OpenTelemetry.AutoInstrumentation'",
            "$env:OTEL_EXPORTER_OTLP_PROTOCOL = 'http/protobuf'",
            "$env:OTEL_EXPORTER_OTLP_ENDPOINT = 'http://127.0.0.1:4316'",
            "$env:OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT = 'http://127.0.0.1:4316/v1/metrics'",
            "$env:OTEL_METRICS_EXPORTER = 'none'",
            "$env:OTEL_RESOURCE_ATTRIBUTES = 'service.name=dotnet-sample-application-${var.test_id}'",
            "$env:OTEL_AWS_APPLICATION_SIGNALS_ENABLED = 'true'",
            "$env:OTEL_TRACES_SAMPLER = 'always_on'",
            "$env:ASPNETCORE_URLS = 'http://0.0.0.0:8080'",
            "dotnet build",
            "Start-Process -FilePath 'dotnet' -ArgumentList 'bin/Debug/netcoreapp8.0/asp_main_service.dll'",
            "Write-Host 'Start Sleep'",
            "Start-Sleep -Seconds 30",
            "wget -O nodejs.zip https://nodejs.org/dist/v20.16.0/node-v20.16.0-win-x64.zip",
            "Expand-Archive -Path .\\nodejs.zip -DestinationPath .\\nodejs -Force",
            "$currentdir = Get-Location",
            "Write-Host $currentdir",
            "$env:Path += ';$currentdir\\nodejs\\node-v20.16.0-win-x64'",

            "# Bring in the traffic generator files to EC2 Instance",
            "aws s3 cp 's3://aws-appsignals-sample-app-prod-${var.aws_region}/traffic-generator.zip' './traffic-generator.zip'",
            "Expand-Archive -Path './traffic-generator.zip' -DestinationPath './' -Force",

            "# Install the traffic generator dependencies",
            "npm install",

            "# Start traffic generator",
            "$env:MAIN_ENDPOINT = 'localhost:8080'",
            "$env:REMOTE_ENDPOINT = '${aws_instance.remote_service_instance.private_ip}'",
            "$env:ID = '${var.test_id}'",

            "Start-Process -FilePath 'npm' -ArgumentList 'start'",
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
            "aws s3 cp s3://aws-appsignals-sample-app-prod-${var.aws_region}/amazon-cloudwatch-agent.json ./amazon-cloudwatch-agent.json",
            "powershell -Command \"(Get-Content -Path 'amazon-cloudwatch-agent.json') -replace 'REGION', 'us-east-1' | Set-Content -Path 'amazon-cloudwatch-agent.json'\"",
            "$ProgressPreference = 'SilentlyContinue'",
            "wget -O dotnet-install.ps1 https://dot.net/v1/dotnet-install.ps1",
            ".\\dotnet-install.ps1 -Version 8.0.302",
            "Invoke-Expression '${var.get_cw_agent_msi_command}'",
            "Write-Host 'Installing Cloudwatch Agent'",
            "msiexec /i amazon-cloudwatch-agent.msi",
            "$timeout = 30",
            "$interval = 5",
            "$call_cloudwatch = & 'C:\\Program Files\\Amazon\\AmazonCloudWatchAgent\\amazon-cloudwatch-agent-ctl.ps1'",
            "$elapsedTime = 0",
            "while ($elapsedTime -lt $timeout) {",
            "    if ($call_cloudwatch) {",
            "        Start-Sleep -Seconds $interval",
            "        Write-Host 'Install Finished'",
            "        break",
            "    } else {",
            "        $call_cloudwatch = & 'C:\\Program Files\\Amazon\\AmazonCloudWatchAgent\\amazon-cloudwatch-agent-ctl.ps1'",
            "        Write-Host 'Cloudwatch Agent not found. Checking again in $interval seconds...'",
            "        Start-Sleep -Seconds $interval",
            "        $elapsedTime += $interval",
            "    }",
            "}",
            "if ($elapsedTime -ge $timeout) {",
            "    Write-Host 'CloudWatch not found after $timeout seconds.'",
            "}",
            "& 'C:\\Program Files\\Amazon\\AmazonCloudWatchAgent\\amazon-cloudwatch-agent-ctl.ps1' -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json",
            "Invoke-Expression '${var.get_adot_distro_command}'",
            "Invoke-Expression '${var.sample_app_zip}'",
            "Expand-Archive -Path .\\dotnet-sample-app.zip -DestinationPath .\\ -Force",
            "New-NetFirewallRule -DisplayName 'Allow TCP 8081' -Direction Inbound -Protocol TCP -LocalPort 8081 -Action Allow",
            "$current_dir = Get-Location",
            "Write-Host $current_dir",
            "Set-Location -Path './asp_remote_service'",
            "$env:CORECLR_ENABLE_PROFILING = '1'",
            "$env:CORECLR_PROFILER = '{918728DD-259F-4A6A-AC2B-B85E1B658318}'",
            "$env:CORECLR_PROFILER_PATH = '$current_dir\\dotnet-distro\\win-x64\\OpenTelemetry.AutoInstrumentation.Native.dll'",
            "$env:DOTNET_ADDITIONAL_DEPS = '$current_dir\\dotnet-distro\\AdditionalDeps'",
            "$env:DOTNET_SHARED_STORE = '$current_dir\\dotnet-distro\\store'",
            "$env:DOTNET_STARTUP_HOOKS = '$current_dir\\dotnet-distro\\net\\OpenTelemetry.AutoInstrumentation.StartupHook.dll'",
            "$env:OTEL_DOTNET_AUTO_HOME = '$current_dir\\dotnet-distro'",
            "$env:OTEL_DOTNET_AUTO_PLUGINS = 'AWS.Distro.OpenTelemetry.AutoInstrumentation.Plugin, AWS.Distro.OpenTelemetry.AutoInstrumentation'",
            "$env:OTEL_EXPORTER_OTLP_PROTOCOL = 'http/protobuf'",
            "$env:OTEL_EXPORTER_OTLP_ENDPOINT = 'http://127.0.0.1:4316'",
            "$env:OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT = 'http://127.0.0.1:4316/v1/metrics'",
            "$env:OTEL_METRICS_EXPORTER = 'none'",
            "$env:OTEL_RESOURCE_ATTRIBUTES = 'service.name=dotnet-sample-remote-application-${var.test_id}'",
            "$env:OTEL_AWS_APPLICATION_SIGNALS_ENABLED = 'true'",
            "$env:OTEL_TRACES_SAMPLER = 'always_on'",
            "$env:ASPNETCORE_URLS = 'http://0.0.0.0:8081'",
            "dotnet build",
            "Start-Process -FilePath 'dotnet' -ArgumentList 'bin/Debug/netcoreapp8.0/asp_remote_service.dll'",
            "Write-Host 'Start Sleep'",
            "Start-Sleep -Seconds 30",
            "Write-Host 'Exiting'"
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
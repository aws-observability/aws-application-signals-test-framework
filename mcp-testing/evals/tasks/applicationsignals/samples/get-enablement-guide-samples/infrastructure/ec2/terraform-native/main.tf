# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  user_data = var.windows_type == "framework" ? local.framework_user_data : local.aspnetcore_user_data
  
  framework_user_data = <<-EOF
<powershell>
Start-Transcript -Path "C:\deployment.log" -Append
Write-Host "Starting application deployment..."

# Install AWS CLI
Write-Host "Installing AWS CLI..."
Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile "C:\AWSCLIV2.msi"
Start-Process msiexec.exe -Wait -ArgumentList "/i C:\AWSCLIV2.msi /quiet"
Remove-Item "C:\AWSCLIV2.msi"

# Install .NET SDK
Write-Host "Installing .NET SDK..."
Invoke-WebRequest -Uri "https://dot.net/v1/dotnet-install.ps1" -OutFile "dotnet-install.ps1"
powershell -ExecutionPolicy Bypass -File dotnet-install.ps1 -Channel 9.0 -InstallDir "C:\Program Files\dotnet"
Remove-Item "dotnet-install.ps1"

# Install NuGet CLI
Write-Host "Installing NuGet CLI..."
Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile "C:\nuget.exe"

# Install .NET Framework 4.8 Developer Pack
Write-Host "Installing .NET Framework 4.8 Developer Pack..."
Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=2088517" -OutFile "C:\ndp48-devpack-enu.exe"
Start-Process "C:\ndp48-devpack-enu.exe" -ArgumentList "/quiet" -Wait
Remove-Item "C:\ndp48-devpack-enu.exe"
Write-Host ".NET Framework 4.8 Developer Pack installed"

# Install IIS and ASP.NET features
Write-Host "Installing IIS and ASP.NET features..."
Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServer -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-CommonHttpFeatures -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpErrors -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpRedirect -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-ApplicationDevelopment -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-NetFxExtensibility45 -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-HealthAndDiagnostics -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpLogging -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-Security -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-RequestFiltering -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-Performance -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerManagementTools -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-ManagementConsole -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-IIS6ManagementCompatibility -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-Metabase -All
Enable-WindowsOptionalFeature -Online -FeatureName IIS-ASPNET45 -All

# Refresh PATH environment variable
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User") + ";C:\Program Files\dotnet"
Write-Host "All installations complete, PATH updated"

# Create application directory
New-Item -ItemType Directory -Force -Path C:\app
Set-Location C:\app

# Download application from S3
Write-Host "Downloading application from s3://${var.s3_bucket_name}/${var.s3_object_key}"
aws s3 cp s3://${var.s3_bucket_name}/${var.s3_object_key} C:\app\app.zip

# Extract application
Write-Host "Extracting application..."
Expand-Archive -Path C:\app\app.zip -DestinationPath C:\app -Force

# Set environment variables
[Environment]::SetEnvironmentVariable("PORT", "${var.port}", "Process")
[Environment]::SetEnvironmentVariable("AWS_REGION", "${var.aws_region}", "Process")

# Start .NET Framework application
Write-Host "Starting .NET Framework application..."
Import-Module WebAdministration

# Build the application first
Write-Host "Building .NET Framework application..."
Set-Location "C:\app"

# Install NuGet packages directly
Write-Host "Installing NuGet packages..."
C:\nuget.exe install packages.config -OutputDirectory packages

# Build the application
Write-Host "Building application with MSBuild..."
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe FrameworkApp.csproj /p:Configuration=Release /p:Platform="Any CPU" /p:OutputPath=bin\

# Ensure IIS is running
Start-Service W3SVC

# Copy application to IIS wwwroot
Copy-Item -Path "C:\app\*" -Destination "C:\inetpub\wwwroot" -Recurse -Force

# Configure IIS port
if ($env:PORT -and $env:PORT -ne "80") {
    Remove-WebBinding -Name "Default Web Site" -Port 80 -ErrorAction SilentlyContinue
    New-WebBinding -Name "Default Web Site" -Port $env:PORT -Protocol http
    Write-Host "IIS configured to use port $env:PORT"
}

# Create application pool if it doesn't exist
if (!(Get-IISAppPool -Name "DefaultAppPool" -ErrorAction SilentlyContinue)) {
    New-WebAppPool -Name "DefaultAppPool"
}

# Start the application pool
Start-WebAppPool -Name "DefaultAppPool"

Write-Host "IIS application deployed and started"

# Wait for application to start
Start-Sleep -Seconds 10

# Start traffic generator
Write-Host "Starting traffic generator..."
Start-Process powershell -ArgumentList "-File C:\app\generate-traffic.ps1" -WindowStyle Hidden

Write-Host "Application deployed and traffic generation started"
</powershell>
EOF

  aspnetcore_user_data = <<-EOF
<powershell>
Start-Transcript -Path "C:\deployment.log" -Append
Write-Host "Starting application deployment..."

# Install AWS CLI
Write-Host "Installing AWS CLI..."
Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile "C:\AWSCLIV2.msi"
Start-Process msiexec.exe -Wait -ArgumentList "/i C:\AWSCLIV2.msi /quiet"
Remove-Item "C:\AWSCLIV2.msi"

# Install .NET SDK
Write-Host "Installing .NET SDK..."
Invoke-WebRequest -Uri "https://dot.net/v1/dotnet-install.ps1" -OutFile "dotnet-install.ps1"
powershell -ExecutionPolicy Bypass -File dotnet-install.ps1 -Channel 9.0 -InstallDir "C:\Program Files\dotnet"
Remove-Item "dotnet-install.ps1"

# Refresh PATH environment variable
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User") + ";C:\Program Files\dotnet"
Write-Host "All installations complete, PATH updated"

# Create application directory
New-Item -ItemType Directory -Force -Path C:\app
Set-Location C:\app

# Download application from S3
Write-Host "Downloading application from s3://${var.s3_bucket_name}/${var.s3_object_key}"
aws s3 cp s3://${var.s3_bucket_name}/${var.s3_object_key} C:\app\app.zip

# Extract application
Write-Host "Extracting application..."
Expand-Archive -Path C:\app\app.zip -DestinationPath C:\app -Force

# Set environment variables
[Environment]::SetEnvironmentVariable("PORT", "${var.port}", "Process")
[Environment]::SetEnvironmentVariable("AWS_REGION", "${var.aws_region}", "Process")

# Start .NET Core/ASP.NET Core application
Write-Host "Starting ASP.NET Core application..."
if (Test-Path "C:\app\*.csproj") {
    Write-Host "Building ASP.NET Core application..."
    dotnet build --configuration Release
    Write-Host "Starting ASP.NET Core application..."
    $process = Start-Process -FilePath "dotnet" -ArgumentList "run --configuration Release" -WorkingDirectory "C:\app" -PassThru -WindowStyle Hidden
    Write-Host "Application started with PID: $($process.Id)"
} else {
    Write-Error "No .NET project file found"
    exit 1
}

# Wait for application to start
Start-Sleep -Seconds 10

# Start traffic generator
Write-Host "Starting traffic generator..."
Start-Process powershell -ArgumentList "-File C:\app\generate-traffic.ps1" -WindowStyle Hidden

Write-Host "Application deployed and traffic generation started"
</powershell>
EOF
}

# Data sources
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM role for EC2
resource "aws_iam_role" "app_role" {
  name = "${var.app_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_readonly" {
  role       = aws_iam_role.app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app_profile" {
  name = "${var.app_name}-profile"
  role = aws_iam_role.app_role.name
}

# Security group
resource "aws_security_group" "app_sg" {
  name        = "${var.app_name}-sg"
  description = "Security group for ${var.app_name}"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow inbound traffic on port ${var.port}"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.app_name}-sg"
  }
}

# EC2 instance
resource "aws_instance" "app_instance" {
  ami                    = data.aws_ami.windows.id
  instance_type          = "t3.medium"
  iam_instance_profile   = aws_iam_instance_profile.app_profile.name
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  subnet_id              = data.aws_subnets.public.ids[0]

  user_data = local.user_data

  tags = {
    Name = "${var.app_name}-instance"
  }
}
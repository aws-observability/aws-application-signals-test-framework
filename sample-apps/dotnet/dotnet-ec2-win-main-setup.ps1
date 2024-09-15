param (
    [string]$GetCloudwatchAgentCommand,
    [string]$GetAdotDistroCommand,
    [string]$GetSampleAppCommand,
    [string]$TestId,
    [string]$RemoteServicePrivateEndpoint,
    [string]$AWSRegion
)

# This file is used to deploy and instrumentation main sample app for Dotnet E2E Canary test
# This is the most stable way to do that in automatically test workflow invloving EC2 and SSM

# To avoid written UI for download and extract zip step, saving lots of time
$ProgressPreference = 'SilentlyContinue'

# Install Dotnet
wget -O dotnet-install.ps1 https://dot.net/v1/dotnet-install.ps1
.\dotnet-install.ps1 -Version 8.0.302

# Install and start Cloudwatch Agent
Invoke-Expression $GetCloudwatchAgentCommand

Write-Host "Installing Cloudwatch Agent"
msiexec /i amazon-cloudwatch-agent.msi
$timeout = 30
$interval = 5
$call_cloudwatch = & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1"
$elapsedTime = 0

while ($elapsedTime -lt $timeout) {
    if ($call_cloudwatch) {
        Start-Sleep -Seconds $interval
        Write-Host "Install Finished"
        break
    } else {
        Write-Host "Cloudwatch Agent not found: $filePath. Checking again in $interval seconds..."
        Start-Sleep -Seconds $interval
        $elapsedTime += $interval
    }
}

if ($elapsedTime -ge $timeout) {
    Write-Host "CloudWatch not found after $timeout seconds."
}

Write-Host "Install Finished"

# Even after this step, it only expose 8080 to localhost and local (EC2) network on current config, so it's safe
# Leave it here for Debug purpose
New-NetFirewallRule -DisplayName "Allow TCP 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow

& "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json

# Get Instrumentation Artifacts and Sample App
Invoke-Expression $GetAdotDistroCommand

Invoke-Expression $GetSampleAppCommand

Expand-Archive -Path .\dotnet-sample-app.zip -DestinationPath .\ -Force

# Config Env variable for Windows EC2

$current_dir = Get-Location
Write-Host $current_dir

Set-Location -Path "./asp_frontend_service"
$env:CORECLR_ENABLE_PROFILING = "1"
$env:CORECLR_PROFILER = "{918728DD-259F-4A6A-AC2B-B85E1B658318}"
$env:CORECLR_PROFILER_PATH = "$current_dir\dotnet-distro\win-x64\OpenTelemetry.AutoInstrumentation.Native.dll"
$env:DOTNET_ADDITIONAL_DEPS = "$current_dir\dotnet-distro\AdditionalDeps"
$env:DOTNET_SHARED_STORE = "$current_dir\dotnet-distro\store"
$env:DOTNET_STARTUP_HOOKS = "$current_dir\dotnet-distro\net\OpenTelemetry.AutoInstrumentation.StartupHook.dll"
$env:OTEL_DOTNET_AUTO_HOME = "$current_dir\dotnet-distro"
$env:OTEL_DOTNET_AUTO_PLUGINS = "AWS.Distro.OpenTelemetry.AutoInstrumentation.Plugin, AWS.Distro.OpenTelemetry.AutoInstrumentation"
$env:OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
$env:OTEL_EXPORTER_OTLP_ENDPOINT = "http://127.0.0.1:4316"
$env:OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT = "http://127.0.0.1:4316/v1/metrics"
$env:OTEL_METRICS_EXPORTER = "none"
$env:OTEL_RESOURCE_ATTRIBUTES = "service.name=dotnet-sample-application-$TestId"
$env:OTEL_AWS_APPLICATION_SIGNALS_ENABLED = "true"
$env:OTEL_TRACES_SAMPLER = "always_on"
$env:ASPNETCORE_URLS = "http://0.0.0.0:8080"


dotnet build


Start-Process -FilePath "dotnet" -ArgumentList "bin/Debug/netcoreapp8.0/asp_frontend_service.dll"

Write-Host "Start Sleep"
Start-Sleep -Seconds 10

# Deploy Traffic Generator

# Install node and setup path for node
wget -O nodejs.zip https://nodejs.org/dist/v20.16.0/node-v20.16.0-win-x64.zip
Expand-Archive -Path .\nodejs.zip -DestinationPath .\nodejs -Force
$currentdir = Get-Location
Write-Host $currentdir
$env:Path += ";$currentdir" + "\nodejs\node-v20.16.0-win-x64"

# Bring in the traffic generator files to EC2 Instance
aws s3 cp "s3://aws-appsignals-sample-app-prod-$AWSRegion/traffic-generator.zip" "./traffic-generator.zip"
Expand-Archive -Path "./traffic-generator.zip" -DestinationPath "./" -Force

# Install the traffic generator dependencies
npm install

# Start traffic generator
$env:MAIN_ENDPOINT = "localhost:8080"
$env:REMOTE_ENDPOINT = $RemoteServicePrivateEndpoint
$env:ID = $TestId

Start-Process -FilePath "npm" -ArgumentList "start"

Write-Host "Exiting"
exit
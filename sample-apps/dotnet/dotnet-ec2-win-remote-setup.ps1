param (
    [string]$GetCloudwatchAgentCommand,
    [string]$GetAdotDistroCommand,
    [string]$GetSampleAppCommand,
    [string]$TestId
)

# This file is used to deploy and instrumentation remote sample app for Dotnet E2E Canary test
# This is the most stable way to do that in automatically test workflow invloving EC2 and SSM

# To avoid written UI for download and extract zip step, saving lots of time
$ProgressPreference = 'SilentlyContinue'

# Install Dotnet
Write-Host "Installing Dotnet" | %{ "{0:HH:mm:ss:fff}: {1}" -f (Get-Date), $_ }
curl.exe -L -o dotnet-install.ps1 https://dot.net/v1/dotnet-install.ps1 --retry 5 --retry-all-errors --retry-delay 5
.\dotnet-install.ps1 -Version 8.0.302

# Install and start Cloudwatch Agent
Invoke-Expression $GetCloudwatchAgentCommand | %{ "{0:HH:mm:ss:fff}: {1}" -f (Get-Date), $_ }

Write-Host "Installing Cloudwatch Agent" | %{ "{0:HH:mm:ss:fff}: {1}" -f (Get-Date), $_ }
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
        $call_cloudwatch = & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1"
        Write-Host "Cloudwatch Agent not found: $filePath. Checking again in $interval seconds..."
        Start-Sleep -Seconds $interval
        $elapsedTime += $interval
    }
}

if ($elapsedTime -ge $timeout) {
    Write-Host "CloudWatch not found after $timeout seconds."
}

& "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json

# Get Instrumentation Artifacts and Sample App
Invoke-Expression $GetAdotDistroCommand | %{ "{0:HH:mm:ss:fff}: {1}" -f (Get-Date), $_ }

Invoke-Expression $GetSampleAppCommand | %{ "{0:HH:mm:ss:fff}: {1}" -f (Get-Date), $_ }

Expand-Archive -Path .\dotnet-sample-app.zip -DestinationPath .\ -Force | %{ "{0:HH:mm:ss:fff}: {1}" -f (Get-Date), $_ }

# Allow income traffic from main-service
New-NetFirewallRule -DisplayName "Allow TCP 8081" -Direction Inbound -Protocol TCP -LocalPort 8081 -Action Allow | %{ "{0:HH:mm:ss:fff}: {1}" -f (Get-Date), $_ }

$current_dir = Get-Location
Write-Host $current_dir

# Config Env variable for Windows EC2
Set-Location -Path "./asp_remote_service"
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
$env:OTEL_RESOURCE_ATTRIBUTES = "service.name=dotnet-sample-remote-application-$TestId"
$env:OTEL_AWS_APPLICATION_SIGNALS_ENABLED = "true"
$env:OTEL_TRACES_SAMPLER = "always_on"
$env:ASPNETCORE_URLS = "http://0.0.0.0:8081"


dotnet build | %{ "{0:HH:mm:ss:fff}: {1}" -f (Get-Date), $_ }


Start-Process -FilePath "dotnet" -ArgumentList "bin/Debug/netcoreapp8.0/asp_remote_service.dll"


Write-Host "Start Sleep"
Start-Sleep -Seconds 30
Write-Host "Exiting"
exit
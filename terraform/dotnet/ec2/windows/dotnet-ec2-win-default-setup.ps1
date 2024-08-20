param (
    [string]$GetCloudwatchAgentCommand,
    [string]$GetAdotDistroCommand,
    [string]$GetSampleAppCommand,
    [string]$TestId
)


msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
wget -O dotnet-install.ps1 https://dot.net/v1/dotnet-install.ps1
.\dotnet-install.ps1 -Version 8.0.302

Invoke-Expression $GetCloudwatchAgentCommand
#wget -O .\amazon-cloudwatch-agent.msi https://amazoncloudwatch-agent.s3.amazonaws.com/windows/amd64/latest/amazon-cloudwatch-agent.msi

Write-Host "Installing Cloudwatch Agent"
msiexec /i amazon-cloudwatch-agent.msi
Start-Sleep -Seconds 10
Write-Host "Install Finished"

# Debug
New-NetFirewallRule -DisplayName "Allow TCP 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow

& "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json

Invoke-Expression $GetAdotDistroCommand
#Invoke-Expression "wget -O ./aws-distro-opentelemetry-dotnet-instrumentation-windows.zip https://github.com/aws-observability/aws-otel-dotnet-instrumentation/releases/download/v1.1.0/aws-distro-opentelemetry-dotnet-instrumentation-windows.zip; Expand-Archive -Path ./aws-distro-opentelemetry-dotnet-instrumentation-windows.zip -DestinationPath .\dotnet-distro -Force"

Invoke-Expression $GetSampleAppCommand
#wget -O ./dotnet-sample-app.zip https://github.com/aws-observability/aws-application-signals-test-framework/raw/dotnetE2ETests/sample-apps/dotnet/dotnet-sample-app.zip

Expand-Archive -Path .\dotnet-sample-app.zip -DestinationPath .\ -Force

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
Start-Sleep -Seconds 30
Write-Host "Exiting"
exit
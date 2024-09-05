param (
    [string]$RemoteServicePrivateEndpoint,
    [string]$TestID,
    [string]$TestCanaryType,
    [string]$AWSRegion
)

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


$env:MAIN_ENDPOINT = "localhost:8080"
$env:REMOTE_ENDPOINT = $RemoteServicePrivateEndpoint
$env:ID = $TestID
$env:CANARY_TYPE = $TestCanaryType

Start-Process -FilePath "npm" -ArgumentList "start"

exit
param (
    [string]$RemoteServicePrivateEndpoint,
    [string]$TestID,
    [string]$TestCanaryType
)

wget -O nodejs.zip https://nodejs.org/dist/v20.16.0/node-v20.16.0-win-x64.zip
Expand-Archive -Path .\nodejs.zip -DestinationPath .\nodejs -Force
$currentdir = Get-Location
Write-Host $currentdir
$env:Path += ";$currentdir" + "\nodejs\node-v20.16.0-win-x64"

# Bring in the traffic generator files to EC2 Instance
#aws s3 cp "s3://aws-appsignals-sample-app-prod-${var.aws_region}/traffic-generator.zip" "./traffic-generator.zip"
wget -o traffic-generator.zip https://raw.githubusercontent.com/aws-observability/aws-application-signals-test-framework/dotnetMergeBranch-windows/terraform/dotnet/ec2/windows/traffic-generator.zip
Expand-Archive -Path "./traffic-generator.zip" -DestinationPath "./" -Force

# Install the traffic generator dependencies
npm install


$env:MAIN_ENDPOINT = "localhost:8080"
$env:REMOTE_ENDPOINT = $RemoteServicePrivateEndpoint
$env:ID = $TestID
$env:CANARY_TYPE = $TestCanaryType

Start-Process -FilePath "npm" -ArgumentList "start" -NoNewWindow -PassThru
# Start the script in a background job
# Start-Job -ScriptBlock $ScriptBlock -ArgumentList $MainEndpoint, $RemoteEndpoint, $Id, $CanaryType,
# $currentdir -NoNewWindow -PassThru
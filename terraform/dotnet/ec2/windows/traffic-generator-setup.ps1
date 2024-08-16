param (
    [string]$RemoteServicePrivateEndpoint,
    [string]$TestID,
    [string]$TestCanaryType
)

wget -O nodejs.zip https://nodejs.org/dist/v20.16.0/node-v20.16.0-win-x64.zip
Expand-Archive -Path .\nodejs.zip -DestinationPath .\nodejs
$env:Path += ";$nodejsdir" + "\nodejs\node-v20.16.0-win-x64"

# Bring in the traffic generator files to EC2 Instance
#aws s3 cp "s3://aws-appsignals-sample-app-prod-${var.aws_region}/traffic-generator.zip" "./traffic-generator.zip"
wget -o traffic-generator.zip https://raw.githubusercontent
.com/aws-observability/aws-application-signals-test-framework/dotnetMergeBranch-windows/terraform/dotnet/ec2/windows/traffic-generator.zip
Expand-Archive -Path "./traffic-generator.zip" -DestinationPath "./"

# Install the traffic generator dependencies
npm install

# Start a new tmux-like session in PowerShell (Using Start-Job or Runspace for background process)
$MainEndpoint = "localhost:8080"
$RemoteEndpoint = $RemoteServicePrivateEndpoint
$Id = $TestID
$CanaryType = $TestCanaryType

$ScriptBlock = {
    param($MainEndpoint, $RemoteEndpoint, $Id, $CanaryType)

    # Set environment variables
    $env:MAIN_ENDPOINT = $MainEndpoint
    $env:REMOTE_ENDPOINT = $RemoteEndpoint
    $env:ID = $Id
    $env:CANARY_TYPE = $CanaryType

    # Start the application
    npm start
}

# Start the script in a background job
Start-Job -ScriptBlock $ScriptBlock -ArgumentList $MainEndpoint, $RemoteEndpoint, $Id, $CanaryType
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export interface AppConfig {
  appName: string;
  s3BucketName: string;
  s3ObjectKey: string;
  language: string;
  port: number;
  healthCheckPath: string;
  windowsType?: 'framework' | 'aspnetcore';
}

export class EC2NativeWindowsAppStack extends cdk.Stack {
  constructor(scope: Construct, id: string, config: AppConfig, props?: cdk.StackProps) {
    super(scope, id, props);

    // Use default VPC
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVPC', {
      isDefault: true,
    });

    // IAM role for EC2 with S3 read permissions and SSM access
    const role = new iam.Role(this, 'AppRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3ReadOnlyAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // Security group
    const securityGroup = new ec2.SecurityGroup(this, 'AppSG', {
      vpc,
      description: `Security group for ${config.appName}`,
      allowAllOutbound: true,
    });

    // Allow inbound traffic on application port
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(config.port),
      `Allow inbound traffic on port ${config.port}`
    );

    // User data to download and run Windows application
    const userData = ec2.UserData.forWindows();
    userData.addCommands(
      '# PowerShell script to download and run application',
      'Start-Transcript -Path "C:\\deployment.log" -Append',
      'Write-Host "Starting application deployment..."',
      '',
      '# Install AWS CLI',
      'Write-Host "Installing AWS CLI..."',
      'Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile "C:\\AWSCLIV2.msi"',
      'Start-Process msiexec.exe -Wait -ArgumentList "/i C:\\AWSCLIV2.msi /quiet"',
      'Remove-Item "C:\\AWSCLIV2.msi"',
      '',
      '# Install .NET SDK',
      'Write-Host "Installing .NET SDK..."',
      'Invoke-WebRequest -Uri "https://dot.net/v1/dotnet-install.ps1" -OutFile "dotnet-install.ps1"',
      'powershell -ExecutionPolicy Bypass -File dotnet-install.ps1 -Channel 9.0 -InstallDir "C:\\Program Files\\dotnet"',
      'Remove-Item "dotnet-install.ps1"',
      '',
      ...(config.windowsType === 'framework' ? [
        '# Install NuGet CLI',
        'Write-Host "Installing NuGet CLI..."',
        'Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile "C:\\nuget.exe"',
        '',
        '# Install .NET Framework 4.8 Developer Pack',
        'Write-Host "Installing .NET Framework 4.8 Developer Pack..."',
        'Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=2088517" -OutFile "C:\\ndp48-devpack-enu.exe"',
        'Start-Process "C:\\ndp48-devpack-enu.exe" -ArgumentList "/quiet" -Wait',
        'Remove-Item "C:\\ndp48-devpack-enu.exe"',
        'Write-Host ".NET Framework 4.8 Developer Pack installed"',
      ] : []),
      '',
      '# Install IIS and ASP.NET features',
      'Write-Host "Installing IIS and ASP.NET features..."',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServer -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-CommonHttpFeatures -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpErrors -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpRedirect -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-ApplicationDevelopment -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-NetFxExtensibility45 -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-HealthAndDiagnostics -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpLogging -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-Security -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-RequestFiltering -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-Performance -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerManagementTools -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-ManagementConsole -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-IIS6ManagementCompatibility -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-Metabase -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-ASPNET45 -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-NetFxExtensibility -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-ISAPIExtensions -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-ISAPIFilter -All',
      'Enable-WindowsOptionalFeature -Online -FeatureName IIS-ManagementService -All',
      '',
      '# Refresh PATH environment variable for all installed tools',
      '$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User") + ";C:\\Program Files\\dotnet"',
      'Write-Host "All installations complete, PATH updated"',
      '',
      '# Create application directory',
      'New-Item -ItemType Directory -Force -Path C:\\app',
      'Set-Location C:\\app',
      '',
      '# Download application from S3',
      `Write-Host "Downloading application from s3://${config.s3BucketName}/${config.s3ObjectKey}"`,
      `aws s3 cp s3://${config.s3BucketName}/${config.s3ObjectKey} C:\\app\\app.zip`,
      '',
      '# Extract application',
      'Write-Host "Extracting application..."',
      'Expand-Archive -Path C:\\app\\app.zip -DestinationPath C:\\app -Force',
      '',
      '# Set environment variables',
      `[Environment]::SetEnvironmentVariable("PORT", "${config.port}", "Process")`,
      `[Environment]::SetEnvironmentVariable("AWS_REGION", "${this.region}", "Process")`,
      '',
      '# Wait for IIS features to be fully installed',
      'Start-Sleep -Seconds 30',
      'Import-Module WebAdministration -Force',
      '',
      ...(config.windowsType === 'framework' ? [
        '# Build .NET Framework application',
        'Write-Host "Building .NET Framework application..."',
        'Set-Location "C:\\app"',
        'C:\\nuget.exe install packages.config -OutputDirectory packages',
        'C:\\Windows\\Microsoft.NET\\Framework64\\v4.0.30319\\MSBuild.exe FrameworkApp.csproj /p:Configuration=Release /p:Platform="Any CPU" /p:OutputPath=bin\\\\',
        'Copy-Item -Path "C:\\app\\*" -Destination "C:\\inetpub\\wwwroot" -Recurse -Force',
      ] : [
        '# Install ASP.NET Core Hosting Bundle',
        'Write-Host "Installing ASP.NET Core Hosting Bundle..."',
        'Invoke-WebRequest -Uri "https://dotnetcli.azureedge.net/dotnet/aspnetcore/Runtime/9.0.0/dotnet-hosting-9.0.0-win.exe" -OutFile "C:\\dotnet-hosting.exe"',
        'Start-Process "C:\\dotnet-hosting.exe" -ArgumentList "/quiet" -Wait',
        'Remove-Item "C:\\dotnet-hosting.exe"',
        '',
        '# Build and publish ASP.NET Core application',
        'Write-Host "Building ASP.NET Core application..."',
        'Set-Location "C:\\app"',
        'dotnet publish --configuration Release --output "C:\\inetpub\\wwwroot"',
      ]),
      '',
      '# Start IIS and configure',
      'Start-Service W3SVC',
      '',
      '# Configure IIS port',
      'if ($env:PORT -and $env:PORT -ne "80") {',
      '    Remove-WebBinding -Name "Default Web Site" -Port 80 -ErrorAction SilentlyContinue',
      '    New-WebBinding -Name "Default Web Site" -Port $env:PORT -Protocol http',
      '    Write-Host "IIS configured to use port $env:PORT"',
      '}',
      '',
      '# Configure application pool',
      'if (Get-IISAppPool -Name "DefaultAppPool" -ErrorAction SilentlyContinue) {',
      '    Remove-WebAppPool -Name "DefaultAppPool"',
      '}',
      'New-WebAppPool -Name "DefaultAppPool"',
      'Set-ItemProperty -Path "IIS:\\AppPools\\DefaultAppPool" -Name "processModel.identityType" -Value "ApplicationPoolIdentity"',
      ...(config.windowsType !== 'framework' ? [
        'Set-ItemProperty -Path "IIS:\\AppPools\\DefaultAppPool" -Name "managedRuntimeVersion" -Value ""',
        'iisreset',
      ] : []),
      'Start-WebAppPool -Name "DefaultAppPool"',
      '',
      'Write-Host "Application deployed and started"',
      '',
      '# Wait for application to start',
      'Start-Sleep -Seconds 10',
      '',
      '# Start traffic generator',
      'Write-Host "Starting traffic generator..."',
      'Start-Process powershell -ArgumentList "-File C:\\app\\generate-traffic.ps1" -WindowStyle Hidden -RedirectStandardOutput "C:\\app\\traffic-generator.log" -RedirectStandardError "C:\\app\\traffic-generator-error.log"',
      '',
      'Write-Host "Application deployed and traffic generation started"'
    );

    // EC2 instance with Windows AMI
    const instance = new ec2.Instance(this, 'AppInstance', {
      vpc,
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.T3,
        ec2.InstanceSize.MEDIUM // Windows needs more resources
      ),
      machineImage: ec2.MachineImage.latestWindows(ec2.WindowsVersion.WINDOWS_SERVER_2022_ENGLISH_FULL_BASE),
      role,
      securityGroup,
      userData,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
    });

    // Outputs
    new cdk.CfnOutput(this, 'InstanceId', {
      value: instance.instanceId,
      description: 'EC2 Instance ID',
    });

    new cdk.CfnOutput(this, 'InstancePublicIP', {
      value: instance.instancePublicIp,
      description: 'EC2 Instance Public IP',
    });

    new cdk.CfnOutput(this, 'HealthCheckURL', {
      value: `http://${instance.instancePublicIp}:${config.port}${config.healthCheckPath}`,
      description: `${config.appName} Health Endpoint`,
    });

    new cdk.CfnOutput(this, 'BucketsAPIURL', {
      value: `http://${instance.instancePublicIp}:${config.port}/api/buckets`,
      description: `${config.appName} Buckets API Endpoint`,
    });

    new cdk.CfnOutput(this, 'S3Location', {
      value: `s3://${config.s3BucketName}/${config.s3ObjectKey}`,
      description: 'S3 location of application package',
    });

    new cdk.CfnOutput(this, 'Language', {
      value: config.language,
      description: 'Application language',
    });

    new cdk.CfnOutput(this, 'Platform', {
      value: 'windows',
      description: 'Application platform',
    });
  }


}
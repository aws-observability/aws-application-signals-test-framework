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

FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8-windowsservercore-ltsc2022

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# Install NuGet and restore packages
RUN Invoke-WebRequest -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile 'C:\nuget.exe'

WORKDIR /inetpub/wwwroot

# Copy project files
COPY FrameworkApp.csproj .
COPY packages.config .

# Restore NuGet packages
RUN C:\nuget.exe restore FrameworkApp.csproj -PackagesDirectory packages

# Copy application files
COPY . .

# Build the application
RUN C:\Windows\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe FrameworkApp.csproj /p:Configuration=Release /p:Platform="Any CPU" /p:OutputPath=bin\

# Install curl for health checks and traffic generation
RUN Invoke-WebRequest -Uri 'https://curl.se/windows/dl-8.4.0_6/curl-8.4.0_6-win64-mingw.zip' -OutFile 'curl.zip'; \
    Expand-Archive curl.zip -DestinationPath C:\; \
    Move-Item 'C:\curl-8.4.0_6-win64-mingw\bin\curl.exe' 'C:\Windows\System32\curl.exe'; \
    Remove-Item curl.zip, 'C:\curl-8.4.0_6-win64-mingw' -Recurse -Force

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health.aspx || exit 1

# Copy traffic generation script
COPY generate-traffic.ps1 C:\generate-traffic.ps1

CMD ["powershell", "-Command", "Start-Process powershell -ArgumentList '-File C:\\generate-traffic.ps1' -WindowStyle Hidden; C:\\ServiceMonitor.exe w3svc"]
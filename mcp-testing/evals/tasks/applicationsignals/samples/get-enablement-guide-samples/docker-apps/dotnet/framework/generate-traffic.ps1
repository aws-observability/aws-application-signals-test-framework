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

# Traffic generator script for .NET Framework application
$BaseUrl = "http://localhost"

Write-Host "Starting continuous traffic generation to $BaseUrl"

while ($true) {
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] Generating traffic..."

    try {
        # Health check
        $response = Invoke-WebRequest -Uri "$BaseUrl/health.aspx" -UseBasicParsing -TimeoutSec 5
        if ($response.StatusCode -ne 200) {
            Write-Host "[$timestamp] ERROR: Health check failed with status $($response.StatusCode)!"
        }
    }
    catch {
        Write-Host "[$timestamp] ERROR: Health check failed - $($_.Exception.Message)"
    }

    try {
        # API call (S3 buckets)
        $response = Invoke-WebRequest -Uri "$BaseUrl/api/buckets" -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -ne 200) {
            Write-Host "[$timestamp] ERROR: API call to /api/buckets failed with status $($response.StatusCode)!"
        }
    }
    catch {
        Write-Host "[$timestamp] ERROR: API call to /api/buckets failed - $($_.Exception.Message)"
    }

    # Sleep between requests
    Start-Sleep -Seconds 2
}
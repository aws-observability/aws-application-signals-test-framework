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

"""EC2 .NET enablement task configurations."""

from ..enablement_tasks import EnablementTask, ENABLEMENT_PROMPT


# Component rubrics - mix and match to build complete validation rubrics

# CloudWatch Agent component
CLOUDWATCH_AGENT_RUBRIC = [
    'IAM: CloudWatchAgentServerPolicy attached to EC2 instance role',
    'CloudWatch Agent: Installed (via yum/dnf install amazon-cloudwatch-agent or equivalent)',
    'CloudWatch Agent: Configuration file created with traces.traces_collected.application_signals',
    'CloudWatch Agent: Configuration file created with logs.metrics_collected.application_signals',
    'CloudWatch Agent: Started with amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s',
]

# ADOT .NET component
ADOT_DOTNET_RUBRIC = [
    'Dockerfile: ADOT .NET auto-instrumentation downloaded and installed via aws-otel-dotnet-install.sh',
]

# OpenTelemetry environment variables component for .NET
OTEL_ENV_VARS_RUBRIC = [
    'UserData docker run: -e OTEL_DOTNET_AUTO_HOME=/opt/otel-dotnet-auto (or equivalent path)',
    'UserData docker run: -e DOTNET_STARTUP_HOOKS=/opt/otel-dotnet-auto/net/OpenTelemetry.AutoInstrumentation.StartupHook.dll (or equivalent path)',
    'UserData docker run: -e DOTNET_SHARED_STORE=/opt/otel-dotnet-auto/store (or equivalent path)',
    'UserData docker run: -e DOTNET_ADDITIONAL_DEPS=/opt/otel-dotnet-auto/AdditionalDeps (or equivalent path)',
    'UserData docker run: -e OTEL_METRICS_EXPORTER=none',
    'UserData docker run: -e OTEL_LOGS_EXPORTER=none',
    'UserData docker run: -e OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true',
    'UserData docker run: -e OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf',
    'UserData docker run: -e OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT=http://localhost:4316/v1/metrics',
    'UserData docker run: -e OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:4316/v1/traces',
    'UserData docker run: -e OTEL_RESOURCE_ATTRIBUTES with service.name',
]

# Docker component
DOCKER_RUBRIC = [
    'UserData docker run: --network host flag present for CloudWatch Agent communication',
]

# Framework-agnostic .NET component
STANDARD_DOTNET_RUBRIC = [
    'Integrity: Application logic unchanged (.NET source files excluding configuration files)',
]

# Integrity checks (common across IaC tools)
INTEGRITY_RUBRIC = [
    'Integrity: Only infrastructure/config files modified (Dockerfile, IaC) - application logic unchanged',
    'Integrity: Existing docker run environment variables preserved (PORT, SERVICE_NAME, etc.)',
    'Integrity: UserData commands added in correct sequence: prerequisites -> CW Agent -> docker run',
]


# Task definitions - compose rubrics from components
EC2_DOTNET_DOCKER_TASKS = [
    # CDK - ASP.NET Core - Linux
    EnablementTask(
        id='ec2_dotnet_aspnetcore_docker_linux_cdk',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/ec2/cdk',
            'docker-apps/dotnet/aspnetcore',
        ],
        iac_dir='infrastructure/ec2/cdk',
        app_dir='docker-apps/dotnet/aspnetcore',
        language='dotnet',
        framework='aspnetcore',
        platform='ec2',
        build_command='npm install && npm run build',
        build_working_dir='infrastructure/ec2/cdk',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_DOTNET_RUBRIC +
            OTEL_ENV_VARS_RUBRIC +
            DOCKER_RUBRIC +
            STANDARD_DOTNET_RUBRIC +
            INTEGRITY_RUBRIC
        ),
    ),

    # Terraform - ASP.NET Core - Linux
    EnablementTask(
        id='ec2_dotnet_aspnetcore_docker_linux_terraform',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/ec2/terraform',
            'docker-apps/dotnet/aspnetcore',
        ],
        iac_dir='infrastructure/ec2/terraform',
        app_dir='docker-apps/dotnet/aspnetcore',
        language='dotnet',
        framework='aspnetcore',
        platform='ec2',
        build_command='terraform init && terraform validate',
        build_working_dir='infrastructure/ec2/terraform',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_DOTNET_RUBRIC +
            OTEL_ENV_VARS_RUBRIC +
            DOCKER_RUBRIC +
            STANDARD_DOTNET_RUBRIC +
            INTEGRITY_RUBRIC
        ),
    ),
]

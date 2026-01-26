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
    'CloudWatch Agent: Installed (by downloading amazon-cloudwatch-agent.msi or equivalent)',
    'CloudWatch Agent: Configuration file created with traces.traces_collected.application_signals',
    'CloudWatch Agent: Configuration file created with logs.metrics_collected.application_signals',
    'CloudWatch Agent: Started with amazon-cloudwatch-agent-ctl.ps1 -a fetch-config -m ec2 -s',
]

# ADOT .NET component
ADOT_DOTNET_RUBRIC = [
    'UserData: ADOT .NET auto-instrumentation downloaded and installed via AWS.Otel.DotNet.Auto.psm1',
    'UserData: ADOT .NET auto-instrumentation setup using Install-OpenTelemetryCore',
    'UserData: IIS server restarted to pickup auto instrumentation via Register-OpenTelemetryForIIS'
]

# OpenTelemetry environment variables component for .NET
OTEL_ENV_VARS_RUBRIC = [
    'UserData $env:OTEL_DOTNET_AUTO_HOME="C:\\Program Files\\AWS Distro for OpenTelemetry AutoInstrumentation" (or equivalent path)',
    'UserData $env:DOTNET_STARTUP_HOOKS=/net/OpenTelemetry.AutoInstrumentation.StartupHook.dll (or equivalent path)',
    'UserData $env:DOTNET_SHARED_STORE=/store (or equivalent path)',
    'UserData $env:DOTNET_ADDITIONAL_DEPS=/AdditionalDeps (or equivalent path)',
    'UserData $env:OTEL_METRICS_EXPORTER=none',
    'UserData $env:OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true',
    'UserData $env:OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf',
    'UserData $env:OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT=http://127.0.0.1:4316/v1/metrics',
    'UserData $env:OTEL_RESOURCE_ATTRIBUTES with service.name',
]

# Framework-agnostic .NET component
STANDARD_DOTNET_RUBRIC = [
    'Integrity: Application logic unchanged (.NET source files excluding configuration files)',
]

# Integrity checks (common across IaC tools)
INTEGRITY_RUBRIC = [
    'Integrity: Only infrastructure/config files modified (Dockerfile, IaC) - application logic unchanged',
    'Integrity: Existing application startup commands unchanged (PORT, SERVICE_NAME, etc.)',
    'Integrity: UserData commands added in correct sequence: prerequisites -> CW Agent -> application startup',
]


# Task definitions - compose rubrics from components
EC2_DOTNET_NATIVE_WINDOWS_TASKS = [
    # CDK - ASP.NET Core - Windows
    EnablementTask(
        id='ec2_dotnet_aspnetcore_native_windows_cdk',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/ec2/cdk-native-windows',
            'docker-apps/dotnet/aspnetcore',
        ],
        iac_dir='infrastructure/ec2/cdk-native-windows',
        app_dir='docker-apps/dotnet/aspnetcore',
        language='dotnet',
        framework='aspnetcore',
        platform='ec2',
        build_command='npm install && npm run build',
        build_working_dir='infrastructure/ec2/cdk-native-windows',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_DOTNET_RUBRIC +
            OTEL_ENV_VARS_RUBRIC +
            STANDARD_DOTNET_RUBRIC +
            INTEGRITY_RUBRIC
        ),
    ),

    # Terraform - ASP.NET Core - Windows
    EnablementTask(
        id='ec2_dotnet_aspnetcore_native_windows_terraform',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/ec2/terraform-native-windows',
            'docker-apps/dotnet/aspnetcore',
        ],
        iac_dir='infrastructure/ec2/terraform-native-windows',
        app_dir='docker-apps/dotnet/aspnetcore',
        language='dotnet',
        framework='aspnetcore',
        platform='ec2',
        build_command='terraform init && terraform validate',
        build_working_dir='infrastructure/ec2/terraform-native-windows',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_DOTNET_RUBRIC +
            OTEL_ENV_VARS_RUBRIC +
            STANDARD_DOTNET_RUBRIC +
            INTEGRITY_RUBRIC
        ),
    ),
    # CDK - .NET Framework - Windows
    EnablementTask(
        id='ec2_dotnet_framework_native_windows_cdk',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/ec2/cdk-native-windows',
            'docker-apps/dotnet/framework',
        ],
        iac_dir='infrastructure/ec2/cdk-native-windows',
        app_dir='docker-apps/dotnet/framework',
        language='dotnet',
        framework='framework',
        platform='ec2',
        build_command='npm install && npm run build',
        build_working_dir='infrastructure/ec2/cdk-native-windows',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_DOTNET_RUBRIC +
            OTEL_ENV_VARS_RUBRIC +
            STANDARD_DOTNET_RUBRIC +
            INTEGRITY_RUBRIC
        ),
    ),

    # Terraform - .NET Framework - Windows
    EnablementTask(
        id='ec2_dotnet_framework_native_windows_terraform',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/ec2/terraform-native-windows',
            'docker-apps/dotnet/framework',
        ],
        iac_dir='infrastructure/ec2/terraform-native-windows',
        app_dir='docker-apps/dotnet/framework',
        language='dotnet',
        framework='framework',
        platform='ec2',
        build_command='terraform init && terraform validate',
        build_working_dir='infrastructure/ec2/terraform-native-windows',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_DOTNET_RUBRIC +
            OTEL_ENV_VARS_RUBRIC +
            STANDARD_DOTNET_RUBRIC +
            INTEGRITY_RUBRIC
        ),
    ),
]

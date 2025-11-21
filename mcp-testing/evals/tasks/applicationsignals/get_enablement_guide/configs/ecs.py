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

"""ECS enablement tasks configurations."""

from ..enablement_tasks import EnablementTask, ENABLEMENT_PROMPT


# Component rubrics - mix and match to build complete validation rubrics

# CloudWatch Agent container
CLOUDWATCH_AGENT_RUBRIC = [
    'IAM: CloudWatchAgentServerPolicy attached to ECS application role',
    'CloudWatch Agent: Sidecar container added to ECS task definition',
    'CloudWatch Agent: CloudWatch Agent configuration file added to ECS task definition',
    'CloudWatch Agent: Configuration file created with traces.traces_collected.application_signals',
    'CloudWatch Agent: Configuration file created with logs.metrics_collected.application_signals',
    'CloudWatch Agent: Log group created for CloudWatch Agent logs',
]

# ADOT SDK container
ADOT_SDK_RUBRIC = [
    'ADOT SDK: ADOT SDK container added as sidecar to ECS task definition',
    'ADOT SDK: ADOT SDK container added volumeMount for opentelemetry-auto-instrumentation',
]

# User Application container
APPLICATION_RUBIC = [
    'Integrity: Application container modified to include volumeMount from ADOT SDK container',
    'Integrity: Aplication containder added container dependency on ADOT SDK container',
    'Integrity: Application container added container dependency on CloudWatch Agent container',
]

# OpenTelemetry environment variables component
COMMON_OTEL_ENV_VARS_RUBRIC = [
    'Integrity: Application container in ECS task definition modified to include OTEL environment variables',
    'Integrity: -e OTEL_RESOURCE_ATTRIBUTES with service.name',
    'Integrity: -e OTEL_LOGS_EXPORTER=none',
    'Integrity: -e OTEL_METRICS_EXPORTER=none',
    'Integrity: -e OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf',
    'Integrity: -e OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true',
    'Integrity: -e OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT=http://localhost:4316/v1/metrics',
    'Integrity: -e OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:4316/v1/traces',
]

# OpenTelemetry Python environment variables
PYTHON_OTEL_ENV_VARS_RUBRIC = [
    'Integrity: -e OTEL_PYTHON_CONFIGURATOR=aws_configurator',
    'Integrity: -e OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true',
    'Integrity: -e PYTHONPATH includes volumeMount from ADOT Python container and auto_instrumentation of the volumeMount',
]

PYTHON_DJANGO_ENV_VARS_RUBRIC = [
    'Integrity: -e DJANGO_SETTINGS_MODULE set to django application settings module',
]

# OpenTelemetry Node.js environment variables for CJS applications
NODEJS_OTEL_ENV_VARS_RUBRIC = [
    'Integrity: -e NODE_OPTIONS=--require /otel-auto-instrumentation-node/autoinstrumentation.js',
]

# OpenTelemetry Java environment variables
JAVA_OTEL_ENV_VARS_RUBRIC = [
    'Integrity: -e JAVA_TOOL_OPTIONS= -javaagent:/otel-auto-instrumentation-java/javaagent.jar',
]

# ADOT SDK for Java
JAVA_ADOT_SDK_RUBRIC = [
    'ADOT SDK: CMD has copy javaagent from ADOT SDK container to volumeMount in application container',
]

# OpenTelemetry Java environment variables
DOTNET_OTEL_ENV_VARS_RUBRIC = [
    'Integrity: -e DOTNET_ADDITIONAL_DEPS=/otel-auto-instrumentation-dotnet/AdditionalDeps',
    'Integrity: -e DOTNET_SHARED_STORE=/otel-auto-instrumentation-dotnet/store',
    'Integrity: -e DOTNET_STARTUP_HOOKS=/otel-auto-instrumentation-dotnet/net/OpenTelemetry.AutoInstrumentation.StartupHook.dll',
    'Integrity: -e OTEL_DOTNET_AUTO_HOME=/otel-auto-instrumentation-dotnet',
]

# Task definitions - compose rubrics from components
ECS_TASKS = [

    # CDK - Python Flask
    EnablementTask(
        id='ecs_python_flask_cdk',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/ecs/cdk',
            'docker-apps/python/flask',
        ],
        iac_dir='infrastructure/ecs/cdk',
        app_dir='docker-apps/python/flask',
        language='python',
        framework='flask',
        platform='ecs',
        build_command='npm install && npm run build',
        build_working_dir='infrastructure/ecs/cdk',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_SDK_RUBRIC +
            APPLICATION_RUBIC +
            COMMON_OTEL_ENV_VARS_RUBRIC +
            PYTHON_OTEL_ENV_VARS_RUBRIC
        ),
    ),

    # Terraform - Python Flask
    EnablementTask(
        id='ecs_python_flask_terraform',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/ecs/terraform',
            'docker-apps/python/flask',
        ],
        iac_dir='infrastructure/ecs/terraform',
        app_dir='docker-apps/python/flask',
        language='python',
        framework='flask',
        platform='ecs',
        build_command='terraform init && terraform validate',
        build_working_dir='infrastructure/ecs/terraform',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_SDK_RUBRIC +
            APPLICATION_RUBIC +
            COMMON_OTEL_ENV_VARS_RUBRIC +
            PYTHON_OTEL_ENV_VARS_RUBRIC
        ),
    ),

    # CDK - Python Django
    EnablementTask(
        id='ecs_python_django_cdk',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/ecs/cdk',
            'docker-apps/python/django',
        ],
        iac_dir='infrastructure/ecs/cdk',
        app_dir='docker-apps/python/django',
        language='python',
        framework='django',
        platform='ecs',
        build_command='npm install && npm run build',
        build_working_dir='infrastructure/ecs/cdk',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_SDK_RUBRIC +
            APPLICATION_RUBIC +
            COMMON_OTEL_ENV_VARS_RUBRIC +
            PYTHON_OTEL_ENV_VARS_RUBRIC +
            PYTHON_DJANGO_ENV_VARS_RUBRIC
        ),
    ),

    # Terraform - Python Django
    EnablementTask(
        id='ecs_python_django_terraform',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/ecs/terraform',
            'docker-apps/python/django',
        ],
        iac_dir='infrastructure/ecs/terraform',
        app_dir='docker-apps/python/django',
        language='python',
        framework='django',
        platform='ecs',
        build_command='terraform init && terraform validate',
        build_working_dir='infrastructure/ecs/terraform',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_SDK_RUBRIC +
            APPLICATION_RUBIC +
            COMMON_OTEL_ENV_VARS_RUBRIC +
            PYTHON_OTEL_ENV_VARS_RUBRIC +
            PYTHON_DJANGO_ENV_VARS_RUBRIC
        ),
    ),

    # CDK - Node.js CJS
    EnablementTask(
        id='ecs_nodejs_cdk',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/ecs/cdk',
            'docker-apps/nodejs/express',
        ],
        iac_dir='infrastructure/ecs/cdk',
        app_dir='docker-apps/nodejs/express',
        language='nodejs',
        framework='express',
        platform='ecs',
        build_command='npm install && npm run build',
        build_working_dir='infrastructure/ecs/cdk',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_SDK_RUBRIC +
            APPLICATION_RUBIC +
            COMMON_OTEL_ENV_VARS_RUBRIC +
            NODEJS_OTEL_ENV_VARS_RUBRIC
        ),
    ),

    # Terraform - Java
    EnablementTask(
        id='ecs_java_terraform',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/ecs/terraform',
            'docker-apps/java',
        ],
        iac_dir='infrastructure/ecs/terraform',
        app_dir='docker-apps/java',
        language='java',
        framework='spring-boot',
        platform='ecs',
        build_command='terraform init && terraform validate',
        build_working_dir='infrastructure/ecs/terraform',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_SDK_RUBRIC +
            APPLICATION_RUBIC +
            COMMON_OTEL_ENV_VARS_RUBRIC +
            JAVA_OTEL_ENV_VARS_RUBRIC +
            JAVA_ADOT_SDK_RUBRIC
        ),
    ),

    # CDK - .NET
    EnablementTask(
        id='ecs_dotnet_cdk',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/ecs/cdk',
            'docker-apps/dotnet/aspnetcore',
        ],
        iac_dir='infrastructure/ecs/cdk',
        app_dir='docker-apps/dotnet/aspnetcore',
        language='dotnet',
        framework='aspnetcore',
        platform='ecs',
        build_command='npm install && npm run build',
        build_working_dir='infrastructure/ecs/cdk',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_SDK_RUBRIC +
            APPLICATION_RUBIC +
            COMMON_OTEL_ENV_VARS_RUBRIC +
            DOTNET_OTEL_ENV_VARS_RUBRIC
        ),
    ),

    # Terraform - .NET
    EnablementTask(
        id='ecs_dotnet_terraform',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/ecs/terraform',
            'docker-apps/dotnet/aspnetcore',
        ],
        iac_dir='infrastructure/ecs/terraform',
        app_dir='docker-apps/dotnet/aspnetcore',
        language='dotnet',
        framework='aspnetcore',
        platform='ecs',
        build_command='terraform init && terraform validate',
        build_working_dir='infrastructure/ecs/terraform',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_SDK_RUBRIC +
            APPLICATION_RUBIC +
            COMMON_OTEL_ENV_VARS_RUBRIC +
            DOTNET_OTEL_ENV_VARS_RUBRIC
        ),
    ),
]

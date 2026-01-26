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

"""EC2 Node.js enablement task configurations."""

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

# ADOT Node.js component
ADOT_NODEJS_RUBRIC = [
    'Dockerfile: @aws/aws-distro-opentelemetry-node-autoinstrumentation installed via npm',
]

# OpenTelemetry environment variables component
OTEL_ENV_VARS_RUBRIC = [
    'UserData docker run: -e OTEL_METRICS_EXPORTER=none',
    'UserData docker run: -e OTEL_LOGS_EXPORTER=none',
    'UserData docker run: -e OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true',
    'UserData docker run: -e OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf',
    'UserData docker run: -e OTEL_TRACES_SAMPLER=xray',
    'UserData docker run: -e OTEL_TRACES_SAMPLER_ARG=endpoint=http://localhost:2000',
    'UserData docker run: -e OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT=http://localhost:4316/v1/metrics',
    'UserData docker run: -e OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:4316/v1/traces',
    'UserData docker run: -e OTEL_RESOURCE_ATTRIBUTES with service.name',
]

# Docker component
DOCKER_RUBRIC = [
    'UserData docker run: --network host flag present for CloudWatch Agent communication',
]

# Node.js CMD modification component
NODEJS_CMD_RUBRIC = [
    'Dockerfile: CMD modified to use node --require flag with ADOT auto-instrumentation (CommonJS) OR --import + --experimental-loader (ESM)',
    'Integrity: Application logic unchanged (JavaScript/TypeScript source files excluding configuration files)',
]

# Integrity checks (common across IaC tools)
INTEGRITY_RUBRIC = [
    'Integrity: Only infrastructure/config files modified (Dockerfile, IaC) - application logic unchanged',
    'Integrity: Existing docker run environment variables preserved (PORT, SERVICE_NAME, etc.)',
    'Integrity: UserData commands added in correct sequence: prerequisites -> CW Agent -> docker run',
]


# Task definitions - compose rubrics from components
EC2_NODEJS_DOCKER_TASKS = [
    # CDK - Express
    EnablementTask(
        id='ec2_nodejs_express_docker_cdk',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/ec2/cdk',
            'docker-apps/nodejs/express',
        ],
        iac_dir='infrastructure/ec2/cdk',
        app_dir='docker-apps/nodejs/express',
        language='nodejs',
        framework='express',
        platform='ec2',
        build_command='npm install && npm run build',
        build_working_dir='infrastructure/ec2/cdk',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_NODEJS_RUBRIC +
            OTEL_ENV_VARS_RUBRIC +
            DOCKER_RUBRIC +
            NODEJS_CMD_RUBRIC +
            INTEGRITY_RUBRIC
        ),
    ),

    # Terraform - Express
    EnablementTask(
        id='ec2_nodejs_express_docker_terraform',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/ec2/terraform',
            'docker-apps/nodejs/express',
        ],
        iac_dir='infrastructure/ec2/terraform',
        app_dir='docker-apps/nodejs/express',
        language='nodejs',
        framework='express',
        platform='ec2',
        build_command='terraform init && terraform validate',
        build_working_dir='infrastructure/ec2/terraform',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_NODEJS_RUBRIC +
            OTEL_ENV_VARS_RUBRIC +
            DOCKER_RUBRIC +
            NODEJS_CMD_RUBRIC +
            INTEGRITY_RUBRIC
        ),
    ),
]

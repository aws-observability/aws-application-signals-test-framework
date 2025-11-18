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

"""Lambda enablement task configurations."""

from ..enablement_tasks import EnablementTask, ENABLEMENT_PROMPT


# Component rubrics for Lambda Application Signals enablement

# X-Ray tracing component
XRAY_TRACING_RUBRIC = [
    'Lambda: X-Ray active tracing enabled (tracing: lambda.Tracing.ACTIVE or TracingConfig.Mode: Active)',
]

# ADOT Lambda layer components (language-specific)
PYTHON_ADOT_LAYER_RUBRIC = [
    'Lambda: ADOT layer added with correct runtime-specific ARN (must be AWSOpenTelemetryDistroPython, not aws-otel-python or other old names)',
    'Lambda: Layer version and account ID are appropriate for region',
]

NODEJS_ADOT_LAYER_RUBRIC = [
    'Lambda: ADOT layer added with correct runtime-specific ARN (must be AWSOpenTelemetryDistroJs, not aws-otel-nodejs or other old names)',
    'Lambda: Layer version and account ID are appropriate for region',
]

JAVA_ADOT_LAYER_RUBRIC = [
    'Lambda: ADOT layer added with correct runtime-specific ARN (must be AWSOpenTelemetryDistroJava, not aws-otel-java or other old names)',
    'Lambda: Layer version and account ID are appropriate for region',
]

DOTNET_ADOT_LAYER_RUBRIC = [
    'Lambda: ADOT layer added with correct runtime-specific ARN (must be AWSOpenTelemetryDistroDotNet, not aws-otel-dotnet or other old names)',
    'Lambda: Layer version and account ID are appropriate for region',
]

# OTEL environment variable component
OTEL_WRAPPER_RUBRIC = [
    'Lambda: AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument environment variable set',
]

# Integrity checks
LAMBDA_INTEGRITY_RUBRIC = [
    'Integrity: All existing environment variables are preserved (passes if no existing environment variables in original config, or if diff shows existing ones are kept)',
    'Integrity: All existing layers are preserved (passes if no existing layers in original config, or if diff shows existing ones are kept)', 
    'Integrity: No application code changes required',
    'Integrity: Only Lambda function configuration modified',
]


# Task definitions for different Lambda runtime and IaC combinations
LAMBDA_TASKS = [
    # Python Lambda with CDK
    EnablementTask(
        id='lambda_python_cdk',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/lambda/cdk',
            'infrastructure/lambda/python-lambda',
        ],
        iac_dir='infrastructure/lambda/cdk',
        app_dir='infrastructure/lambda/python-lambda',
        language='python',
        framework='lambda',
        platform='lambda',
        build_command='npm install && npm run build',
        build_working_dir='infrastructure/lambda/cdk',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            XRAY_TRACING_RUBRIC +
            PYTHON_ADOT_LAYER_RUBRIC +
            OTEL_WRAPPER_RUBRIC +
            LAMBDA_INTEGRITY_RUBRIC
        ),
    ),

    # Python Lambda with Terraform
    EnablementTask(
        id='lambda_python_terraform',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/lambda/terraform',
            'infrastructure/lambda/python-lambda',
        ],
        iac_dir='infrastructure/lambda/terraform',
        app_dir='infrastructure/lambda/python-lambda',
        language='python',
        framework='lambda',
        platform='lambda',
        build_command='terraform init && terraform validate',
        build_working_dir='infrastructure/lambda/terraform',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            XRAY_TRACING_RUBRIC +
            PYTHON_ADOT_LAYER_RUBRIC +
            OTEL_WRAPPER_RUBRIC +
            LAMBDA_INTEGRITY_RUBRIC
        ),
    ),

    # Node.js Lambda with CDK
    EnablementTask(
        id='lambda_nodejs_cdk',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/lambda/cdk',
            'infrastructure/lambda/nodejs-lambda',
        ],
        iac_dir='infrastructure/lambda/cdk',
        app_dir='infrastructure/lambda/nodejs-lambda',
        language='nodejs',
        framework='lambda',
        platform='lambda',
        build_command='npm install && npm run build',
        build_working_dir='infrastructure/lambda/cdk',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            XRAY_TRACING_RUBRIC +
            NODEJS_ADOT_LAYER_RUBRIC +
            OTEL_WRAPPER_RUBRIC +
            LAMBDA_INTEGRITY_RUBRIC
        ),
    ),

    # Node.js Lambda with Terraform
    EnablementTask(
        id='lambda_nodejs_terraform',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/lambda/terraform',
            'infrastructure/lambda/nodejs-lambda',
        ],
        iac_dir='infrastructure/lambda/terraform',
        app_dir='infrastructure/lambda/nodejs-lambda',
        language='nodejs',
        framework='lambda',
        platform='lambda',
        build_command='terraform init && terraform validate',
        build_working_dir='infrastructure/lambda/terraform',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            XRAY_TRACING_RUBRIC +
            NODEJS_ADOT_LAYER_RUBRIC +
            OTEL_WRAPPER_RUBRIC +
            LAMBDA_INTEGRITY_RUBRIC
        ),
    ),

    # Java Lambda with CDK
    EnablementTask(
        id='lambda_java_cdk',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/lambda/cdk',
            'infrastructure/lambda/java-lambda',
        ],
        iac_dir='infrastructure/lambda/cdk',
        app_dir='infrastructure/lambda/java-lambda',
        language='java',
        framework='lambda',
        platform='lambda',
        build_command='npm install && npm run build',
        build_working_dir='infrastructure/lambda/cdk',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            XRAY_TRACING_RUBRIC +
            JAVA_ADOT_LAYER_RUBRIC +
            OTEL_WRAPPER_RUBRIC +
            LAMBDA_INTEGRITY_RUBRIC
        ),
    ),

    # Java Lambda with Terraform
    EnablementTask(
        id='lambda_java_terraform',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/lambda/terraform',
            'infrastructure/lambda/java-lambda',
        ],
        iac_dir='infrastructure/lambda/terraform',
        app_dir='infrastructure/lambda/java-lambda',
        language='java',
        framework='lambda',
        platform='lambda',
        build_command='terraform init && terraform validate',
        build_working_dir='infrastructure/lambda/terraform',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            XRAY_TRACING_RUBRIC +
            JAVA_ADOT_LAYER_RUBRIC +
            OTEL_WRAPPER_RUBRIC +
            LAMBDA_INTEGRITY_RUBRIC
        ),
    ),

    # .NET Lambda with CDK
    EnablementTask(
        id='lambda_dotnet_cdk',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/lambda/cdk',
            'infrastructure/lambda/dotnet-lambda',
        ],
        iac_dir='infrastructure/lambda/cdk',
        app_dir='infrastructure/lambda/dotnet-lambda',
        language='dotnet',
        framework='lambda',
        platform='lambda',
        build_command='npm install && npm run build',
        build_working_dir='infrastructure/lambda/cdk',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            XRAY_TRACING_RUBRIC +
            DOTNET_ADOT_LAYER_RUBRIC +
            OTEL_WRAPPER_RUBRIC +
            LAMBDA_INTEGRITY_RUBRIC
        ),
    ),

    # .NET Lambda with Terraform
    EnablementTask(
        id='lambda_dotnet_terraform',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/lambda/terraform',
            'infrastructure/lambda/dotnet-lambda',
        ],
        iac_dir='infrastructure/lambda/terraform',
        app_dir='infrastructure/lambda/dotnet-lambda',
        language='dotnet',
        framework='lambda',
        platform='lambda',
        build_command='terraform init && terraform validate',
        build_working_dir='infrastructure/lambda/terraform',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            XRAY_TRACING_RUBRIC +
            DOTNET_ADOT_LAYER_RUBRIC +
            OTEL_WRAPPER_RUBRIC +
            LAMBDA_INTEGRITY_RUBRIC
        ),
    ),
]
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

"""EKS .NET enablement task configurations."""

from ..enablement_tasks import EnablementTask, ENABLEMENT_PROMPT


# Component rubrics - mix and match to build complete validation rubrics

# CloudWatch Agent component
CLOUDWATCH_AGENT_RUBRIC = [
    'IAM: CloudWatchAgentServerPolicy is attached to EKS role used by worker nodes',
    'CloudWatch Observability EKS add-on: Added to the EKS Cluster',
]

# ADOT .NET component
ADOT_DOTNET_RUBRIC = [
    'Kubernetes Deployment: Instrumentation annotation added with inject-dotnet set to true',
]

# Framework-agnostic .NET component
STANDARD_DOTNET_RUBRIC = [
    'Integrity: Application logic unchanged (.NET source files excluding configuration files)',
]

# Integrity checks (common across IaC tools)
INTEGRITY_RUBRIC = [
    'Integrity: Only infrastructure/config files modified (Dockerfile, IaC) - application logic unchanged',
    'Integrity: Existing docker run environment variables preserved (PORT, SERVICE_NAME, etc.)',
]


# Task definitions - compose rubrics from components
EKS_DOTNET_DOCKER_TASKS = [
    # CDK - Spring Boot
    EnablementTask(
        id='eks_dotnet_aspnetcore_docker_cdk',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/eks/cdk',
            'docker-apps/dotnet/aspnetcore',
        ],
        iac_dir='infrastructure/eks/cdk',
        app_dir='docker-apps/dotnet/aspnetcore',
        language='dotnet',
        framework='aspnetcore',
        platform='eks',
        build_command='npm install && npm run build',
        build_working_dir='infrastructure/eks/cdk',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_DOTNET_RUBRIC +
            STANDARD_DOTNET_RUBRIC +
            INTEGRITY_RUBRIC
        ),
    ),

    # Terraform - Spring Boot
    EnablementTask(
        id='eks_dotnet_aspnetcore_docker_terraform',
        prompt_template=ENABLEMENT_PROMPT,
        git_paths=[
            'infrastructure/eks/terraform',
            'docker-apps/dotnet/aspnetcore',
        ],
        iac_dir='infrastructure/eks/terraform',
        app_dir='docker-apps/dotnet/aspnetcore',
        language='dotnet',
        framework='aspnetcore',
        platform='eks',
        build_command='terraform init && terraform validate',
        build_working_dir='infrastructure/eks/terraform',
        expected_tools=['get_enablement_guide'],
        modifies_code=True,
        validation_rubric=(
            CLOUDWATCH_AGENT_RUBRIC +
            ADOT_DOTNET_RUBRIC +
            STANDARD_DOTNET_RUBRIC +
            INTEGRITY_RUBRIC
        ),
    ),
]

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

"""Change event tasks for Application Signals MCP evaluation.

Evaluates whether the AI agent can use the list_change_events tool to correlate infrastructure and application changes with service performance issues.
"""

from evals.core import (
    BedrockLLMProvider,
    Captor,
    FinalResponseCaptor,
    LLMJudgeValidator,
    ToolCallsCaptor,
    ToolPresenceValidator,
    ToolCallValidator,
    ValidationPromptType,
    Validator,
)
from evals.tasks.applicationsignals import ApplicationSignalsTask
from pathlib import Path
from typing import Any, Dict, Optional


class ChangeEventTask(ApplicationSignalsTask):
    """Task for evaluating change event correlation capabilities."""

    def __init__(
        self,
        id: str,
        prompt: str,
        validation_rubric: list[str],
        expected_tool_calls: list[list[str]] = None,
        expected_tools_set: list[str] = None,
        mock_config: Optional[Dict[str, Any]] = None,
    ):
        """Initialize change event task."""
        super().__init__(id=id)
        self.fixtures_dir = Path(__file__).parent / 'fixtures'
        self.prompt = prompt
        self.mock_config = mock_config
        self.validation_rubric = validation_rubric
        self.expected_tool_calls = expected_tool_calls
        self.expected_tools_set = expected_tools_set

    def get_working_directory(self) -> Optional[Path]:
        """No working directory needed for change event tasks."""
        return None

    def get_prompt(self, working_directory: Path) -> str:
        """Return task prompt."""
        return self.prompt

    def get_captors(self, working_directory: Path) -> list[Captor]:
        """Get captors for recording task execution."""
        return [ToolCallsCaptor(), FinalResponseCaptor()]

    def get_validators(self, working_directory: Path) -> list[Validator]:
        """Get validators for verifying task completion."""
        validators = []
        
        if self.expected_tool_calls:
            validators.append(
                ToolCallValidator(expected_tool_calls=self.expected_tool_calls, ignore_file_tools=True)
            )
        
        if self.expected_tools_set:
            validators.append(
                ToolPresenceValidator(expected_tools=self.expected_tools_set, ignore_file_tools=True)
            )
        
        validators.append(
            LLMJudgeValidator(
                validation_prompt_type=ValidationPromptType.WORKFLOW,
                llm_provider=BedrockLLMProvider(),
                rubric=self.validation_rubric,
            )
        )
        
        return validators


# Task definitions
TASKS = [
    ChangeEventTask(
        id='change-1-deployment-correlation',
        prompt='Can you list all the changes to my payments-service service in the last 3 hours?',
        validation_rubric=[
            'Agent sees that there is 1 deployment event'
        ],
        expected_tool_calls=[
            ['get_service_detail','list_change_events'],
        ],
        mock_config={
            'boto3': {
                'application-signals': {
                    'list_entity_events': [
                        {'request': {}, 'response': 'change-1-list-entity-events.json'}
                    ],
                    'list_services': [
                        {'request': {}, 'response': 'change-1-list-services.json'}   
                    ],
                    'get_service': [
                        {'request': {}, 'response': 'change-1-get-service.json'}
                    ],
                    'list_audit_findings': [
                        {'request': {}, 'response': 'change-1-audit-findings.json'}
                    ]
                },
            }
        },
    ),
    ChangeEventTask(
        id='slo-changes-deployment-correlation',
        prompt='My payments-latency SLO is breaching. Can you investigate the root cause?',
        validation_rubric=[
            'Agent sees that there is 1 deployment event and uses information in the event to complete root cause.'
        ],
        expected_tools_set=[
            'get_slo',
            'get_service_detail',
            'list_change_events',
        ],
        mock_config={
            'boto3': {
                'application-signals': {
                    'get_service_level_objective': [
                        {'request': {}, 'response': 'change-1-get-service-level-objective.json'}
                    ],
                    'list_entity_events': [
                        {'request': {}, 'response': 'change-1-list-entity-events.json'}
                    ],
                    'list_services': [
                        {'request': {}, 'response': 'change-1-list-services.json'}   
                    ],
                    'get_service': [
                        {'request': {}, 'response': 'change-1-get-service.json'}
                    ],
                    'list_audit_findings': [
                        {'request': {}, 'response': 'change-1-audit-findings.json'}
                    ]
                },
            }
        },
    ),
]

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

"""Base task class for Application Signals MCP evaluation."""

from evals.core import Task
from pathlib import Path


SAMPLES_ROOT = Path(__file__).parent.parent.parent.parent


class ApplicationSignalsTask(Task):
    """Base class for Application Signals evaluation tasks.

    Provides common configuration for all Application Signals tasks.
    """

    def get_server_root_directory(self) -> Path:
        """Return MCP server root directory.

        TODO: Update this to point to your local MCP server directory.

        Example:
            return Path('/Users/username/projects/mcp/src/cloudwatch-applicationsignals-mcp-server')
        """
        raise NotImplementedError(
            "Please configure get_server_root_directory() in base.py to point to your local MCP server. "
            "See mcp-testing/README.md for setup instructions."
        )

    def get_server_file(self) -> Path:
        """Return MCP server file path."""
        return (
            self.get_server_root_directory()
            / 'awslabs'
            / 'cloudwatch_applicationsignals_mcp_server'
            / 'server.py'
        )

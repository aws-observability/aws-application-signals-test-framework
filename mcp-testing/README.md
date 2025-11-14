# MCP Testing Framework

Evaluation tasks and sample applications for testing the CloudWatch Application Signals MCP server.

## Setup

### 1. Install MCP Server

Clone and install the CloudWatch Application Signals MCP server:

```bash
# Clone the MCP repository
git clone <mcp-repo-url>
cd <mcp-repo>/src/cloudwatch-applicationsignals-mcp-server

# Install the server package
uv pip install -e .
```

### 2. Setup Environment and Install Dependencies

From the `mcp-testing/` directory:

```bash
# Create virtual environment
uv venv

# Activate virtual environment
source .venv/bin/activate

# Install eval dependencies
uv pip install -r evals/requirements.txt
```

### 3. Configure MCP Server Path

> **Note:** The sample applications directory (`SAMPLES_ROOT`) is hardcoded to point to `mcp-testing/` as samples are expected to live in this directory.

Get the absolute path to your MCP server directory:

```bash
# Navigate to your MCP server directory
cd <your-mcp-repo>/src/cloudwatch-applicationsignals-mcp-server

# Get the absolute path
pwd
```

Edit `evals/tasks/applicationsignals/base.py` and update the `get_server_root_directory()` method with the path from above:

```python
def get_server_root_directory(self) -> Path:
    return Path('/absolute/path/to/cloudwatch-applicationsignals-mcp-server')
```

### 4. Run Evals

From the `mcp-testing/` directory:

```bash
python -m evals tasks --list              # List all available tasks
python -m evals tasks --task-id <task_id> # Run a specific task
```

See `evals/README.md` for detailed documentation.

# Cerebelum CLI - Command Line Interface

Command-line tool for monitoring and controlling Cerebelum workflow executions.

## Installation

```bash
# From python-sdk directory
source venv/bin/activate
pip install click

# Make CLI executable
chmod +x cerebelum_cli.py

# Optional: Create symlink for easy access
ln -s $(pwd)/cerebelum_cli.py /usr/local/bin/cerebelum
```

## Quick Start

```bash
# List all executions
./cerebelum_cli.py list

# Show detailed status
./cerebelum_cli.py status <execution-id>

# Watch execution in real-time
./cerebelum_cli.py watch <execution-id>

# Resume failed execution
./cerebelum_cli.py resume <execution-id>

# Show active workflows
./cerebelum_cli.py active
```

## Commands

### `list` - List Executions

List workflow executions with optional filtering.

```bash
# List all executions
cerebelum list

# List only running executions
cerebelum list --status running

# List by workflow name
cerebelum list --workflow MyWorkflow

# Limit results
cerebelum list --limit 50

# Combine filters
cerebelum list --status failed --workflow DeployWorkflow --limit 10
```

**Options:**
- `--status`: Filter by status (`running`, `completed`, `failed`, `sleeping`, `approval`, `paused`)
- `--workflow`: Filter by workflow name
- `--limit`: Maximum number of results (default: 20)

**Output:**
```
ID                                       WORKFLOW                  PROGRESS     STATUS
====================================================================================================
abc-123-def-456...                       DeploymentWorkflow        3/10 (30%)   🔄 RUNNING
xyz-789-ghi-012...                       TestWorkflow              10/10 (100%) ✅ COMPLETED
====================================================================================================
Showing 2 of 15 executions
```

### `status` - Show Detailed Status

Display comprehensive status information for a specific execution.

```bash
cerebelum status abc-123-def-456
```

**Output:**
```
============================================================
  Execution: abc-123-def-456-789-012
============================================================

📊 Overview:
  Workflow:  DeploymentWorkflow
  Status:    🔄 RUNNING
  Started:   2024-12-11 10:30:00
  Duration:  5m 23s

📈 Progress:
  Step:      4/10
  Current:   deploy_to_staging
  Complete:  40.0%
  [████████████████░░░░░░░░░░░░░░░░░░░░░░░░] 40.0%

✅ Completed Steps (3):
  - validate_config
  - build_artifact
  - run_tests

============================================================
```

### `watch` - Real-time Monitoring

Watch execution progress with auto-refresh.

```bash
# Watch with default 2-second interval
cerebelum watch abc-123

# Custom refresh interval
cerebelum watch abc-123 --interval 5
```

**Features:**
- Auto-refreshing display
- Progress bar visualization
- Shows current step
- Sleep countdown for sleeping workflows
- Stops automatically when execution completes
- Press Ctrl+C to stop watching

**Output:**
```
============================================================
  Watching: abc-123-def-456-789-012
============================================================

Workflow: DeploymentWorkflow
Status:   🔄 RUNNING

Progress: 4/10 (40.0%)
Current:  deploy_to_staging

[█████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░]

Last update: 14:32:15
Press Ctrl+C to stop watching
```

### `resume` - Resume Execution

Resume a paused or failed workflow execution.

```bash
cerebelum resume abc-123-def-456
```

**What it does:**
1. Checks current execution status
2. Verifies execution can be resumed (not already completed/running)
3. Resumes execution from last checkpoint
4. Skips already completed steps

**Output:**
```
Checking status of abc-123-def-456...
Current status: FAILED
Resuming execution...
✅ Execution resumed successfully!

💡 Tip: Use 'cerebelum watch abc-123-def-456' to monitor progress
```

### `active` - Show Active Workflows

Quick view of all currently running workflows.

```bash
cerebelum active
```

**Output:**
```
Fetching active workflows...

🔄 Active Workflows (3):
================================================================================

DeploymentWorkflow
  ID:       abc-123-def-456-789-012
  Progress: 4/10 (40%)
  Current:  deploy_to_staging

TestWorkflow
  ID:       xyz-789-ghi-012-345-678
  Progress: 7/15 (47%)
  Current:  run_integration_tests

================================================================================
```

## Global Options

All commands support these global options:

```bash
# Connect to different Core instance
cerebelum --core-url prod.example.com:9090 list

# Use environment variable
export CEREBELUM_CORE_URL=prod.example.com:9090
cerebelum list
```

**Options:**
- `--core-url`: Cerebelum Core URL (default: `localhost:9090`)
- Environment variable: `CEREBELUM_CORE_URL`

## Use Cases

### Monitor Long-Running Deployments

```bash
# Start deployment
./my_deployment.py

# In another terminal, watch progress
cerebelum watch <execution-id>
```

### Resume Failed Deployments

```bash
# List failed executions
cerebelum list --status failed

# Check what failed
cerebelum status <execution-id>

# Fix the issue, then resume
cerebelum resume <execution-id>
```

### Dashboard View

```bash
# Create a simple dashboard script
#!/bin/bash
while true; do
    clear
    echo "=== Cerebelum Dashboard ==="
    echo
    ./cerebelum_cli.py active
    echo
    ./cerebelum_cli.py list --status failed --limit 5
    sleep 10
done
```

### Workflow Monitoring in CI/CD

```bash
#!/bin/bash
# Deploy script with monitoring

# Trigger deployment
EXEC_ID=$(python deploy.py | grep "execution_id" | cut -d: -f2)

# Monitor until completion
cerebelum watch $EXEC_ID

# Check result
STATUS=$(cerebelum status $EXEC_ID | grep "Status:" | awk '{print $3}')

if [ "$STATUS" = "COMPLETED" ]; then
    echo "✅ Deployment successful"
    exit 0
else
    echo "❌ Deployment failed"
    exit 1
fi
```

## Troubleshooting

### "Error importing cerebelum"

Make sure protobuf files are generated:

```bash
python -m grpc_tools.protoc \
    --proto_path=../../priv/protos \
    --python_out=cerebelum \
    --grpc_python_out=cerebelum \
    ../../priv/protos/worker_service.proto
```

### "Connection refused"

Check that Cerebelum Core is running:

```bash
# In Core directory
mix run --no-halt

# Or check if already running
lsof -i :9090
```

### "Execution not found"

The execution ID might be invalid or from a different Core instance. Use `cerebelum list` to see available executions.

## Advanced Usage

### Scripting with CLI

```bash
# Get execution IDs as JSON (future enhancement)
cerebelum list --format json

# Filter and process with jq
cerebelum list --status running --format json | jq '.[] | .execution_id'

# Bulk resume all failed executions
for id in $(cerebelum list --status failed --format json | jq -r '.[] | .execution_id'); do
    cerebelum resume $id
done
```

### Integration with Monitoring Tools

```bash
# Export metrics to Prometheus (future enhancement)
cerebelum metrics --prometheus-port 9091

# Send alerts on failure
cerebelum list --status failed --format json | \
    jq -r '.[] | "\(.workflow_name) failed: \(.execution_id)"' | \
    while read msg; do
        curl -X POST slack-webhook-url -d "{\"text\": \"$msg\"}"
    done
```

## Related Documentation

- [ExecutionClient API Reference](EXECUTION_CLIENT_README.md)
- [Python SDK Guide](RESUMEN_PYTHON_SDK.md)
- [Long-Running Workflows](../../docs/long-running-workflows.md)

## Tips

1. **Use `watch` for deployments** - Real-time monitoring is perfect for tracking long-running deployments

2. **Combine with shell scripts** - The CLI is designed to work well with standard Unix tools (grep, awk, etc.)

3. **Set CEREBELUM_CORE_URL** - Use environment variable in production to avoid repeating `--core-url`

4. **Tab completion** - Future enhancement will add shell completion for commands and execution IDs

5. **Color output** - The CLI uses emoji and symbols that work best in modern terminals

## Future Enhancements

- [ ] JSON output format (`--format json`)
- [ ] Shell auto-completion
- [ ] Metrics export (Prometheus)
- [ ] Filtering by date range
- [ ] Execution cancellation command
- [ ] Bulk operations
- [ ] Configuration file support (~/.cerebelumrc)

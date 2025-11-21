#!/usr/bin/env python3
"""
DISTRIBUTED SERVER: Run workflow(s) as worker server

This script runs workflows in DISTRIBUTED mode as a server.
It will:
1. Auto-register all workflow steps with Core
2. Submit workflow blueprints to Core
3. Run as a worker server showing logs
4. Process tasks when Core assigns them
5. Block indefinitely until Ctrl+C

Usage:
    Terminal 1: cd ../../ && mix run --no-halt              # Start Core
    Terminal 2: python3 06_distributed_server.py            # Run this server
    Terminal 3: python3 06_execute_workflow.py <workflow>   # Execute workflows

The server will show logs like:
    ✅ Worker 'python-workflows-abc123' registered successfully
    ✅ Workflow 'hello_workflow' blueprint submitted successfully
    📋 Received task: greet (execution: xyz-789)
    👋 [greet] Hello, Alice!
    ✅ Task completed: greet

Multiple Workflows:
    You can register multiple workflows in this server.
    Just add them to the WORKFLOWS list below.
"""

import asyncio
from cerebelum import step, workflow, Context


# =============================================================================
# WORKFLOW DEFINITIONS
# =============================================================================

@step
async def greet(context: Context, inputs: dict):
    """Greet the user."""
    name = inputs.get("name", "World")
    print(f"  👋 [{context.step_name}] Hello, {name}!")
    return {"message": f"Hello, {name}!"}


@step
async def make_uppercase(context: Context, greet: dict):
    """Convert to uppercase."""
    message = greet["message"]
    upper = message.upper()
    print(f"  🔠 [{context.step_name}] {upper}")
    return {"result": upper}


@workflow
def hello_workflow(wf):
    """Simple workflow for demonstration."""
    wf.timeline(greet >> make_uppercase)


# =============================================================================
# REGISTER YOUR WORKFLOWS HERE
# =============================================================================

# List all workflows you want to register with this server
WORKFLOWS = [
    hello_workflow,
    # Add more workflows here:
    # another_workflow,
    # user_onboarding_workflow,
]


# =============================================================================
# MAIN
# =============================================================================

async def main():
    """Run workflow as distributed server."""

    print("=" * 70)
    print("STARTING DISTRIBUTED WORKER SERVER")
    print("=" * 70)
    print()
    print("This script will:")
    print("  1. Connect to Core (localhost:9090)")
    print("  2. Auto-register workflow 'hello_workflow'")
    print("  3. Submit initial execution")
    print("  4. Run as worker server (shows logs)")
    print("  5. Process tasks until Ctrl+C")
    print()
    print("Make sure Core is running:")
    print("  Terminal 1: cd ../../ && mix run --no-halt")
    print()
    print("To execute workflows:")
    print("  Terminal 3: python3 06_execute_workflow.py")
    print()
    print("=" * 70)
    print()

    # Run in DISTRIBUTED mode
    # This call NEVER RETURNS - runs as server until Ctrl+C
    await hello_workflow.execute(
        inputs={"name": "Initial"},
        distributed=True
    )


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print()
        print("=" * 70)
        print("Server stopped")
        print("=" * 70)

#!/usr/bin/env python3
"""
EXECUTE WORKFLOW: Send execution requests to Core

This script sends workflow execution requests to Core.
It will:
1. Connect to Core via gRPC
2. Submit workflow execution request with specified workflow name
3. Return immediately with execution ID
4. Can be run multiple times

Usage:
    Terminal 1: cd ../../ && mix run --no-halt              # Start Core
    Terminal 2: python3 06_distributed_server.py            # Start worker
    Terminal 3: python3 06_execute_workflow.py <workflow> [name]  # Execute

Arguments:
    workflow: Workflow name to execute (e.g., "hello_workflow")
    name:     Optional name to greet (default: "World")

Examples:
    # Execute hello_workflow with default name
    $ python3 06_execute_workflow.py hello_workflow
    ✅ Workflow submitted: abc-123

    # Execute hello_workflow with "Alice"
    $ python3 06_execute_workflow.py hello_workflow Alice
    ✅ Workflow submitted: def-456

    # Execute another_workflow with "Bob"
    $ python3 06_execute_workflow.py another_workflow Bob
    ✅ Workflow submitted: ghi-789

Note:
    The workflow must be registered by a running worker server.
    Check Terminal 2 (worker) to see which workflows are available.
"""

import asyncio
import sys
from cerebelum.distributed import DistributedExecutor


async def execute_workflow(workflow_name: str, name: str = "World"):
    """Execute a workflow with given inputs.

    Args:
        workflow_name: Name of the workflow to execute
        name: Name to greet (default: "World")
    """

    print("=" * 70)
    print("EXECUTING WORKFLOW")
    print("=" * 70)
    print()
    print(f"📤 Submitting workflow execution to Core...")
    print(f"   Workflow: {workflow_name}")
    print(f"   Input: name={name}")
    print()

    # Create distributed executor
    executor = DistributedExecutor(
        core_url="localhost:9090",
        worker_id="python-executor"
    )

    try:
        # Execute workflow by ID (assumes it's already registered by worker)
        result = await executor.execute(
            workflow=workflow_name,  # Workflow ID (must be registered by server)
            input_data={"name": name}
        )

        print("✅ Workflow submitted successfully!")
        print(f"   Execution ID: {result.execution_id}")
        print(f"   Status: {result.status}")
        print()
        print("💡 Check Terminal 2 (worker server) to see execution logs!")
        print()

    except Exception as e:
        print(f"❌ Error: {type(e).__name__}: {e}")
        print()
        print("Make sure:")
        print("  1. Core is running (Terminal 1): cd ../../ && mix run --no-halt")
        print("  2. Worker is running (Terminal 2): python3 06_distributed_server.py")
        print()
        raise
    finally:
        executor.close()

    print("=" * 70)


async def main():
    """Main entry point."""

    # Check arguments
    if len(sys.argv) < 2:
        print("❌ Error: Workflow name required")
        print()
        print("Usage:")
        print("  python3 06_execute_workflow.py <workflow_name> [name]")
        print()
        print("Examples:")
        print("  python3 06_execute_workflow.py hello_workflow")
        print("  python3 06_execute_workflow.py hello_workflow Alice")
        print("  python3 06_execute_workflow.py another_workflow Bob")
        print()
        sys.exit(1)

    # Get workflow name and optional name argument
    workflow_name = sys.argv[1]
    name = sys.argv[2] if len(sys.argv) > 2 else "World"

    await execute_workflow(workflow_name, name)


if __name__ == "__main__":
    asyncio.run(main())

#!/usr/bin/env python3
"""
Test: Sleep and Resurrection Integration
==========================================

This test verifies that:
1. Python SDK can call sleep() in a step
2. Worker sends SLEEP TaskResult to Core
3. Core Engine receives it via WorkflowDelegatingWorkflow
4. Engine transitions to :sleeping state
5. Workflow can be resurrected after Core restart

Test workflow:
  step1 → step2 (sleeps 10s) → step3

Usage:
  Terminal 1: Core
    cd ../../ && mix run --no-halt

  Terminal 2: Worker Server
    python3 test_sleep_resurrection.py --server

  Terminal 3: Execute Workflow
    python3 test_sleep_resurrection.py --execute

  Terminal 4: Monitor Execution
    # Check Engine status
    # Kill and restart Core to test resurrection
"""

import asyncio
import sys
from datetime import timedelta

from cerebelum import step, workflow, Context
from cerebelum.dsl.async_helpers import sleep


@step
async def start_process(context: Context, name: str):
    """Step 1: Start the process."""
    print(f"  ▶️  [{context.step_name}] Starting process for {name}")
    await asyncio.sleep(0.5)
    return {"started": True, "name": name, "timestamp": "2024-12-11T10:00:00"}


@step
async def wait_deployment(context: Context, start_process: dict):
    """Step 2: Wait for deployment (tests sleep/resurrection)."""
    name = start_process["name"]
    print(f"  ⏳ [{context.step_name}] Waiting for deployment of {name}")
    print(f"     This will sleep for 10 seconds")
    print(f"     🔥 Kill and restart Core during this time to test resurrection!")

    # Sleep for 10 seconds - this should trigger Engine sleep state
    await sleep(10_000, data={"checkpoint": "before_deployment_check"})

    print(f"  ✅ [{context.step_name}] Sleep completed! Checking deployment...")
    await asyncio.sleep(0.5)

    return {
        "deployed": True,
        "deployment_time": "10s",
        "status": "active"
    }


@step
async def finalize(context: Context, start_process: dict, wait_deployment: dict):
    """Step 3: Finalize the process."""
    name = start_process["name"]
    deployed = wait_deployment["deployed"]

    print(f"  🎉 [{context.step_name}] Process finalized!")
    print(f"     Name: {name}")
    print(f"     Deployed: {deployed}")
    print(f"     Execution: {context.execution_id}")

    return {
        "success": True,
        "name": name,
        "execution_id": context.execution_id
    }


@workflow
def test_sleep_workflow(wf):
    """Simple workflow to test sleep and resurrection."""
    wf.timeline(
        start_process >>
        wait_deployment >>
        finalize
    )


async def run_worker_server():
    """Run as worker server (distributed mode)."""
    print("\n" + "=" * 70)
    print("🚀 STARTING WORKER SERVER - SLEEP RESURRECTION TEST")
    print("=" * 70)
    print("\n📋 Workflow: test_sleep_workflow")
    print("📊 Steps: 3 (with 10s sleep in step2)")
    print("🔧 Mode: DISTRIBUTED")
    print("\n" + "=" * 70)
    print("\n🔌 Connecting to Core at localhost:9090...")
    print("📝 Registering workflow...")
    print("🏃 Starting worker server...")
    print("\n💡 To execute, run in another terminal:")
    print("   python3 test_sleep_resurrection.py --execute")
    print("\n💡 To test resurrection:")
    print("   1. Start execution")
    print("   2. Wait for step2 sleep")
    print("   3. Kill Core (Ctrl+C in Core terminal)")
    print("   4. Restart Core")
    print("   5. Workflow should resume automatically!")
    print("\n" + "=" * 70)
    print()

    await test_sleep_workflow.execute(
        inputs={
            "name": "TestProcess"
        },
        distributed=True,
        max_reconnect_attempts=0,  # Infinite reconnection
    )


async def execute_workflow():
    """Execute workflow via gRPC."""
    from cerebelum.distributed import DistributedExecutor

    print("\n" + "=" * 70)
    print("🚀 EXECUTING WORKFLOW - SLEEP RESURRECTION TEST")
    print("=" * 70)

    executor = DistributedExecutor(core_url="localhost:9090")

    print("\n📤 Sending ExecuteRequest to Core...")
    print("📋 Workflow: test_sleep_workflow")
    print("📊 Input: {\"name\": \"TestProcess\"}")
    print("\n" + "=" * 70)

    try:
        result = await executor.execute(
            workflow="test_sleep_workflow",
            input_data={"name": "TestProcess"}
        )

        print("\n" + "=" * 70)
        print("✅ WORKFLOW EXECUTION STARTED")
        print("=" * 70)
        print(f"Execution ID: {result.execution_id}")
        print(f"Status: {result.status}")
        print("\n💡 Check worker server terminal for logs")
        print("💡 Monitor execution in Core logs")
        print("=" * 70)

    except Exception as e:
        print(f"\n❌ Error: {e}")
    finally:
        executor.close()


def print_usage():
    """Print usage instructions."""
    print("\nUsage:")
    print("  python3 test_sleep_resurrection.py --server    # Run worker server")
    print("  python3 test_sleep_resurrection.py --execute   # Execute workflow")
    print()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print_usage()
        sys.exit(1)

    mode = sys.argv[1]

    if mode == "--server":
        try:
            asyncio.run(run_worker_server())
        except KeyboardInterrupt:
            print("\n🛑 Server stopped")
    elif mode == "--execute":
        asyncio.run(execute_workflow())
    else:
        print_usage()
        sys.exit(1)

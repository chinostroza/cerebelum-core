#!/usr/bin/env python3
"""Test ExecutionClient with a simple workflow."""

import asyncio
import sys
sys.path.insert(0, '.')

from cerebelum import (
    WorkflowBuilder,
    DistributedExecutor,
    Worker,
    ExecutionClient,
    ExecutionState
)


# Simple step functions
async def step1(ctx, inputs):
    """First step - double the input."""
    print(f"  Step 1: Doubling {inputs['x']}")
    await asyncio.sleep(0.5)
    return inputs['x'] * 2


async def step2(ctx, inputs):
    """Second step - add 10."""
    print(f"  Step 2: Adding 10 to {inputs}")
    await asyncio.sleep(0.5)
    return inputs + 10


async def step3(ctx, inputs):
    """Third step - multiply by 3."""
    print(f"  Step 3: Multiplying {inputs} by 3")
    await asyncio.sleep(0.5)
    return inputs * 3


async def run_test():
    """Run a test workflow and query its status."""
    print("=" * 60)
    print("Testing ExecutionClient")
    print("=" * 60)

    # Build workflow
    workflow = (
        WorkflowBuilder("test.SimpleWorkflow")
        .timeline(["step1", "step2", "step3"])
        .step("step1", step1)
        .step("step2", step2)
        .step("step3", step3)
        .build()
    )

    # Start worker in background
    worker = Worker(core_url="localhost:9090", worker_id="test-worker-1")
    worker_task = asyncio.create_task(worker.run())

    # Give worker time to register
    await asyncio.sleep(1)

    print("\n1. Executing workflow...")
    executor = DistributedExecutor(core_url="localhost:9090")

    try:
        # Execute workflow
        execution_task = asyncio.create_task(
            executor.execute(workflow, {"x": 5})
        )

        # Wait a bit for execution to start
        await asyncio.sleep(2)

        # Create ExecutionClient
        client = ExecutionClient(core_url="localhost:9090")

        print("\n2. Listing all executions...")
        try:
            executions, total, has_more = await client.list_executions(limit=5)
            print(f"   Found {total} total execution(s)")

            if executions:
                for i, exec_status in enumerate(executions, 1):
                    status_symbol = {
                        ExecutionState.RUNNING: "🔄",
                        ExecutionState.COMPLETED: "✅",
                        ExecutionState.FAILED: "❌",
                        ExecutionState.SLEEPING: "💤",
                    }.get(exec_status.status, "❓")

                    print(f"\n   Execution {i}:")
                    print(f"     {status_symbol} ID: {exec_status.execution_id[:24]}...")
                    print(f"     Workflow: {exec_status.workflow_name}")
                    print(f"     Status: {exec_status.status.value}")
                    print(f"     Progress: {exec_status.progress_percentage:.1f}% ({exec_status.current_step_index}/{exec_status.total_steps})")

                    if exec_status.current_step_name:
                        print(f"     Current Step: {exec_status.current_step_name}")

                # Get detailed status of the first execution
                first_exec_id = executions[0].execution_id
                print(f"\n3. Getting detailed status for: {first_exec_id[:24]}...")

                status = await client.get_execution_status(first_exec_id)

                print(f"\n   === Detailed Status ===")
                print(f"   Execution ID: {status.execution_id}")
                print(f"   Workflow: {status.workflow_name}")
                print(f"   Status: {status.status.value}")
                print(f"   Progress: {status.current_step_index}/{status.total_steps} ({status.progress_percentage:.1f}%)")

                if status.current_step_name:
                    print(f"   Current Step: {status.current_step_name}")

                if status.started_at:
                    print(f"   Started: {status.started_at}")

                if status.elapsed_seconds:
                    print(f"   Elapsed: {status.elapsed_seconds}s")

                if status.completed_steps:
                    print(f"\n   Completed Steps ({len(status.completed_steps)}):")
                    for step in status.completed_steps:
                        print(f"     - {step.step_name} ({step.status})")

                if status.sleep_info:
                    print(f"\n   💤 Sleeping:")
                    print(f"      Duration: {status.sleep_info.duration_ms}ms")
                    print(f"      Remaining: {status.sleep_info.remaining_ms}ms")

                if status.error:
                    print(f"\n   ❌ Error:")
                    print(f"      Kind: {status.error['kind']}")
                    print(f"      Message: {status.error['message']}")

            else:
                print("   ⚠️  No executions found")

        except Exception as e:
            print(f"   ❌ Error querying execution status: {e}")
            import traceback
            traceback.print_exc()

        # Wait for workflow to complete
        print("\n4. Waiting for workflow to complete...")
        result = await execution_task
        print(f"   ✅ Workflow completed!")
        print(f"   Execution ID: {result.execution_id}")
        print(f"   Final Output: {result.output}")

        # Query final status
        print("\n5. Querying final status...")
        final_status = await client.get_execution_status(result.execution_id)
        print(f"   Status: {final_status.status.value}")
        print(f"   Progress: {final_status.progress_percentage:.0f}%")

        if final_status.completed_at:
            print(f"   Completed: {final_status.completed_at}")

        client.close()

    finally:
        # Cleanup
        worker_task.cancel()
        try:
            await worker_task
        except asyncio.CancelledError:
            pass

    print("\n" + "=" * 60)
    print("✅ Test completed successfully!")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(run_test())

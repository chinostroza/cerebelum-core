#!/usr/bin/env python3
"""Example: Using ExecutionClient to query workflow status.

This example demonstrates how to use the ExecutionClient to:
1. Query the status of a specific execution
2. List all running executions
3. Monitor execution progress
4. Resume failed executions

Prerequisites:
- Cerebelum Core must be running on localhost:9090
- At least one workflow execution must have been started
"""

import asyncio
import time
from cerebelum import ExecutionClient, ExecutionState


async def example_get_status(client: ExecutionClient, execution_id: str):
    """Example: Get status of a specific execution."""
    print(f"\n=== Getting status for execution: {execution_id} ===")

    try:
        status = await client.get_execution_status(execution_id)

        print(f"Workflow: {status.workflow_name}")
        print(f"Status: {status.status.value}")
        print(f"Progress: {status.current_step_index}/{status.total_steps} ({status.progress_percentage:.1f}%)")
        print(f"Current Step: {status.current_step_name}")

        if status.started_at:
            print(f"Started: {status.started_at}")

        if status.elapsed_seconds:
            print(f"Elapsed: {status.elapsed_seconds}s")

        if status.completed_at:
            print(f"Completed: {status.completed_at}")

        if status.completed_steps:
            print(f"\nCompleted Steps ({len(status.completed_steps)}):")
            for step in status.completed_steps[:5]:  # Show first 5
                print(f"  - {step.step_name} ({step.status})")

        if status.sleep_info:
            print(f"\nSleeping:")
            print(f"  Duration: {status.sleep_info.duration_ms}ms")
            print(f"  Remaining: {status.sleep_info.remaining_ms}ms")

        if status.approval_info:
            print(f"\nWaiting for Approval:")
            print(f"  Type: {status.approval_info.approval_type}")
            if status.approval_info.timeout_ms:
                print(f"  Timeout: {status.approval_info.timeout_ms}ms")
                print(f"  Remaining: {status.approval_info.remaining_timeout_ms}ms")

        if status.error:
            print(f"\nError:")
            print(f"  Kind: {status.error['kind']}")
            print(f"  Message: {status.error['message']}")

        print("\n✅ Status retrieved successfully")

    except Exception as e:
        print(f"❌ Error getting status: {e}")


async def example_list_executions(client: ExecutionClient):
    """Example: List all executions with filtering."""
    print("\n=== Listing all executions ===")

    try:
        executions, total_count, has_more = await client.list_executions(limit=10)

        print(f"Found {total_count} total executions")
        print(f"Showing first {len(executions)} executions:")
        print()

        if not executions:
            print("  (no executions found)")
        else:
            for exec_status in executions:
                status_symbol = {
                    ExecutionState.RUNNING: "🔄",
                    ExecutionState.COMPLETED: "✅",
                    ExecutionState.FAILED: "❌",
                    ExecutionState.SLEEPING: "💤",
                    ExecutionState.WAITING_FOR_APPROVAL: "⏸️",
                }.get(exec_status.status, "❓")

                print(f"  {status_symbol} {exec_status.execution_id[:16]}... - {exec_status.workflow_name}")
                print(f"      Progress: {exec_status.progress_percentage:.1f}% ({exec_status.current_step_index}/{exec_status.total_steps})")

        if has_more:
            print(f"\n... and {total_count - len(executions)} more")

        print("\n✅ Executions listed successfully")

    except Exception as e:
        print(f"❌ Error listing executions: {e}")


async def example_list_running(client: ExecutionClient):
    """Example: List only running executions."""
    print("\n=== Listing running executions ===")

    try:
        executions, total_count, _ = await client.list_executions(
            status=ExecutionState.RUNNING,
            limit=20
        )

        print(f"Found {total_count} running execution(s)")

        for exec_status in executions:
            print(f"\n  🔄 {exec_status.workflow_name}")
            print(f"     ID: {exec_status.execution_id[:24]}...")
            print(f"     Current Step: {exec_status.current_step_name}")
            print(f"     Progress: {exec_status.progress_percentage:.1f}%")

        print("\n✅ Running executions listed successfully")

    except Exception as e:
        print(f"❌ Error listing running executions: {e}")


async def example_monitor_progress(client: ExecutionClient, execution_id: str, duration: int = 10):
    """Example: Monitor execution progress in real-time."""
    print(f"\n=== Monitoring execution progress for {duration}s ===")
    print(f"Execution ID: {execution_id}")
    print()

    start_time = time.time()

    try:
        while time.time() - start_time < duration:
            status = await client.get_execution_status(execution_id)

            # Clear line and print status
            print(f"\r  Status: {status.status.value:30} Progress: {status.progress_percentage:6.1f}% Step: {status.current_step_name:20}", end="", flush=True)

            if status.status in [ExecutionState.COMPLETED, ExecutionState.FAILED]:
                print()
                print(f"\n  Execution finished with status: {status.status.value}")
                break

            await asyncio.sleep(1)

        print()
        print("\n✅ Monitoring completed")

    except Exception as e:
        print(f"\n❌ Error monitoring execution: {e}")


async def example_resume_execution(client: ExecutionClient, execution_id: str):
    """Example: Resume a failed or paused execution."""
    print(f"\n=== Resuming execution: {execution_id} ===")

    try:
        # First check the status
        status = await client.get_execution_status(execution_id)
        print(f"Current status: {status.status.value}")

        if status.status == ExecutionState.COMPLETED:
            print("⚠️  Execution is already completed, cannot resume")
            return

        if status.status == ExecutionState.RUNNING:
            print("⚠️  Execution is already running")
            return

        # Resume the execution
        result_status = await client.resume_execution(execution_id)

        if result_status == "resumed":
            print("✅ Execution resumed successfully")
        elif result_status == "already_running":
            print("⚠️  Execution was already running")
        else:
            print(f"❌ Failed to resume: {result_status}")

    except Exception as e:
        print(f"❌ Error resuming execution: {e}")


async def main():
    """Main example function."""
    print("=" * 60)
    print("Cerebelum ExecutionClient Examples")
    print("=" * 60)

    # Initialize the client
    client = ExecutionClient(core_url="localhost:9090")

    try:
        # Example 1: List all executions
        await example_list_executions(client)

        # Example 2: List only running executions
        await example_list_running(client)

        # Get the first execution ID for further examples
        executions, _, _ = await client.list_executions(limit=1)

        if executions:
            execution_id = executions[0].execution_id

            # Example 3: Get status of a specific execution
            await example_get_status(client, execution_id)

            # Example 4: Monitor progress (if execution is running)
            if executions[0].status == ExecutionState.RUNNING:
                await example_monitor_progress(client, execution_id, duration=5)

            # Example 5: Resume execution (if execution is failed/paused)
            if executions[0].status in [ExecutionState.FAILED, ExecutionState.SLEEPING]:
                await example_resume_execution(client, execution_id)

        else:
            print("\n⚠️  No executions found. Start a workflow first:")
            print("     python3 07_distributed_server.py")

    finally:
        # Close the client
        client.close()

    print("\n" + "=" * 60)
    print("Examples completed!")
    print("=" * 60)


if __name__ == "__main__":
    # Run the examples
    asyncio.run(main())

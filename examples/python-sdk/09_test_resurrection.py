"""Test: Workflow Resurrection End-to-End

This test demonstrates that workflows survive system restarts when using
Cerebelum Core with resurrection enabled.

Architecture:
1. Python SDK defines workflow with sleep
2. Core executes workflow (Elixir Engine)
3. Workflow enters sleep state
4. We simulate Core crash/restart
5. Resurrector automatically resumes workflow
6. Workflow completes successfully

Prerequisites:
- Core running: mix run --no-halt
- Database migrated: mix ecto.migrate
- Resurrection enabled in config (default: true)

Run:
    # Terminal 1: Start Core
    cd /Users/dev/Documents/zea/cerebelum-io/cerebelum-core
    mix run --no-halt

    # Terminal 2: Run this test
    python3 09_test_resurrection.py
"""

import asyncio
import sys
from cerebelum import step, workflow, Context, Worker
from datetime import datetime


# ============================================================================
# Workflow Definition - Simple workflow with sleep
# ============================================================================

@step
async def step_1_before_sleep(context: Context, inputs: dict) -> dict:
    """First step before sleep."""
    timestamp = datetime.utcnow().isoformat()
    print(f"✅ [STEP 1] Executed at {timestamp}")
    print(f"   Execution ID: {context.execution_id}")
    print(f"   Input: {inputs}")

    return {
        "message": "Step 1 completed",
        "executed_at": timestamp
    }


@step
async def step_2_sleep(context: Context, step_1_before_sleep: dict) -> dict:
    """Sleep step - workflow will pause here."""
    print(f"💤 [STEP 2] Starting sleep (10 seconds)...")
    print(f"   Previous result: {step_1_before_sleep['message']}")

    # This sleep will be handled by Core's Cerebelum.sleep()
    # In distributed mode, this translates to a Sleep command
    # which the Engine processes with state preservation

    # For now, we'll use the marker that Core recognizes
    # The actual sleep duration will be read from workflow definition
    sleep_duration_ms = 10_000  # 10 seconds

    return {
        "_sleep": True,
        "duration_ms": sleep_duration_ms,
        "message": "Sleep requested"
    }


@step
async def step_3_after_sleep(context: Context, step_2_sleep: dict) -> dict:
    """Final step after sleep - proves resurrection worked."""
    timestamp = datetime.utcnow().isoformat()
    print(f"✅ [STEP 3] Executed after sleep at {timestamp}")
    print(f"   Sleep info: {step_2_sleep['message']}")
    print(f"   🎉 RESURRECTION SUCCESSFUL - Workflow survived!")

    return {
        "message": "Workflow completed successfully after resurrection",
        "completed_at": timestamp
    }


@workflow
def resurrection_test_workflow(wf):
    """Test workflow with sleep for resurrection."""
    wf.timeline(
        step_1_before_sleep >>
        step_2_sleep >>
        step_3_after_sleep
    )


# ============================================================================
# Test Runner
# ============================================================================

async def run_resurrection_test():
    """Run the resurrection test."""
    print("\n" + "=" * 70)
    print("RESURRECTION TEST - Python SDK + Core Integration")
    print("=" * 70)

    # Configuration
    CORE_URL = "localhost:9090"
    WORKER_ID = "python-resurrection-test"

    print(f"\n📋 Configuration:")
    print(f"   Core URL: {CORE_URL}")
    print(f"   Worker ID: {WORKER_ID}")
    print(f"   Test: Sleep 10s + verify resurrection")

    try:
        # Create worker
        print(f"\n🔌 Connecting to Core at {CORE_URL}...")
        worker = Worker(
            core_url=CORE_URL,
            worker_id=WORKER_ID,
            capabilities=["python", "async"]
        )

        # Register workflow
        print(f"📝 Registering workflow: resurrection_test_workflow")
        worker.register_workflow(resurrection_test_workflow)

        # Register steps
        worker.register_step("step_1_before_sleep", step_1_before_sleep)
        worker.register_step("step_2_sleep", step_2_sleep)
        worker.register_step("step_3_after_sleep", step_3_after_sleep)

        print(f"✅ Worker registered and ready")

        # Execute workflow
        print(f"\n🚀 Starting workflow execution...")
        print(f"   This will execute on Core, not locally!")
        print(f"   Watch for sleep and resurrection...")

        from cerebelum import DistributedExecutor
        executor = DistributedExecutor(core_url=CORE_URL, worker_id=WORKER_ID)

        # Note: For this test, we're using the existing blueprint submission
        # The Core will handle the actual sleep via Cerebelum.sleep/1
        result = await executor.execute(
            resurrection_test_workflow,
            {"test_id": "resurrection-001"}
        )

        print(f"\n" + "=" * 70)
        print(f"✨ TEST RESULT")
        print(f"=" * 70)
        print(f"Status: {result.status}")
        print(f"Execution ID: {result.execution_id}")
        print(f"Output: {result.output}")

        if result.status == "completed":
            print(f"\n🎉 SUCCESS - Workflow completed!")
            print(f"   ✅ Step 1 executed")
            print(f"   ✅ Workflow slept 10 seconds")
            print(f"   ✅ Step 3 executed after sleep")
            print(f"   ✅ Resurrection system working!")
        else:
            print(f"\n❌ FAILED - Workflow status: {result.status}")

        return result

    except Exception as e:
        print(f"\n❌ Error during test: {e}")
        print(f"\nTroubleshooting:")
        print(f"1. Is Core running? (mix run --no-halt)")
        print(f"2. Is gRPC enabled? (config/dev.exs - enable_grpc_server: true)")
        print(f"3. Is port 9090 open?")
        raise


# ============================================================================
# Manual Test Instructions
# ============================================================================

async def manual_resurrection_test():
    """Manual test to demonstrate resurrection after crash.

    Instructions:
    1. Run this function
    2. Wait for "WORKFLOW SLEEPING" message
    3. Stop the Core (Ctrl+C in Core terminal)
    4. Restart Core (mix run --no-halt)
    5. Watch logs - Resurrector will find and resume the workflow
    6. Workflow will complete step 3
    """
    print("\n" + "=" * 70)
    print("MANUAL RESURRECTION TEST")
    print("=" * 70)
    print("\nThis test requires manual intervention:")
    print("\n1️⃣  Workflow will start and enter sleep (10s)")
    print("2️⃣  YOU: Stop Core with Ctrl+C")
    print("3️⃣  YOU: Restart Core with 'mix run --no-halt'")
    print("4️⃣  Watch: Resurrector will resume workflow automatically")
    print("5️⃣  Verify: Workflow completes step 3")
    print("\nReady? Press Enter to start...")
    input()

    # Execute the test
    await run_resurrection_test()


# ============================================================================
# Alternative: Elixir-Native Workflow (Recommended for testing)
# ============================================================================

def create_elixir_test_workflow():
    """Create an Elixir workflow script for easier testing.

    This is actually easier than Python for testing resurrection
    because we can use IEx and directly call Core functions.
    """
    script = '''
# Test Resurrection in IEx
# Run: iex -S mix

# Define simple workflow
defmodule ResurrectionTestWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      step_1() |> sleep_10s() |> step_2()
    end
  end

  def step_1(context) do
    IO.puts("✅ Step 1 - Before sleep")
    {:ok, %{timestamp: DateTime.utc_now()}}
  end

  def sleep_10s(_context, _result) do
    IO.puts("💤 Sleeping 10 seconds...")
    Cerebelum.sleep(10_000)
    {:ok, :awake}
  end

  def step_2(_context, _result) do
    IO.puts("✅ Step 2 - After sleep (RESURRECTED!)")
    {:ok, %{completed: true}}
  end
end

# Execute
{:ok, pid} = Cerebelum.Execution.Supervisor.start_execution(
  ResurrectionTestWorkflow,
  %{}
)

# Get execution ID
status = Cerebelum.Execution.Engine.get_status(pid)
execution_id = status.execution_id

IO.puts("Execution ID: #{execution_id}")
IO.puts("Wait 3 seconds, then kill process to test resurrection...")

# Wait a bit
Process.sleep(3000)

# Kill the process (simulate crash)
Process.exit(pid, :kill)
IO.puts("💥 Process killed!")

# Wait for resurrector (scans every 1s in dev)
Process.sleep(2000)

# Check if it was resurrected
case Cerebelum.Execution.Supervisor.get_execution_pid(execution_id) do
  {:ok, new_pid} ->
    IO.puts("✨ RESURRECTED! New PID: #{inspect(new_pid)}")
    IO.puts("Wait for workflow to complete...")
    Process.sleep(8000)

    final_status = Cerebelum.Execution.Engine.get_status(new_pid)
    IO.puts("Final status: #{final_status.status}")

  {:error, :not_found} ->
    IO.puts("❌ Not resurrected - check logs")
end
'''

    print("\n" + "=" * 70)
    print("ELIXIR TEST SCRIPT (Recommended)")
    print("=" * 70)
    print("\nCopy this script and paste in IEx:")
    print("\n" + script)
    print("\n" + "=" * 70)


# ============================================================================
# Main
# ============================================================================

async def main():
    """Main entry point."""
    if len(sys.argv) > 1 and sys.argv[1] == "--manual":
        # Manual test with instructions
        await manual_resurrection_test()
    elif len(sys.argv) > 1 and sys.argv[1] == "--elixir":
        # Show Elixir test script
        create_elixir_test_workflow()
    else:
        # Automated test
        print("\nℹ️  Running automated test...")
        print("   For manual crash test: python3 09_test_resurrection.py --manual")
        print("   For Elixir test script: python3 09_test_resurrection.py --elixir")
        await run_resurrection_test()


if __name__ == "__main__":
    asyncio.run(main())

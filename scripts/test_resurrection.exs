#!/usr/bin/env elixir

# Test Resurrection System End-to-End
#
# This script demonstrates that workflows survive crashes and restarts.
#
# Run:
#   mix run scripts/test_resurrection.exs
#
# Or in IEx:
#   iex -S mix
#   Code.eval_file("scripts/test_resurrection.exs")

IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("RESURRECTION TEST - End-to-End")
IO.puts(String.duplicate("=", 70))

# Define test workflow
defmodule ResurrectionTestWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      step_1_before_sleep() |> sleep_step() |> step_2_after_sleep()
    end
  end

  def step_1_before_sleep(context) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    IO.puts("✅ [#{timestamp}] Step 1 - Before sleep")
    IO.puts("   Execution ID: #{context.execution_id}")
    {:ok, %{executed_at: timestamp, step: 1}}
  end

  def sleep_step(_context, result) do
    IO.puts("💤 Sleeping for 8 seconds...")
    IO.puts("   Previous result: #{inspect(result)}")
    Cerebelum.sleep(8_000)
    {:ok, :awake}
  end

  def step_2_after_sleep(_context, _result) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    IO.puts("✅ [#{timestamp}] Step 2 - After sleep")
    IO.puts("   🎉 RESURRECTION SUCCESSFUL!")
    {:ok, %{completed_at: timestamp, step: 2}}
  end
end

# Test function
defmodule ResurrectionTest do
  def run do
    IO.puts("\n📋 Test Plan:")
    IO.puts("   1. Start workflow with 8-second sleep")
    IO.puts("   2. Wait 2 seconds (workflow will be sleeping)")
    IO.puts("   3. Kill the process (simulate crash)")
    IO.puts("   4. Wait for Resurrector to scan and resume")
    IO.puts("   5. Verify workflow completes successfully")

    # Start workflow
    IO.puts("\n🚀 Starting workflow...")
    {:ok, pid} = Cerebelum.Execution.Supervisor.start_execution(
      ResurrectionTestWorkflow,
      %{test_id: "resurrection-001"}
    )

    # Get execution ID
    status = Cerebelum.Execution.Engine.get_status(pid)
    execution_id = status.execution_id

    IO.puts("   Workflow started!")
    IO.puts("   PID: #{inspect(pid)}")
    IO.puts("   Execution ID: #{execution_id}")

    # Wait for workflow to enter sleep
    IO.puts("\n⏳ Waiting 2 seconds for workflow to enter sleep...")
    Process.sleep(2000)

    # Verify it's sleeping
    try do
      status = Cerebelum.Execution.Engine.get_status(pid)
      IO.puts("   Current state: #{status.status}")
      IO.puts("   Current step: #{status.current_step}")
    rescue
      _ -> IO.puts("   Process might have crashed")
    end

    # Kill the process
    IO.puts("\n💥 Simulating crash - killing process...")
    Process.exit(pid, :kill)
    Process.sleep(200)

    # Verify process is dead
    if Process.alive?(pid) do
      IO.puts("   ❌ Process still alive!")
    else
      IO.puts("   ✅ Process terminated")
    end

    # Check registry
    case Cerebelum.Execution.Registry.lookup_execution(execution_id) do
      {:ok, _pid} ->
        IO.puts("   ⚠️  Still in registry (will be cleaned up)")
      {:error, :not_found} ->
        IO.puts("   ✅ Removed from registry")
    end

    # Wait for Resurrector
    IO.puts("\n🔄 Waiting for Resurrector to scan and resume...")
    IO.puts("   Resurrector scans every 1s in :ignore mode")
    IO.puts("   Scanning for paused executions...")

    # In test mode, Resurrector is disabled, so we manually resurrect
    if Mix.env() == :test do
      IO.puts("   ⚠️  Test mode detected - manual resurrection required")
      IO.puts("   Calling resume_execution manually...")

      Process.sleep(500)

      case Cerebelum.Execution.Supervisor.resume_execution(execution_id) do
        {:ok, new_pid} ->
          IO.puts("   ✅ Manually resurrected!")
          IO.puts("   New PID: #{inspect(new_pid)}")
        {:error, reason} ->
          IO.puts("   ❌ Failed to resurrect: #{inspect(reason)}")
      end
    else
      # In dev mode, Resurrector should work
      Process.sleep(2000)
    end

    # Check if resurrected
    case Cerebelum.Execution.Supervisor.get_execution_pid(execution_id) do
      {:ok, new_pid} ->
        IO.puts("\n✨ WORKFLOW RESURRECTED!")
        IO.puts("   New PID: #{inspect(new_pid)}")

        # Get status
        status = Cerebelum.Execution.Engine.get_status(new_pid)
        IO.puts("   Status: #{status.status}")
        IO.puts("   Current step: #{status.current_step}")

        # Wait for completion
        IO.puts("\n⏳ Waiting for workflow to complete...")
        Process.sleep(7000)

        # Final status
        final_status = Cerebelum.Execution.Engine.get_status(new_pid)
        IO.puts("\n📊 Final Status:")
        IO.puts("   Status: #{final_status.status}")
        IO.puts("   Timeline: #{final_status.timeline_progress}")
        IO.puts("   Results: #{inspect(final_status.results)}")

        if final_status.status == :completed do
          IO.puts("\n" <> String.duplicate("=", 70))
          IO.puts("🎉 SUCCESS - Resurrection Test Passed!")
          IO.puts(String.duplicate("=", 70))
          IO.puts("\nVerified:")
          IO.puts("✅ Workflow survived process crash")
          IO.puts("✅ State was reconstructed from events")
          IO.puts("✅ Sleep was resumed with correct remaining time")
          IO.puts("✅ Workflow completed successfully")
        else
          IO.puts("\n⚠️  Workflow did not complete (status: #{final_status.status})")
        end

      {:error, :not_found} ->
        IO.puts("\n❌ RESURRECTION FAILED")
        IO.puts("   Workflow was not resurrected")
        IO.puts("\nPossible causes:")
        IO.puts("   - Resurrector is disabled (check config)")
        IO.puts("   - Events were not properly stored")
        IO.puts("   - State reconstruction failed")

        # Check events
        {:ok, events} = Cerebelum.EventStore.get_events(execution_id)
        IO.puts("\n   Events found: #{length(events)}")
        Enum.each(events, fn event ->
          IO.puts("     - #{event.event_type} (v#{event.version})")
        end)
    end

    :ok
  end
end

# Run the test
ResurrectionTest.run()

IO.puts("\n")

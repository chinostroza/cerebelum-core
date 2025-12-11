#!/usr/bin/env elixir

# Simple Resurrection Test
#
# This demonstrates workflow resurrection in the simplest possible way.
#
# Run:   mix run scripts/simple_resurrection_test.exs

IO.puts("\n#{IO.ANSI.cyan()}╔════════════════════════════════════════════════╗")
IO.puts("║  SIMPLE RESURRECTION TEST                     ║")
IO.puts("╚════════════════════════════════════════════════╝#{IO.ANSI.reset()}\n")

# Define workflow
defmodule SimpleResurrectionWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      before_sleep() |> after_sleep()
    end
  end

  def before_sleep(context) do
    IO.puts("✅ Step 1: Before sleep (#{context.execution_id})")
    # Return sleep tuple - this triggers the Engine's sleep mechanism
    # which emits SleepStartedEvent and enables resurrection
    {:sleep, [milliseconds: 10_000], {:ok, :will_sleep}}
  end

  def after_sleep(_context, _result) do
    IO.puts("✅ Step 2: After sleep - RESURRECTED!")
    {:ok, :completed}
  end
end

# Execute
IO.puts("🚀 Starting workflow with 10-second sleep...")
{:ok, pid} = Cerebelum.Execution.Supervisor.start_execution(SimpleResurrectionWorkflow, %{})
status = Cerebelum.Execution.Engine.get_status(pid)
execution_id = status.execution_id

IO.puts("   Execution ID: #{execution_id}")
IO.puts("   PID: #{inspect(pid)}")

# Wait a bit for workflow to start sleeping
IO.puts("\n⏳ Waiting 2 seconds for workflow to enter sleep...")
Process.sleep(2000)

# Kill the process
IO.puts("\n💥 Killing process (simulating crash)...")
Process.exit(pid, :kill)
Process.sleep(100)

if Process.alive?(pid) do
  IO.puts("   ❌ Process still alive!")
else
  IO.puts("   ✅ Process killed")
end

# Manually resurrect (since Resurrector is disabled in dev for this test)
IO.puts("\n🔄 Resurrecting workflow manually...")
case Cerebelum.Execution.Supervisor.resume_execution(execution_id) do
  {:ok, new_pid} ->
    IO.puts("   ✅ Resurrected! New PID: #{inspect(new_pid)}")

    # Wait for completion (sleep duration + buffer)
    IO.puts("\n⏳ Waiting for workflow to complete...")
    Process.sleep(9000)  # Wait for remaining sleep + step execution

    # Check final status
    final_status = if Process.alive?(new_pid) do
      status = Cerebelum.Execution.Engine.get_status(new_pid)
      IO.puts("\n📊 Final Status: #{status.state}")
      status
    else
      IO.puts("\n📊 Process no longer alive (may have completed)")
      # Check events to see final state
      {:ok, events} = Cerebelum.EventStore.get_events(execution_id)
      last_event = List.last(events)
      IO.puts("   Last event: #{last_event.event_type}")
      state = if(last_event.event_type == "ExecutionCompletedEvent", do: :completed, else: :unknown)
      %{state: state}
    end

    if final_status.state == :completed do
      IO.puts("\n#{IO.ANSI.green()}╔════════════════════════════════════════════════╗")
      IO.puts("║  ✨ SUCCESS - RESURRECTION WORKS!              ║")
      IO.puts("╚════════════════════════════════════════════════╝#{IO.ANSI.reset()}\n")
    else
      IO.puts("\n⚠️  Workflow state: #{final_status.state}")
    end

  {:error, reason} ->
    IO.puts("   ❌ Failed: #{inspect(reason)}")

    # Check events
    {:ok, events} = Cerebelum.EventStore.get_events(execution_id)
    IO.puts("\n   Events (#{length(events)}):")
    Enum.each(events, fn e -> IO.puts("     - #{e.event_type}") end)
end

IO.puts("\n")

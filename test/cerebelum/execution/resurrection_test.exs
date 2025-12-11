defmodule Cerebelum.Execution.ResurrectionTest do
  @moduledoc """
  Tests for workflow resurrection capabilities.

  These tests verify that workflows can survive system restarts by
  reconstructing their state from events and resuming execution.
  """

  use ExUnit.Case, async: false

  alias Cerebelum.Execution.{Engine, Supervisor, Registry, StateReconstructor}
  alias Cerebelum.EventStore
  alias Cerebelum.Repo

  setup do
    # Checkout sandbox connection for test isolation
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Allow all relevant processes to use the sandbox
    allow_sandbox_access()

    # Clean up events table before each test
    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE TABLE events CASCADE", [])

    :ok
  end

  defp allow_sandbox_access do
    processes = [
      Process.whereis(Cerebelum.EventStore),
      Process.whereis(Cerebelum.Execution.Supervisor),
      Process.whereis(Cerebelum.Execution.Registry),
      Process.whereis(Cerebelum.Execution.Resurrector)
    ]

    Enum.each(processes, fn pid ->
      if pid, do: Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    end)
  end

  # Test workflows

  defmodule SimpleSleepWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        start() |> sleep_step() |> finish()
      end
    end

    def start(_ctx), do: {:ok, :started}

    def sleep_step(_ctx, {:ok, _}) do
      # Sleep for 2 seconds
      {:sleep, [seconds: 2], {:ok, :sleeping}}
    end

    def finish(_ctx, {:ok, _}, {:ok, _}), do: {:ok, :completed}
  end

  defmodule QuickSleepWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        start() |> quick_sleep() |> finish()
      end
    end

    def start(_ctx), do: {:ok, :started}

    def quick_sleep(_ctx, {:ok, _}) do
      # Sleep for 50ms (short enough to complete during test)
      {:sleep, [milliseconds: 50], {:ok, :slept}}
    end

    def finish(_ctx, {:ok, _}, {:ok, _}), do: {:ok, :done}
  end

  defmodule SimpleWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        step1() |> step2() |> step3()
      end
    end

    def step1(_ctx), do: {:ok, 1}
    def step2(_ctx, {:ok, _}), do: {:ok, 2}
    def step3(_ctx, {:ok, _}, {:ok, _}), do: {:ok, 3}
  end

  describe "Registry integration" do
    test "execution is registered on start" do
      {:ok, pid} = Supervisor.start_execution(SimpleWorkflow, %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Verify registration
      assert {:ok, ^pid} = Registry.lookup_execution(execution_id)
    end

    test "execution is automatically unregistered on termination" do
      {:ok, pid} = Supervisor.start_execution(QuickSleepWorkflow, %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Verify registered
      assert {:ok, ^pid} = Registry.lookup_execution(execution_id)

      # Wait for workflow to complete
      Process.sleep(200)
      EventStore.flush()

      # Give time for process to terminate
      Process.sleep(100)

      # Verify unregistered (process died)
      assert {:error, :not_found} = Registry.lookup_execution(execution_id)
    end

    test "prevents duplicate executions" do
      # Start first execution
      {:ok, pid1} = Supervisor.start_execution(SimpleSleepWorkflow, %{})
      status = Engine.get_status(pid1)
      execution_id = status.execution_id

      # Try to resume while still running
      assert {:error, :already_running} = Supervisor.resume_execution(execution_id)
    end
  end

  describe "State reconstruction" do
    test "reconstructs simple workflow state" do
      # Start and wait for workflow to execute a few steps
      {:ok, pid} = Supervisor.start_execution(SimpleWorkflow, %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(200)
      EventStore.flush()
      Process.sleep(100)

      # Reconstruct state
      assert {:ok, engine_data} = StateReconstructor.reconstruct_to_engine_data(execution_id)

      # Verify basic state
      assert engine_data.context.execution_id == execution_id
      assert engine_data.context.workflow_module == SimpleWorkflow
      assert map_size(engine_data.results) > 0
    end

    test "reconstructs sleep state correctly" do
      # Start workflow with sleep
      {:ok, pid} = Supervisor.start_execution(SimpleSleepWorkflow, %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for sleep to start
      Process.sleep(150)
      EventStore.flush()

      # Verify sleeping
      status = Engine.get_status(pid)
      assert status.state == :sleeping

      # Reconstruct state
      assert {:ok, engine_data} = StateReconstructor.reconstruct_to_engine_data(execution_id)

      # Verify sleep state is captured
      assert engine_data.sleep_duration_ms != nil
      assert engine_data.sleep_started_at != nil
      assert engine_data.sleep_step_name == :sleep_step
    end
  end

  describe "Resume execution" do
    test "resumes sleeping workflow with remaining time" do
      # Start workflow
      {:ok, pid} = Supervisor.start_execution(SimpleSleepWorkflow, %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for sleep to start
      Process.sleep(150)
      EventStore.flush()

      # Verify sleeping
      status = Engine.get_status(pid)
      assert status.state == :sleeping

      # Kill the process to simulate crash/restart
      Process.exit(pid, :kill)
      Process.sleep(100)

      # Verify unregistered
      assert {:error, :not_found} = Registry.lookup_execution(execution_id)

      # Allow sandbox for new process
      allow_sandbox_access()

      # Resume execution
      assert {:ok, new_pid} = Supervisor.resume_execution(execution_id)
      assert new_pid != pid

      # Verify re-registered
      assert {:ok, ^new_pid} = Registry.lookup_execution(execution_id)

      # Verify resumed in sleeping state
      status = Engine.get_status(new_pid)
      assert status.state == :sleeping
      assert status.execution_id == execution_id
    end

    test "resumes workflow with already elapsed sleep time" do
      # Start workflow with short sleep
      {:ok, pid} = Supervisor.start_execution(QuickSleepWorkflow, %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for sleep to start
      Process.sleep(50)
      EventStore.flush()

      # Kill process
      Process.exit(pid, :kill)

      # Wait for sleep time to elapse
      Process.sleep(100)

      # Allow sandbox for new process
      allow_sandbox_access()

      # Resume - should wake immediately and continue
      assert {:ok, new_pid} = Supervisor.resume_execution(execution_id)

      # Should resume and quickly complete
      Process.sleep(200)
      EventStore.flush()
      Process.sleep(100)

      # Verify completed
      assert {:error, :not_found} = Registry.lookup_execution(execution_id)

      # Verify events show completion
      {:ok, events} = EventStore.get_events(execution_id)
      event_types = Enum.map(events, & &1.event_type)
      assert "ExecutionCompletedEvent" in event_types
    end

    test "cannot resume completed workflow" do
      # Start simple workflow
      {:ok, pid} = Supervisor.start_execution(SimpleWorkflow, %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(200)
      EventStore.flush()
      Process.sleep(100)

      # Try to resume
      assert {:error, :not_resumable} = Supervisor.resume_execution(execution_id)
    end

    test "cannot resume non-existent workflow" do
      assert {:error, :not_found} = Supervisor.resume_execution("non-existent-id")
    end
  end

  describe "Concurrent resume protection" do
    test "prevents concurrent resume of same execution" do
      # Start workflow
      {:ok, pid} = Supervisor.start_execution(SimpleSleepWorkflow, %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for sleep
      Process.sleep(150)
      EventStore.flush()

      # First resume attempt while still running
      assert {:error, :already_running} = Supervisor.resume_execution(execution_id)

      # Kill original process
      Process.exit(pid, :kill)
      Process.sleep(100)

      # Allow sandbox for new processes
      allow_sandbox_access()

      # Resume successfully
      assert {:ok, new_pid1} = Supervisor.resume_execution(execution_id)

      # Second concurrent resume should fail
      assert {:error, :already_running} = Supervisor.resume_execution(execution_id)

      # Verify only one process registered
      assert {:ok, ^new_pid1} = Registry.lookup_execution(execution_id)
    end
  end

  describe "get_execution_pid/1" do
    test "returns pid for running execution" do
      {:ok, pid} = Supervisor.start_execution(SimpleSleepWorkflow, %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      assert {:ok, ^pid} = Supervisor.get_execution_pid(execution_id)
    end

    test "returns error for non-existent execution" do
      assert {:error, :not_found} = Supervisor.get_execution_pid("unknown-id")
    end

    test "returns error after execution completes" do
      {:ok, pid} = Supervisor.start_execution(QuickSleepWorkflow, %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(300)
      EventStore.flush()

      assert {:error, :not_found} = Supervisor.get_execution_pid(execution_id)
    end
  end

  describe "Resurrector" do
    test "finds paused executions" do
      # Start a sleeping workflow
      {:ok, pid} = Supervisor.start_execution(SimpleSleepWorkflow, %{})
      status = Engine.get_status(pid)
      _execution_id = status.execution_id

      # Wait for sleep to start
      Process.sleep(150)
      EventStore.flush()

      # Kill the process
      Process.exit(pid, :kill)
      Process.sleep(100)

      # Trigger manual resurrection
      # Note: We don't test automatic resurrection on boot here as it's
      # complex to test in the test environment. Manual trigger tests
      # the same logic.
      allow_sandbox_access()
      {:ok, stats} = Cerebelum.Execution.Resurrector.resurrect_all()

      # Should have found and resurrected the workflow
      assert stats.total >= 1
      assert stats.success >= 1
    end
  end
end

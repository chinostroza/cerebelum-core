defmodule Cerebelum.Execution.SleepTest do
  use ExUnit.Case, async: false

  alias Cerebelum.Execution.Engine
  alias Cerebelum.EventStore
  alias Cerebelum.Repo

  setup do
    # Checkout sandbox connection for test isolation
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Allow EventStore GenServer to use the sandbox connection
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), Process.whereis(Cerebelum.EventStore))

    # Clean up events table before each test
    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE TABLE events CASCADE", [])

    :ok
  end

  defmodule SleepWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        start() |> wait_a_bit() |> finish()
      end
    end

    def start(_ctx) do
      {:ok, %{started_at: DateTime.utc_now()}}
    end

    def wait_a_bit(_ctx, {:ok, start_data}) do
      # Sleep for 100ms
      {:sleep, [milliseconds: 100], {:ok, %{waiting: true, start_data: start_data}}}
    end

    def finish(_ctx, _start, {:ok, wait_data}) do
      {:ok, %{finished: true, waited: true, wait_data: wait_data}}
    end
  end

  defmodule MultipleSleepsWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        step1() |> sleep1() |> step2() |> sleep2() |> step3()
      end
    end

    def step1(_ctx), do: {:ok, 1}
    def sleep1(_ctx, {:ok, _}), do: {:sleep, [milliseconds: 50], {:ok, :slept1}}
    def step2(_ctx, {:ok, _}, {:ok, _}), do: {:ok, 2}
    def sleep2(_ctx, {:ok, _}, {:ok, _}, {:ok, _}), do: {:sleep, [milliseconds: 50], {:ok, :slept2}}
    # step3 receives: ctx, step1, sleep1, step2, sleep2 (5 args)
    def step3(_ctx, {:ok, _}, {:ok, _}, {:ok, _}, {:ok, _}), do: {:ok, 3}
  end

  defmodule SecondsSleepWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        start() |> sleep_seconds() |> finish()
      end
    end

    def start(_ctx), do: {:ok, :started}

    def sleep_seconds(_ctx, {:ok, _}) do
      # Sleep for 1 second using :seconds option
      {:sleep, [seconds: 1], {:ok, :sleeping}}
    end

    def finish(_ctx, {:ok, _}, {:ok, _}), do: {:ok, :done}
  end

  describe "sleep execution" do
    test "workflow sleeps for specified milliseconds" do
      # Start workflow
      {:ok, pid} = Engine.start_link(workflow_module: SleepWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Immediately check - should be executing
      Process.sleep(10)
      status = Engine.get_status(pid)
      assert status.state in [:executing_step, :sleeping]

      # Wait for sleep to complete
      Process.sleep(150)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Should be completed
      status = Engine.get_status(pid)
      assert status.state == :completed

      # Verify results
      assert Map.has_key?(status.results, :finish)
      {:ok, finish_result} = status.results.finish
      assert finish_result.finished == true
      assert finish_result.waited == true

      # Check events
      {:ok, events} = EventStore.get_events(execution_id)

      sleep_started = Enum.find(events, fn e -> e.event_type == "SleepStartedEvent" end)
      assert sleep_started != nil
      assert sleep_started.event_data["duration_ms"] == 100

      sleep_completed = Enum.find(events, fn e -> e.event_type == "SleepCompletedEvent" end)
      assert sleep_completed != nil
      # Should have actually slept around 100ms
      assert sleep_completed.event_data["actual_duration_ms"] >= 90
      assert sleep_completed.event_data["actual_duration_ms"] <= 150
    end

    test "multiple sleeps in sequence" do
      # Start workflow
      {:ok, pid} = Engine.start_link(workflow_module: MultipleSleepsWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(250)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Should be completed
      status = Engine.get_status(pid)
      assert status.state == :completed

      # Check all steps completed
      assert Map.has_key?(status.results, :step1)
      assert Map.has_key?(status.results, :sleep1)
      assert Map.has_key?(status.results, :step2)
      assert Map.has_key?(status.results, :sleep2)
      assert Map.has_key?(status.results, :step3)

      # Check events
      {:ok, events} = EventStore.get_events(execution_id)

      sleep_events = Enum.filter(events, fn e ->
        e.event_type in ["SleepStartedEvent", "SleepCompletedEvent"]
      end)

      # Should have 2 sleep started and 2 sleep completed
      sleep_started_events = Enum.filter(sleep_events, fn e -> e.event_type == "SleepStartedEvent" end)
      sleep_completed_events = Enum.filter(sleep_events, fn e -> e.event_type == "SleepCompletedEvent" end)

      assert length(sleep_started_events) == 2
      assert length(sleep_completed_events) == 2
    end

    test "sleep with seconds option" do
      # Start workflow
      {:ok, pid} = Engine.start_link(workflow_module: SecondsSleepWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Should be sleeping or executing
      Process.sleep(100)
      status = Engine.get_status(pid)
      assert status.state in [:executing_step, :sleeping]

      # Wait for completion (1 second + overhead)
      Process.sleep(1100)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Should be completed
      status = Engine.get_status(pid)
      assert status.state == :completed

      # Check events
      {:ok, events} = EventStore.get_events(execution_id)

      sleep_started = Enum.find(events, fn e -> e.event_type == "SleepStartedEvent" end)
      assert sleep_started != nil
      # 1 second = 1000ms
      assert sleep_started.event_data["duration_ms"] == 1000
    end

    test "status during sleep shows sleep information" do
      # Start workflow
      {:ok, pid} = Engine.start_link(workflow_module: SleepWorkflow, inputs: %{})

      # Wait a bit to enter sleep state
      Process.sleep(50)

      # Get status while sleeping
      status = Engine.get_status(pid)

      if status.state == :sleeping do
        # Should have sleep information
        assert Map.has_key?(status, :sleep_duration_ms)
        assert Map.has_key?(status, :sleep_elapsed_ms)
        assert Map.has_key?(status, :sleep_remaining_ms)

        assert status.sleep_duration_ms == 100
        assert status.sleep_elapsed_ms > 0
        assert status.sleep_remaining_ms > 0
        assert status.sleep_remaining_ms < 100
      end

      # Wait for completion
      Process.sleep(200)
      EventStore.flush()
      Process.sleep(50)

      # Should be completed now
      status = Engine.get_status(pid)
      assert status.state == :completed
    end

    test "multiple executions can sleep concurrently" do
      # Start 3 executions
      {:ok, pid1} = Engine.start_link(workflow_module: SleepWorkflow, inputs: %{})
      {:ok, pid2} = Engine.start_link(workflow_module: SleepWorkflow, inputs: %{})
      {:ok, pid3} = Engine.start_link(workflow_module: SleepWorkflow, inputs: %{})

      status1 = Engine.get_status(pid1)
      status2 = Engine.get_status(pid2)
      status3 = Engine.get_status(pid3)

      # Wait for all to complete
      Process.sleep(250)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # All should complete
      final1 = Engine.get_status(pid1)
      final2 = Engine.get_status(pid2)
      final3 = Engine.get_status(pid3)

      assert final1.state == :completed
      assert final2.state == :completed
      assert final3.state == :completed

      # Verify events for all executions
      {:ok, events1} = EventStore.get_events(status1.execution_id)
      {:ok, events2} = EventStore.get_events(status2.execution_id)
      {:ok, events3} = EventStore.get_events(status3.execution_id)

      # Each should have sleep events
      assert Enum.any?(events1, fn e -> e.event_type == "SleepStartedEvent" end)
      assert Enum.any?(events2, fn e -> e.event_type == "SleepStartedEvent" end)
      assert Enum.any?(events3, fn e -> e.event_type == "SleepStartedEvent" end)
    end
  end
end

defmodule Cerebelum.Execution.EngineTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Execution.Engine
  alias Cerebelum.Examples.CounterWorkflow

  describe "start_link/1" do
    test "starts engine with workflow and inputs" do
      {:ok, pid} = Engine.start_link(
        workflow_module: CounterWorkflow,
        inputs: %{}
      )

      assert Process.alive?(pid)
      Engine.stop(pid)
    end

    test "requires workflow_module" do
      # start_link returns {:error, reason} when init fails
      result = Engine.start_link(inputs: %{})
      assert match?({:error, _}, result)
    end

    test "accepts optional name" do
      {:ok, pid} = Engine.start_link(
        name: :test_engine,
        workflow_module: CounterWorkflow,
        inputs: %{}
      )

      assert Process.whereis(:test_engine) == pid
      Engine.stop(pid)
    end
  end

  describe "execution states" do
    test "starts in initializing state and transitions through execution" do
      {:ok, pid} = Engine.start_link(
        workflow_module: CounterWorkflow,
        inputs: %{}
      )

      # CounterWorkflow is fast, may complete quickly
      # Just verify it's in a valid state
      status = Engine.get_status(pid)
      assert status.state in [:initializing, :executing_step, :completed]
      assert is_binary(status.execution_id)

      Engine.stop(pid)
    end

    test "executes workflow and reaches completed state" do
      {:ok, pid} = Engine.start_link(
        workflow_module: CounterWorkflow,
        inputs: %{}
      )

      # Wait for execution to complete (should be fast for CounterWorkflow)
      :timer.sleep(100)

      status = Engine.get_status(pid)
      assert status.state == :completed

      Engine.stop(pid)
    end

    test "updates current_step during execution" do
      {:ok, pid} = Engine.start_link(
        workflow_module: CounterWorkflow,
        inputs: %{}
      )

      # Check status at different points
      statuses = for _ <- 1..5 do
        status = Engine.get_status(pid)
        :timer.sleep(5)
        status
      end

      # Should see progression through steps
      steps_seen = Enum.map(statuses, & &1.current_step) |> Enum.uniq()
      assert length(steps_seen) >= 1

      Engine.stop(pid)
    end
  end

  describe "results caching" do
    test "stores results for each step" do
      {:ok, pid} = Engine.start_link(
        workflow_module: CounterWorkflow,
        inputs: %{}
      )

      # Wait for completion
      :timer.sleep(100)

      status = Engine.get_status(pid)

      # CounterWorkflow has 4 steps: initialize, increment, double, finalize
      assert map_size(status.results) == 4
      assert Map.has_key?(status.results, :initialize)
      assert Map.has_key?(status.results, :increment)
      assert Map.has_key?(status.results, :double)
      assert Map.has_key?(status.results, :finalize)

      Engine.stop(pid)
    end

    test "results contain expected values from CounterWorkflow" do
      {:ok, pid} = Engine.start_link(
        workflow_module: CounterWorkflow,
        inputs: %{}
      )

      :timer.sleep(100)

      status = Engine.get_status(pid)

      # Verify CounterWorkflow logic: 0 -> 1 -> 2 -> 2
      assert status.results[:initialize] == {:ok, 0}
      assert status.results[:increment] == {:ok, 1}
      assert status.results[:double] == {:ok, 2}
      assert status.results[:finalize] == {:ok, 2}

      Engine.stop(pid)
    end
  end

  describe "get_status/1" do
    test "returns comprehensive status information" do
      {:ok, pid} = Engine.start_link(
        workflow_module: CounterWorkflow,
        inputs: %{test: "data"}
      )

      :timer.sleep(100)

      status = Engine.get_status(pid)

      assert is_map(status)
      assert Map.has_key?(status, :state)
      assert Map.has_key?(status, :execution_id)
      assert Map.has_key?(status, :workflow_module)
      assert Map.has_key?(status, :current_step)
      assert Map.has_key?(status, :timeline_progress)
      assert Map.has_key?(status, :completed_steps)
      assert Map.has_key?(status, :total_steps)
      assert Map.has_key?(status, :results)
      assert Map.has_key?(status, :error)
      assert Map.has_key?(status, :context)

      assert status.workflow_module == CounterWorkflow
      assert is_binary(status.execution_id)

      Engine.stop(pid)
    end

    test "timeline_progress shows correct format" do
      {:ok, pid} = Engine.start_link(
        workflow_module: CounterWorkflow,
        inputs: %{}
      )

      :timer.sleep(100)

      status = Engine.get_status(pid)

      # CounterWorkflow has 4 steps
      assert status.total_steps == 4
      assert status.timeline_progress == "4/4"

      Engine.stop(pid)
    end

    test "includes context with inputs" do
      {:ok, pid} = Engine.start_link(
        workflow_module: CounterWorkflow,
        inputs: %{user_id: 123}
      )

      :timer.sleep(100)

      status = Engine.get_status(pid)

      assert status.context.inputs == %{user_id: 123}

      Engine.stop(pid)
    end
  end

  describe "error handling" do
    defmodule FailingWorkflow do
      use Cerebelum.Workflow

      workflow do
        timeline do
          step1() |> step2()
        end
      end

      def step1(_context) do
        {:ok, "success"}
      end

      def step2(_context, _step1) do
        raise "Intentional error for testing"
      end
    end

    test "transitions to failed state on error" do
      {:ok, pid} = Engine.start_link(
        workflow_module: FailingWorkflow,
        inputs: %{}
      )

      :timer.sleep(100)

      status = Engine.get_status(pid)

      assert status.state == :failed
      assert status.error != nil

      Engine.stop(pid)
    end

    test "captures error information" do
      {:ok, pid} = Engine.start_link(
        workflow_module: FailingWorkflow,
        inputs: %{}
      )

      :timer.sleep(100)

      status = Engine.get_status(pid)

      # Error is now a map with structured ErrorInfo
      assert is_map(status.error)
      assert status.error.kind == :exception
      assert status.error.step_name == :step2
      assert is_map(status.error.reason)
      assert status.error.reason.type == RuntimeError
      assert is_list(status.error.stacktrace)
      assert is_binary(status.error_message)
      assert String.contains?(status.error_message, "step2")

      Engine.stop(pid)
    end

    test "stores results up to the failing step" do
      {:ok, pid} = Engine.start_link(
        workflow_module: FailingWorkflow,
        inputs: %{}
      )

      :timer.sleep(100)

      status = Engine.get_status(pid)

      # step1 should have completed successfully
      assert Map.has_key?(status.results, :step1)
      assert status.results[:step1] == {:ok, "success"}

      # step2 should not have a result
      refute Map.has_key?(status.results, :step2)

      Engine.stop(pid)
    end

    defmodule ExitingWorkflow do
      use Cerebelum.Workflow

      workflow do
        timeline do
          step1() |> exit_step()
        end
      end

      def step1(_context) do
        {:ok, "before exit"}
      end

      def exit_step(_context, _step1) do
        exit(:intentional_exit)
      end
    end

    defmodule ThrowingWorkflow do
      use Cerebelum.Workflow

      workflow do
        timeline do
          step1() |> throw_step()
        end
      end

      def step1(_context) do
        {:ok, "before throw"}
      end

      def throw_step(_context, _step1) do
        throw({:error, :invalid_data})
      end
    end

    test "handles exit signals" do
      {:ok, pid} = Engine.start_link(
        workflow_module: ExitingWorkflow,
        inputs: %{}
      )

      :timer.sleep(100)

      status = Engine.get_status(pid)

      assert status.state == :failed
      assert status.error.kind == :exit
      assert status.error.step_name == :exit_step
      assert status.error.reason == :intentional_exit
      assert String.contains?(status.error_message, "Exit in step")

      Engine.stop(pid)
    end

    test "handles throw values" do
      {:ok, pid} = Engine.start_link(
        workflow_module: ThrowingWorkflow,
        inputs: %{}
      )

      :timer.sleep(100)

      status = Engine.get_status(pid)

      assert status.state == :failed
      assert status.error.kind == :throw
      assert status.error.step_name == :throw_step
      assert status.error.reason == {:error, :invalid_data}
      assert String.contains?(status.error_message, "Throw in step")

      Engine.stop(pid)
    end

    test "error message is user-friendly" do
      {:ok, pid} = Engine.start_link(
        workflow_module: FailingWorkflow,
        inputs: %{}
      )

      :timer.sleep(100)

      status = Engine.get_status(pid)

      assert is_binary(status.error_message)
      assert String.contains?(status.error_message, "Exception")
      assert String.contains?(status.error_message, "step2")
      assert String.contains?(status.error_message, "RuntimeError")

      Engine.stop(pid)
    end
  end

  describe "workflow with inputs" do
    defmodule InputWorkflow do
      use Cerebelum.Workflow

      workflow do
        timeline do
          greet() |> shout()
        end
      end

      def greet(context) do
        name = context.inputs[:name] || "World"
        {:ok, "Hello, #{name}!"}
      end

      def shout(_context, {:ok, greeting}) do
        {:ok, String.upcase(greeting)}
      end
    end

    test "passes inputs through context" do
      {:ok, pid} = Engine.start_link(
        workflow_module: InputWorkflow,
        inputs: %{name: "Alice"}
      )

      :timer.sleep(100)

      status = Engine.get_status(pid)

      assert status.results[:greet] == {:ok, "Hello, Alice!"}
      assert status.results[:shout] == {:ok, "HELLO, ALICE!"}

      Engine.stop(pid)
    end

    test "uses default when no input provided" do
      {:ok, pid} = Engine.start_link(
        workflow_module: InputWorkflow,
        inputs: %{}
      )

      :timer.sleep(100)

      status = Engine.get_status(pid)

      assert status.results[:greet] == {:ok, "Hello, World!"}

      Engine.stop(pid)
    end
  end

  describe "step arguments" do
    defmodule ArgumentWorkflow do
      use Cerebelum.Workflow

      workflow do
        timeline do
          step1() |> step2() |> step3()
        end
      end

      def step1(_context) do
        {:ok, :first}
      end

      def step2(_context, result1) do
        {:ok, {:second, result1}}
      end

      def step3(_context, result1, result2) do
        {:ok, {:third, result1, result2}}
      end
    end

    test "passes previous results as arguments" do
      {:ok, pid} = Engine.start_link(
        workflow_module: ArgumentWorkflow,
        inputs: %{}
      )

      :timer.sleep(100)

      status = Engine.get_status(pid)

      assert status.results[:step1] == {:ok, :first}
      assert status.results[:step2] == {:ok, {:second, {:ok, :first}}}
      assert status.results[:step3] == {:ok, {:third, {:ok, :first}, {:ok, {:second, {:ok, :first}}}}}

      Engine.stop(pid)
    end
  end

  describe "concurrent executions" do
    test "can run multiple workflows in parallel" do
      pids = for i <- 1..5 do
        {:ok, pid} = Engine.start_link(
          workflow_module: CounterWorkflow,
          inputs: %{run: i}
        )
        pid
      end

      # Wait for all to complete
      :timer.sleep(200)

      # All should be completed
      statuses = Enum.map(pids, &Engine.get_status/1)
      assert Enum.all?(statuses, fn s -> s.state == :completed end)

      # Clean up
      Enum.each(pids, &Engine.stop/1)
    end

    test "each execution has unique execution_id" do
      pids = for _ <- 1..3 do
        {:ok, pid} = Engine.start_link(
          workflow_module: CounterWorkflow,
          inputs: %{}
        )
        pid
      end

      :timer.sleep(100)

      execution_ids = pids
        |> Enum.map(&Engine.get_status/1)
        |> Enum.map(& &1.execution_id)

      assert length(Enum.uniq(execution_ids)) == 3

      Enum.each(pids, &Engine.stop/1)
    end
  end
end

defmodule Cerebelum.Execution.JumpHandlerTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Execution.{JumpHandler, Engine.Data}
  alias Cerebelum.Context

  doctest JumpHandler

  # Helper to create test data
  defp create_test_data(timeline, current_index, iteration \\ 0, results \\ %{}) do
    %Data{
      timeline: timeline,
      workflow_metadata: %{timeline: timeline},
      current_step_index: current_index,
      iteration: iteration,
      results: results,
      context: %Context{
        execution_id: "test-123",
        workflow_module: TestWorkflow,
        workflow_version: "1.0.0",
        inputs: %{},
        current_step: nil,
        correlation_id: nil,
        tags: [],
        metadata: %{},
        started_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    }
  end

  describe "jump_to_step/3 with :back_to" do
    test "jumps back to target step and updates index" do
      timeline = [:step1, :step2, :step3]
      data = create_test_data(timeline, 2)

      {:ok, new_data} = JumpHandler.jump_to_step(data, :back_to, :step1)

      assert new_data.current_step_index == 0
    end

    test "increments iteration counter" do
      timeline = [:step1, :step2, :step3]
      data = create_test_data(timeline, 2, 0)

      {:ok, new_data} = JumpHandler.jump_to_step(data, :back_to, :step1)

      assert new_data.iteration == 1
    end

    test "clears results after target step" do
      timeline = [:step1, :step2, :step3, :step4]
      results = %{step1: :r1, step2: :r2, step3: :r3, step4: :r4}
      data = create_test_data(timeline, 3, 0, results)

      {:ok, new_data} = JumpHandler.jump_to_step(data, :back_to, :step2)

      # Should keep step1 only (steps before index 1)
      assert new_data.results == %{step1: :r1}
    end

    test "preserves results before target step" do
      timeline = [:step1, :step2, :step3]
      results = %{step1: :result1, step2: :result2, step3: :result3}
      data = create_test_data(timeline, 2, 0, results)

      {:ok, new_data} = JumpHandler.jump_to_step(data, :back_to, :step2)

      assert new_data.results == %{step1: :result1}
    end

    test "returns error when step not found" do
      timeline = [:step1, :step2, :step3]
      data = create_test_data(timeline, 2)

      assert {:error, :step_not_found} =
               JumpHandler.jump_to_step(data, :back_to, :nonexistent_step)
    end

    test "returns error when iteration limit exceeded" do
      timeline = [:step1, :step2, :step3]
      data = create_test_data(timeline, 2, 1000)

      assert {:error, :infinite_loop} = JumpHandler.jump_to_step(data, :back_to, :step1)
    end

    test "can jump back to same step (retry)" do
      timeline = [:fetch_data, :process_data, :save_data]
      data = create_test_data(timeline, 0, 0, %{})

      {:ok, new_data} = JumpHandler.jump_to_step(data, :back_to, :fetch_data)

      assert new_data.current_step_index == 0
      assert new_data.iteration == 1
    end

    test "multiple back_to calls increment iteration each time" do
      timeline = [:step1, :step2, :step3]
      data = create_test_data(timeline, 2, 0)

      {:ok, data} = JumpHandler.jump_to_step(data, :back_to, :step1)
      assert data.iteration == 1

      {:ok, data} = JumpHandler.jump_to_step(data, :back_to, :step1)
      assert data.iteration == 2

      {:ok, data} = JumpHandler.jump_to_step(data, :back_to, :step1)
      assert data.iteration == 3
    end
  end

  describe "jump_to_step/3 with :skip_to" do
    test "jumps to target step and updates index" do
      timeline = [:step1, :step2, :step3, :step4]
      data = create_test_data(timeline, 0)

      {:ok, new_data} = JumpHandler.jump_to_step(data, :skip_to, :step3)

      assert new_data.current_step_index == 2
    end

    test "preserves iteration counter" do
      timeline = [:step1, :step2, :step3]
      data = create_test_data(timeline, 0, 5)

      {:ok, new_data} = JumpHandler.jump_to_step(data, :skip_to, :step3)

      assert new_data.iteration == 5
    end

    test "preserves all results" do
      timeline = [:step1, :step2, :step3, :step4]
      results = %{step1: :r1, step2: :r2}
      data = create_test_data(timeline, 2, 0, results)

      {:ok, new_data} = JumpHandler.jump_to_step(data, :skip_to, :step4)

      assert new_data.results == results
    end

    test "returns error when step not found" do
      timeline = [:step1, :step2, :step3]
      data = create_test_data(timeline, 0)

      assert {:error, :step_not_found} =
               JumpHandler.jump_to_step(data, :skip_to, :nonexistent_step)
    end

    test "can skip multiple steps forward" do
      timeline = [:step1, :step2, :step3, :step4, :step5]
      data = create_test_data(timeline, 0)

      {:ok, new_data} = JumpHandler.jump_to_step(data, :skip_to, :step5)

      assert new_data.current_step_index == 4
    end

    test "can skip to next step" do
      timeline = [:step1, :step2, :step3]
      data = create_test_data(timeline, 0)

      {:ok, new_data} = JumpHandler.jump_to_step(data, :skip_to, :step2)

      assert new_data.current_step_index == 1
    end
  end

  describe "find_step_index/2" do
    test "returns index of step in timeline" do
      timeline = [:step1, :step2, :step3]

      assert {:ok, 0} = JumpHandler.find_step_index(timeline, :step1)
      assert {:ok, 1} = JumpHandler.find_step_index(timeline, :step2)
      assert {:ok, 2} = JumpHandler.find_step_index(timeline, :step3)
    end

    test "returns error when step not found" do
      timeline = [:step1, :step2, :step3]

      assert {:error, :step_not_found} =
               JumpHandler.find_step_index(timeline, :nonexistent)
    end

    test "handles empty timeline" do
      timeline = []

      assert {:error, :step_not_found} = JumpHandler.find_step_index(timeline, :step1)
    end

    test "finds step in long timeline" do
      timeline = Enum.map(1..100, &String.to_atom("step#{&1}"))

      assert {:ok, 49} = JumpHandler.find_step_index(timeline, :step50)
    end
  end

  describe "clear_results_after/3" do
    test "clears results after given index" do
      timeline = [:step1, :step2, :step3, :step4]
      results = %{step1: :r1, step2: :r2, step3: :r3, step4: :r4}

      cleared = JumpHandler.clear_results_after(results, timeline, 2)

      assert cleared == %{step1: :r1, step2: :r2}
    end

    test "clears all results when index is 0" do
      timeline = [:step1, :step2, :step3]
      results = %{step1: :r1, step2: :r2, step3: :r3}

      cleared = JumpHandler.clear_results_after(results, timeline, 0)

      assert cleared == %{}
    end

    test "preserves all results when index is at end" do
      timeline = [:step1, :step2, :step3]
      results = %{step1: :r1, step2: :r2, step3: :r3}

      cleared = JumpHandler.clear_results_after(results, timeline, 3)

      assert cleared == results
    end

    test "handles empty results" do
      timeline = [:step1, :step2, :step3]
      results = %{}

      cleared = JumpHandler.clear_results_after(results, timeline, 1)

      assert cleared == %{}
    end

    test "ignores results not in timeline" do
      timeline = [:step1, :step2, :step3]
      results = %{step1: :r1, step2: :r2, step3: :r3, extra_step: :extra}

      cleared = JumpHandler.clear_results_after(results, timeline, 2)

      assert cleared == %{step1: :r1, step2: :r2}
    end
  end

  describe "check_iteration_limit/1" do
    test "returns :ok when within limit" do
      assert :ok = JumpHandler.check_iteration_limit(0)
      assert :ok = JumpHandler.check_iteration_limit(500)
      assert :ok = JumpHandler.check_iteration_limit(999)
      assert :ok = JumpHandler.check_iteration_limit(1000)
    end

    test "returns error when exceeding limit" do
      assert {:error, :infinite_loop} = JumpHandler.check_iteration_limit(1001)
      assert {:error, :infinite_loop} = JumpHandler.check_iteration_limit(2000)
      assert {:error, :infinite_loop} = JumpHandler.check_iteration_limit(999_999)
    end
  end

  describe "max_iterations/0" do
    test "returns maximum iterations value" do
      assert JumpHandler.max_iterations() == 1000
    end
  end
end

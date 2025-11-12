defmodule Cerebelum.Execution.BranchHandlerTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Execution.BranchHandler
  alias Cerebelum.FlowAction

  doctest BranchHandler

  describe "evaluate/3" do
    test "returns :no_branch when no branch defined for step" do
      metadata = %{branches: %{}}

      assert BranchHandler.evaluate(metadata, :some_step, %{}) == :no_branch
    end

    test "returns :no_branch when branches key missing from metadata" do
      metadata = %{}

      assert BranchHandler.evaluate(metadata, :some_step, %{}) == :no_branch
    end

    test "returns {:continue, nil} when no condition matches" do
      metadata = %{
        branches: %{
          calculate_risk: [
            {quote(do: result.score > 0.8), :high_risk}
          ]
        }
      }

      result = %{score: 0.5}

      assert BranchHandler.evaluate(metadata, :calculate_risk, result) == {:continue, nil}
    end

    test "returns {:skip_to, target} when condition matches with atom action" do
      metadata = %{
        branches: %{
          calculate_risk: [
            {quote(do: result.score > 0.8), :high_risk}
          ]
        }
      }

      result = %{score: 0.9}

      assert BranchHandler.evaluate(metadata, :calculate_risk, result) == {:skip_to, :high_risk}
    end

    test "returns {:skip_to, target} when condition matches with FlowAction.SkipTo" do
      metadata = %{
        branches: %{
          calculate_risk: [
            {quote(do: result.score > 0.8), FlowAction.skip_to(:high_risk_path)}
          ]
        }
      }

      result = %{score: 0.9}

      assert BranchHandler.evaluate(metadata, :calculate_risk, result) ==
               {:skip_to, :high_risk_path}
    end

    test "evaluates first matching condition" do
      metadata = %{
        branches: %{
          calculate_risk: [
            {quote(do: result.score > 0.8), :high_risk},
            {quote(do: result.score > 0.5), :medium_risk},
            {quote(do: true), :low_risk}
          ]
        }
      }

      # High risk
      assert BranchHandler.evaluate(metadata, :calculate_risk, %{score: 0.9}) ==
               {:skip_to, :high_risk}

      # Medium risk
      assert BranchHandler.evaluate(metadata, :calculate_risk, %{score: 0.6}) ==
               {:skip_to, :medium_risk}

      # Low risk (default)
      assert BranchHandler.evaluate(metadata, :calculate_risk, %{score: 0.3}) ==
               {:skip_to, :low_risk}
    end

    test "supports FlowAction.Continue for explicit continue" do
      metadata = %{
        branches: %{
          check_status: [
            {quote(do: result.status == :ok), FlowAction.continue()}
          ]
        }
      }

      result = %{status: :ok}

      assert BranchHandler.evaluate(metadata, :check_status, result) == {:continue, nil}
    end

    test "supports :continue atom action" do
      metadata = %{
        branches: %{
          check_status: [
            {quote(do: result.status == :ok), :continue}
          ]
        }
      }

      result = %{status: :ok}

      assert BranchHandler.evaluate(metadata, :check_status, result) == {:continue, nil}
    end

    test "handles result as {:ok, map}" do
      metadata = %{
        branches: %{
          calculate_risk: [
            {quote(do: result.score > 0.8), :high_risk}
          ]
        }
      }

      result = {:ok, %{score: 0.9}}

      assert BranchHandler.evaluate(metadata, :calculate_risk, result) == {:skip_to, :high_risk}
    end

    test "handles result as {:ok, value}" do
      metadata = %{
        branches: %{
          check_number: [
            {quote(do: result > 100), :large}
          ]
        }
      }

      result = {:ok, 150}

      assert BranchHandler.evaluate(metadata, :check_number, result) == {:skip_to, :large}
    end

    test "handles result as simple value" do
      metadata = %{
        branches: %{
          check_number: [
            {quote(do: result > 100), :large}
          ]
        }
      }

      result = 150

      assert BranchHandler.evaluate(metadata, :check_number, result) == {:skip_to, :large}
    end

    test "complex workflow example - bank reconciliation" do
      metadata = %{
        branches: %{
          calculate_differences: [
            {quote(do: result.total_diff > result.threshold), :escalate},
            {quote(do: true), :auto_resolve}
          ]
        }
      }

      # High difference - escalate
      result_high = %{total_diff: 500.0, threshold: 100.0}

      assert BranchHandler.evaluate(metadata, :calculate_differences, result_high) ==
               {:skip_to, :escalate}

      # Low difference - auto resolve
      result_low = %{total_diff: 50.0, threshold: 100.0}

      assert BranchHandler.evaluate(metadata, :calculate_differences, result_low) ==
               {:skip_to, :auto_resolve}
    end

    test "complex conditions with multiple fields" do
      metadata = %{
        branches: %{
          process_order: [
            {quote(do: result.amount > 1000 and result.priority == :high), :fast_track},
            {quote(do: result.amount > 1000), :standard_high_value},
            {quote(do: result.priority == :high), :standard_priority},
            {quote(do: true), :standard}
          ]
        }
      }

      # Fast track
      assert BranchHandler.evaluate(metadata, :process_order, %{
               amount: 2000,
               priority: :high
             }) == {:skip_to, :fast_track}

      # Standard high value
      assert BranchHandler.evaluate(metadata, :process_order, %{amount: 2000, priority: :low}) ==
               {:skip_to, :standard_high_value}

      # Standard priority
      assert BranchHandler.evaluate(metadata, :process_order, %{amount: 500, priority: :high}) ==
               {:skip_to, :standard_priority}

      # Standard
      assert BranchHandler.evaluate(metadata, :process_order, %{amount: 500, priority: :low}) ==
               {:skip_to, :standard}
    end

    test "supports boolean operators" do
      metadata = %{
        branches: %{
          validate: [
            {quote(do: result.valid and result.approved), :proceed},
            {quote(do: result.valid or result.override), :review},
            {quote(do: not result.blocked), :check},
            {quote(do: true), :reject}
          ]
        }
      }

      # AND
      assert BranchHandler.evaluate(metadata, :validate, %{valid: true, approved: true}) ==
               {:skip_to, :proceed}

      # OR
      assert BranchHandler.evaluate(metadata, :validate, %{
               valid: false,
               approved: false,
               override: true
             }) == {:skip_to, :review}

      # NOT
      assert BranchHandler.evaluate(metadata, :validate, %{
               valid: false,
               approved: false,
               override: false,
               blocked: false
             }) == {:skip_to, :check}

      # Default
      assert BranchHandler.evaluate(metadata, :validate, %{
               valid: false,
               approved: false,
               override: false,
               blocked: true
             }) == {:skip_to, :reject}
    end
  end

  describe "get_branch_for_step/2" do
    test "returns branch conditions when defined" do
      conditions = [{quote(do: result.score > 0.8), :high_risk}]

      metadata = %{
        branches: %{
          calculate_risk: conditions
        }
      }

      assert BranchHandler.get_branch_for_step(metadata, :calculate_risk) == conditions
    end

    test "returns nil when step has no branch" do
      metadata = %{
        branches: %{
          calculate_risk: [{quote(do: result.score > 0.8), :high_risk}]
        }
      }

      assert BranchHandler.get_branch_for_step(metadata, :other_step) == nil
    end

    test "returns nil when branches is empty map" do
      metadata = %{branches: %{}}

      assert BranchHandler.get_branch_for_step(metadata, :calculate_risk) == nil
    end

    test "returns nil when metadata has no branches key" do
      metadata = %{}

      assert BranchHandler.get_branch_for_step(metadata, :calculate_risk) == nil
    end
  end
end

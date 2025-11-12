defmodule Cerebelum.Execution.DivergeHandlerTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Execution.DivergeHandler
  alias Cerebelum.FlowAction

  doctest DivergeHandler

  describe "evaluate/3" do
    test "returns :no_diverge when no diverge defined for step" do
      metadata = %{diverges: %{}}

      assert DivergeHandler.evaluate(metadata, :some_step, :timeout) == :no_diverge
    end

    test "returns :no_diverge when diverges key missing from metadata" do
      metadata = %{}

      assert DivergeHandler.evaluate(metadata, :some_step, :timeout) == :no_diverge
    end

    test "returns {:continue, nil} when no pattern matches" do
      metadata = %{
        diverges: %{
          fetch_data: [
            {:timeout, :retry},
            {{:error, :network}, :retry}
          ]
        }
      }

      assert DivergeHandler.evaluate(metadata, :fetch_data, {:ok, "data"}) == {:continue, nil}
    end

    test "returns {:back_to, step} for :retry action on atom pattern" do
      metadata = %{
        diverges: %{
          fetch_data: [
            {:timeout, :retry}
          ]
        }
      }

      assert DivergeHandler.evaluate(metadata, :fetch_data, :timeout) == {:back_to, :fetch_data}
    end

    test "returns {:back_to, step} for :retry action on tuple pattern" do
      metadata = %{
        diverges: %{
          fetch_data: [
            {{:error, :network}, :retry}
          ]
        }
      }

      assert DivergeHandler.evaluate(metadata, :fetch_data, {:error, :network}) ==
               {:back_to, :fetch_data}
    end

    test "returns {:back_to, step} for :retry action on wildcard pattern" do
      metadata = %{
        diverges: %{
          fetch_data: [
            {{:error, :_}, :retry}
          ]
        }
      }

      assert DivergeHandler.evaluate(metadata, :fetch_data, {:error, :network}) ==
               {:back_to, :fetch_data}

      assert DivergeHandler.evaluate(metadata, :fetch_data, {:error, :database_down}) ==
               {:back_to, :fetch_data}
    end

    test "returns {:failed, result} for :failed action" do
      metadata = %{
        diverges: %{
          fetch_data: [
            {{:error, :critical}, :failed}
          ]
        }
      }

      assert DivergeHandler.evaluate(metadata, :fetch_data, {:error, :critical}) ==
               {:failed, {:error, :critical}}
    end

    test "matches first pattern when multiple patterns match" do
      metadata = %{
        diverges: %{
          fetch_data: [
            {{:error, :_}, :retry},
            {{:error, :critical}, :failed}
          ]
        }
      }

      # First pattern matches, so should retry (not fail)
      assert DivergeHandler.evaluate(metadata, :fetch_data, {:error, :critical}) ==
               {:back_to, :fetch_data}
    end

    test "returns {:continue, nil} for :continue action" do
      metadata = %{
        diverges: %{
          fetch_data: [
            {:ok, :continue}
          ]
        }
      }

      assert DivergeHandler.evaluate(metadata, :fetch_data, :ok) == {:continue, nil}
    end

    test "supports FlowAction.Continue struct" do
      metadata = %{
        diverges: %{
          fetch_data: [
            {:ok, FlowAction.continue()}
          ]
        }
      }

      assert DivergeHandler.evaluate(metadata, :fetch_data, :ok) == {:continue, nil}
    end

    test "supports FlowAction.BackTo struct" do
      metadata = %{
        diverges: %{
          validate_data: [
            {{:error, :validation_failed}, FlowAction.back_to(:prepare_data)}
          ]
        }
      }

      assert DivergeHandler.evaluate(metadata, :validate_data, {:error, :validation_failed}) ==
               {:back_to, :prepare_data}
    end

    test "supports FlowAction.SkipTo struct" do
      metadata = %{
        diverges: %{
          optional_step: [
            {:skip, FlowAction.skip_to(:final_step)}
          ]
        }
      }

      assert DivergeHandler.evaluate(metadata, :optional_step, :skip) ==
               {:skip_to, :final_step}
    end

    test "supports FlowAction.Failed struct" do
      metadata = %{
        diverges: %{
          critical_step: [
            {:error, FlowAction.failed(:critical_error)}
          ]
        }
      }

      assert DivergeHandler.evaluate(metadata, :critical_step, :error) ==
               {:failed, :critical_error}
    end

    test "complex workflow example with multiple diverge clauses" do
      metadata = %{
        diverges: %{
          fetch_bank_statement: [
            {:timeout, :retry},
            {{:error, :bank_api_down}, :failed},
            {{:error, :_}, :failed}
          ],
          fetch_internal_ledger: [
            {:timeout, :retry},
            {{:error, :database_error}, :failed}
          ]
        }
      }

      # fetch_bank_statement scenarios
      assert DivergeHandler.evaluate(metadata, :fetch_bank_statement, :timeout) ==
               {:back_to, :fetch_bank_statement}

      assert DivergeHandler.evaluate(metadata, :fetch_bank_statement, {:error, :bank_api_down}) ==
               {:failed, {:error, :bank_api_down}}

      assert DivergeHandler.evaluate(metadata, :fetch_bank_statement, {:error, :network}) ==
               {:failed, {:error, :network}}

      assert DivergeHandler.evaluate(metadata, :fetch_bank_statement, {:ok, "data"}) ==
               {:continue, nil}

      # fetch_internal_ledger scenarios
      assert DivergeHandler.evaluate(metadata, :fetch_internal_ledger, :timeout) ==
               {:back_to, :fetch_internal_ledger}

      assert DivergeHandler.evaluate(
               metadata,
               :fetch_internal_ledger,
               {:error, :database_error}
             ) == {:failed, {:error, :database_error}}

      assert DivergeHandler.evaluate(metadata, :fetch_internal_ledger, {:ok, "ledger"}) ==
               {:continue, nil}
    end
  end

  describe "get_diverge_for_step/2" do
    test "returns diverge patterns when defined" do
      patterns = [{:timeout, :retry}]

      metadata = %{
        diverges: %{
          fetch_data: patterns
        }
      }

      assert DivergeHandler.get_diverge_for_step(metadata, :fetch_data) == patterns
    end

    test "returns nil when step has no diverge" do
      metadata = %{
        diverges: %{
          fetch_data: [{:timeout, :retry}]
        }
      }

      assert DivergeHandler.get_diverge_for_step(metadata, :other_step) == nil
    end

    test "returns nil when diverges is empty map" do
      metadata = %{diverges: %{}}

      assert DivergeHandler.get_diverge_for_step(metadata, :fetch_data) == nil
    end

    test "returns nil when metadata has no diverges key" do
      metadata = %{}

      assert DivergeHandler.get_diverge_for_step(metadata, :fetch_data) == nil
    end
  end
end

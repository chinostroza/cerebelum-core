defmodule Cerebelum.Integration.DivergeBranchIntegrationTest do
  use ExUnit.Case, async: true

  alias Cerebelum

  doctest Cerebelum

  @moduletag :integration

  describe "Workflow with diverge and branch" do
    defmodule RetryWorkflow do
      use Cerebelum.Workflow

      workflow do
        timeline do
          fetch_data() |> process_data() |> save_data()
        end

        diverge from: fetch_data() do
          :timeout -> :retry
          {:error, :network} -> :retry
          {:error, :_} -> :failed
        end
      end

      def fetch_data(context) do
        # Simular timeout en primer intento
        case Map.get(context.inputs, :attempt, 0) do
          0 -> :timeout
          1 -> {:ok, "data"}
        end
      end

      def process_data(_context, {:ok, data}) do
        {:ok, String.upcase(data)}
      end

      def save_data(_context, _fetch_result, {:ok, processed}) do
        {:ok, "saved: #{processed}"}
      end
    end

    defmodule BranchingWorkflow do
      use Cerebelum.Workflow

      workflow do
        timeline do
          calculate_risk() |> high_risk() |> medium_risk() |> low_risk() |> complete()
        end

        branch after: calculate_risk(), on: result do
          result.score > 0.8 -> :high_risk
          result.score > 0.5 -> :medium_risk
          true -> :low_risk
        end
      end

      def calculate_risk(context) do
        score = Map.get(context.inputs, :score, 0.3)
        {:ok, %{score: score}}
      end

      # High risk path
      def high_risk(_context, {:ok, risk}) do
        {:ok, "HIGH RISK PATH: #{risk.score}"}
      end

      # Medium risk path
      def medium_risk(_context, _risk_result, {:ok, high_result}) do
        {:ok, "MEDIUM RISK PATH: after #{high_result}"}
      end

      # Low risk path
      def low_risk(_context, _risk, _high, {:ok, medium_result}) do
        {:ok, "LOW RISK PATH: after #{medium_result}"}
      end

      def complete(_context, _risk, _high, _medium, {:ok, low_result}) do
        {:ok, "completed: #{low_result}"}
      end
    end

    test "workflow with diverge retry works" do
      # Primera ejecución - timeout y retry
      {:ok, execution} = Cerebelum.execute_workflow(RetryWorkflow, %{attempt: 0})

      # Wait for execution to complete
      Process.sleep(100)

      {:ok, status} = Cerebelum.get_execution_status(execution.id)

      # Should have retried (iteration > 0)
      assert status.iteration > 0

      # Should eventually timeout or complete
      # En este caso no completará porque attempt siempre será 0
      # Este es un test simple que verifica que el retry se ejecutó
    end

    test "workflow with branch to high risk" do
      {:ok, execution} = Cerebelum.execute_workflow(BranchingWorkflow, %{score: 0.9})

      # Wait for execution
      Process.sleep(100)

      {:ok, status} = Cerebelum.get_execution_status(execution.id)

      # Should have completed
      assert status.state == :completed

      # Should have executed high_risk step
      assert Map.has_key?(status.results, :high_risk)
      assert {:ok, "HIGH RISK PATH: 0.9"} = status.results[:high_risk]

      # Should have executed all remaining steps after the jump
      assert Map.has_key?(status.results, :medium_risk)
      assert Map.has_key?(status.results, :low_risk)
      assert Map.has_key?(status.results, :complete)
    end

    test "workflow with branch to medium risk" do
      {:ok, execution} = Cerebelum.execute_workflow(BranchingWorkflow, %{score: 0.6})

      Process.sleep(100)

      {:ok, status} = Cerebelum.get_execution_status(execution.id)

      assert status.state == :completed

      # Should have skipped high_risk
      refute Map.has_key?(status.results, :high_risk)

      # Should have executed medium_risk and onwards
      assert Map.has_key?(status.results, :medium_risk)
      assert Map.has_key?(status.results, :low_risk)
      assert Map.has_key?(status.results, :complete)
    end

    test "workflow with branch to low risk" do
      {:ok, execution} = Cerebelum.execute_workflow(BranchingWorkflow, %{score: 0.2})

      Process.sleep(100)

      {:ok, status} = Cerebelum.get_execution_status(execution.id)

      assert status.state == :completed

      # Should have skipped high_risk and medium_risk
      refute Map.has_key?(status.results, :high_risk)
      refute Map.has_key?(status.results, :medium_risk)

      # Should have executed low_risk and complete
      assert Map.has_key?(status.results, :low_risk)
      assert Map.has_key?(status.results, :complete)
    end
  end

  describe "Complex workflow with both diverge and branch" do
    defmodule ComplexWorkflow do
      use Cerebelum.Workflow

      workflow do
        timeline do
          fetch_data() |> validate_data() |> fast_process() |> manual_review() |> standard_process() |> finalize()
        end

        # Retry on timeout
        diverge from: fetch_data() do
          :timeout -> :retry
          {:error, :_} -> :failed
        end

        # Different paths based on data quality
        branch after: validate_data(), on: result do
          result.quality == :high -> :fast_process
          result.quality == :low -> :manual_review
          true -> :standard_process
        end
      end

      def fetch_data(context) do
        case Map.get(context.inputs, :fetch_status, :ok) do
          :timeout -> :timeout
          :ok -> {:ok, "raw_data"}
        end
      end

      def validate_data(_context, {:ok, _data}) do
        quality = :high
        {:ok, %{quality: quality, data: "validated"}}
      end

      # Fast process path
      def fast_process(_context, _fetch, {:ok, validation}) do
        {:ok, "FAST: #{validation.data}"}
      end

      # Manual review path
      def manual_review(_context, _fetch, _validation, {:ok, fast}) do
        {:ok, "MANUAL: after #{fast}"}
      end

      # Standard process path
      def standard_process(_context, _fetch, _validation, _fast, {:ok, manual}) do
        {:ok, "STANDARD: after #{manual}"}
      end

      def finalize(_context, _fetch, _validation, _fast, _manual, {:ok, standard}) do
        {:ok, "DONE: #{standard}"}
      end
    end

    test "complex workflow with high quality data" do
      {:ok, execution} = Cerebelum.execute_workflow(ComplexWorkflow, %{fetch_status: :ok})

      Process.sleep(100)

      {:ok, status} = Cerebelum.get_execution_status(execution.id)

      assert status.state == :completed

      # Should have executed fast_process and everything after
      assert Map.has_key?(status.results, :fast_process)
      assert {:ok, "FAST: validated"} = status.results[:fast_process]
      assert Map.has_key?(status.results, :manual_review)
      assert Map.has_key?(status.results, :standard_process)
      assert Map.has_key?(status.results, :finalize)
    end
  end
end

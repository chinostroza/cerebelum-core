defmodule Cerebelum.Workflow.DSLTest do
  use ExUnit.Case, async: true

  # Workflow con solo timeline
  defmodule TimelineOnlyWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        step1() |> step2() |> step3()
      end
    end

    def step1(_context), do: :ok
    def step2(_context, _step1), do: :ok
    def step3(_context, _step1, _step2), do: :ok
  end

  # Workflow con timeline y diverge
  defmodule WorkflowWithDiverge do
    use Cerebelum.Workflow

    workflow do
      timeline do
        validate() |> process()
      end

      diverge from: validate() do
        :timeout -> :retry
        {:error, :network} -> :failed
        {:error, _} -> :failed
      end
    end

    def validate(_context), do: :ok
    def process(_context, _validate), do: :ok
  end

  # Workflow con timeline y branch
  defmodule WorkflowWithBranch do
    use Cerebelum.Workflow

    workflow do
      timeline do
        calculate() |> decide()
      end

      branch after: calculate(), on: result do
        result > 0.8 -> :high_path
        result > 0.5 -> :medium_path
        true -> :low_path
      end
    end

    def calculate(_context), do: 0.9
    def decide(_context, _result), do: :ok
  end

  # Workflow completo con todo
  defmodule CompleteWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        step1() |> step2() |> step3() |> step4()
      end

      diverge from: step1() do
        :timeout -> :retry
        {:error, _} -> :failed
      end

      diverge from: step3() do
        {:error, :network} -> :retry
      end

      branch after: step2(), on: result do
        result.score > 100 -> :high_score_path
        true -> :normal_path
      end
    end

    def step1(_context), do: :ok
    def step2(_context, _step1), do: %{score: 50}
    def step3(_context, _step1, _step2), do: :ok
    def step4(_context, _step1, _step2, _step3), do: :ok
  end

  describe "timeline macro" do
    test "parses simple pipeline into list of steps" do
      metadata = TimelineOnlyWorkflow.__workflow_metadata__()

      assert metadata.timeline == [:step1, :step2, :step3]
    end

    test "extracts function names from function calls" do
      metadata = WorkflowWithDiverge.__workflow_metadata__()

      assert metadata.timeline == [:validate, :process]
    end

    test "preserves order of steps in pipeline" do
      metadata = CompleteWorkflow.__workflow_metadata__()

      assert metadata.timeline == [:step1, :step2, :step3, :step4]
    end

    test "timeline is stored in @cerebelum_timeline" do
      # Verificar que el atributo existe y tiene el valor correcto
      assert TimelineOnlyWorkflow.__workflow_metadata__().timeline == [:step1, :step2, :step3]
    end
  end

  describe "diverge macro" do
    test "parses diverge block with patterns" do
      metadata = WorkflowWithDiverge.__workflow_metadata__()

      assert Map.has_key?(metadata.diverges, :validate)
    end

    test "extracts pattern -> action mappings" do
      metadata = WorkflowWithDiverge.__workflow_metadata__()

      patterns = metadata.diverges[:validate]

      assert is_list(patterns)
      assert length(patterns) == 3
    end

    test "preserves pattern match structure" do
      metadata = WorkflowWithDiverge.__workflow_metadata__()

      patterns = metadata.diverges[:validate]

      # Verificar que los patrones están presentes
      assert {:timeout, :retry} in patterns
      assert Enum.any?(patterns, fn
               {{:error, :network}, :failed} -> true
               _ -> false
             end)
    end

    test "supports multiple diverge blocks for different steps" do
      metadata = CompleteWorkflow.__workflow_metadata__()

      assert Map.has_key?(metadata.diverges, :step1)
      assert Map.has_key?(metadata.diverges, :step3)
    end

    test "extracts step name from 'from:' option" do
      metadata = WorkflowWithDiverge.__workflow_metadata__()

      # El diverge está asociado a :validate
      assert Map.has_key?(metadata.diverges, :validate)
    end
  end

  describe "branch macro" do
    test "parses branch block with conditions" do
      metadata = WorkflowWithBranch.__workflow_metadata__()

      assert Map.has_key?(metadata.branches, :calculate)
    end

    test "extracts condition -> action mappings" do
      metadata = WorkflowWithBranch.__workflow_metadata__()

      conditions = metadata.branches[:calculate]

      assert is_list(conditions)
      assert length(conditions) == 3
    end

    test "preserves AST of conditions" do
      metadata = WorkflowWithBranch.__workflow_metadata__()

      conditions = metadata.branches[:calculate]

      # Verificar que tenemos tuplas {condition_ast, action}
      assert Enum.all?(conditions, fn {_condition, action} ->
               is_atom(action)
             end)
    end

    test "extracts step name from 'after:' option" do
      metadata = WorkflowWithBranch.__workflow_metadata__()

      # El branch está asociado a :calculate
      assert Map.has_key?(metadata.branches, :calculate)
    end

    test "captures variable from 'on:' option" do
      metadata = WorkflowWithBranch.__workflow_metadata__()

      # Por ahora solo verificamos que el branch existe
      # La variable 'result' está en el AST de las condiciones
      assert Map.has_key?(metadata.branches, :calculate)
    end
  end

  describe "workflow macro integration" do
    test "combines timeline, diverges, and branches" do
      metadata = CompleteWorkflow.__workflow_metadata__()

      assert metadata.timeline == [:step1, :step2, :step3, :step4]
      assert map_size(metadata.diverges) == 2
      assert map_size(metadata.branches) == 1
    end

    test "workflow with only timeline works" do
      metadata = TimelineOnlyWorkflow.__workflow_metadata__()

      assert metadata.timeline == [:step1, :step2, :step3]
      assert metadata.diverges == %{}
      assert metadata.branches == %{}
    end

    test "workflow with timeline and diverge works" do
      metadata = WorkflowWithDiverge.__workflow_metadata__()

      assert length(metadata.timeline) == 2
      assert map_size(metadata.diverges) == 1
      assert metadata.branches == %{}
    end

    test "workflow with timeline and branch works" do
      metadata = WorkflowWithBranch.__workflow_metadata__()

      assert length(metadata.timeline) == 2
      assert metadata.diverges == %{}
      assert map_size(metadata.branches) == 1
    end
  end

  describe "parse helpers" do
    alias Cerebelum.Workflow.DSL

    test "extract_function_name/1 extracts from function call" do
      ast = quote(do: validate_order())
      assert DSL.extract_function_name(ast) == :validate_order
    end

    test "extract_function_name/1 handles atom directly" do
      assert DSL.extract_function_name(:step1) == :step1
    end

    test "parse_timeline_pipeline/1 parses simple pipeline" do
      pipeline = quote(do: step1() |> step2() |> step3())
      steps = DSL.parse_timeline_pipeline(pipeline)

      assert steps == [:step1, :step2, :step3]
    end

    test "parse_timeline_pipeline/1 handles single step" do
      pipeline = quote(do: step1())
      steps = DSL.parse_timeline_pipeline(pipeline)

      assert steps == [:step1]
    end

    test "parse_match_block/1 parses pattern clauses" do
      block =
        quote do
          :timeout -> :retry
          {:error, _} -> :failed
        end

      patterns = DSL.parse_match_block(block)

      assert length(patterns) == 2
      assert {:timeout, :retry} in patterns
    end

    test "parse_condition_block/1 parses conditional clauses" do
      block =
        quote do
          result > 0.8 -> :high
          true -> :low
        end

      conditions = DSL.parse_condition_block(block, :result)

      assert length(conditions) == 2
      assert Enum.all?(conditions, fn {_cond, action} -> is_atom(action) end)
    end
  end
end

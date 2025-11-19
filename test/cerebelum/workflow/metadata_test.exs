defmodule Cerebelum.Workflow.MetadataTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Workflow.Metadata

  # Workflow de ejemplo simple
  defmodule SimpleWorkflow do
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

  # Workflow con diverges y branches
  defmodule ComplexWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        validate() |> process() |> finalize()
      end

      diverge from: validate() do
        :timeout -> :retry
        {:error, _} -> :failed
      end

      branch after: process(), on: result do
        result > 100 -> :high_value
        true -> :standard
      end
    end

    def validate(_context), do: :ok
    def process(_context, _validate), do: 50
    def finalize(_context, _validate, _process), do: :done
  end

  describe "extract/1" do
    test "extracts complete metadata from simple workflow" do
      metadata = Metadata.extract(SimpleWorkflow)

      assert metadata.module == SimpleWorkflow
      assert metadata.timeline == [:step1, :step2, :step3]
      assert metadata.diverges == %{}
      assert metadata.branches == %{}
      assert is_binary(metadata.version)
      assert is_map(metadata.functions)
      assert is_map(metadata.graph)
    end

    test "extracts complete metadata from complex workflow" do
      metadata = Metadata.extract(ComplexWorkflow)

      assert metadata.module == ComplexWorkflow
      assert metadata.timeline == [:validate, :process, :finalize]
      assert map_size(metadata.diverges) == 1
      assert map_size(metadata.branches) == 1
      assert is_binary(metadata.version)
      assert is_map(metadata.functions)
      assert is_map(metadata.graph)
    end

    test "version is a valid hex string or unknown" do
      metadata = Metadata.extract(SimpleWorkflow)

      assert is_binary(metadata.version)
      # Durante compilación puede ser "unknown" o un hash válido (SHA256 = 64 hex chars)
      assert metadata.version == "unknown" or String.match?(metadata.version, ~r/^[0-9a-f]{64}$/)
    end

    test "version is consistent for same workflow" do
      # La versión debe ser consistente para el mismo módulo
      metadata1 = Metadata.extract(SimpleWorkflow)
      metadata2 = Metadata.extract(SimpleWorkflow)

      assert metadata1.version == metadata2.version
    end
  end

  describe "extract_functions/2" do
    test "extracts function metadata from timeline" do
      functions = Metadata.extract_functions(SimpleWorkflow, [:step1, :step2, :step3])

      assert map_size(functions) == 3
      assert functions[:step1]
      assert functions[:step2]
      assert functions[:step3]
    end

    test "includes arity for each function" do
      functions = Metadata.extract_functions(SimpleWorkflow, [:step1, :step2, :step3])

      assert functions[:step1].arity == 1
      assert functions[:step2].arity == 2
      assert functions[:step3].arity == 3
    end

    test "marks functions as exported" do
      functions = Metadata.extract_functions(SimpleWorkflow, [:step1])

      assert functions[:step1].exported? == true
      assert functions[:step1].exists? == true
    end

    test "handles non-existent functions" do
      functions = Metadata.extract_functions(SimpleWorkflow, [:nonexistent])

      assert functions[:nonexistent].exists? == false
      assert functions[:nonexistent].exported? == false
      assert functions[:nonexistent].arity == nil
    end
  end

  describe "introspect_function/2" do
    test "returns function info for existing function" do
      info = Metadata.introspect_function(SimpleWorkflow, :step1)

      assert info.name == :step1
      assert info.arity == 1
      assert info.exported? == true
      assert info.exists? == true
    end

    test "returns not found info for non-existent function" do
      info = Metadata.introspect_function(SimpleWorkflow, :missing)

      assert info.name == :missing
      assert info.arity == nil
      assert info.exported? == false
      assert info.exists? == false
    end
  end

  describe "build_graph/1" do
    test "builds linear graph from simple timeline" do
      metadata = SimpleWorkflow.__workflow_metadata__()
      graph = Metadata.build_graph(metadata)

      assert graph[:step1].next == [:step2]
      assert graph[:step2].next == [:step3]
      assert graph[:step3].next == []
    end

    test "includes diverge actions in graph" do
      metadata = ComplexWorkflow.__workflow_metadata__()
      graph = Metadata.build_graph(metadata)

      assert :retry in graph[:validate].diverge_actions
      assert :failed in graph[:validate].diverge_actions
    end

    test "includes branch actions in graph" do
      metadata = ComplexWorkflow.__workflow_metadata__()
      graph = Metadata.build_graph(metadata)

      assert :high_value in graph[:process].branch_actions
      assert :standard in graph[:process].branch_actions
    end

    test "empty timeline produces empty graph" do
      metadata = %{timeline: [], diverges: %{}, branches: %{}}
      graph = Metadata.build_graph(metadata)

      assert graph == %{}
    end

    test "single step timeline produces graph with no next" do
      metadata = %{timeline: [:single], diverges: %{}, branches: %{}}
      graph = Metadata.build_graph(metadata)

      assert graph == %{}
    end
  end

  describe "workflow metadata integration" do
    test "workflow version is accessible via __workflow_metadata__" do
      metadata = SimpleWorkflow.__workflow_metadata__()

      assert is_binary(metadata.version)
      assert String.length(metadata.version) >= 7
    end

    test "metadata includes all required fields" do
      metadata = ComplexWorkflow.__workflow_metadata__()

      assert Map.has_key?(metadata, :timeline)
      assert Map.has_key?(metadata, :diverges)
      assert Map.has_key?(metadata, :branches)
      assert Map.has_key?(metadata, :version)
    end

    test "diverges are converted to map" do
      metadata = ComplexWorkflow.__workflow_metadata__()

      assert is_map(metadata.diverges)
      assert Map.has_key?(metadata.diverges, :validate)
    end

    test "branches are converted to map" do
      metadata = ComplexWorkflow.__workflow_metadata__()

      assert is_map(metadata.branches)
      assert Map.has_key?(metadata.branches, :process)
    end
  end
end

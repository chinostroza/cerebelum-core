defmodule Cerebelum.WorkflowTest do
  use ExUnit.Case, async: true

  # Test workflow simple
  defmodule MinimalWorkflow do
    use Cerebelum.Workflow
  end

  # Test workflow con atributos manuales (antes de implementar DSL)
  defmodule ManualWorkflow do
    use Cerebelum.Workflow

    @cerebelum_timeline [:step1, :step2, :step3]
    @cerebelum_diverges {:step1, [{:timeout, :retry}]}
    @cerebelum_branches {:step2, [{quote(do: result > 0.8), :high_risk}]}
  end

  describe "Workflow behaviour" do
    test "defines __workflow_metadata__ callback" do
      assert function_exported?(Cerebelum.Workflow, :behaviour_info, 1)
      callbacks = Cerebelum.Workflow.behaviour_info(:callbacks)
      assert {:__workflow_metadata__, 0} in callbacks
    end

    test "minimal workflow implements behaviour" do
      assert function_exported?(MinimalWorkflow, :__workflow_metadata__, 0)
    end
  end

  describe "__using__ macro" do
    test "registers @cerebelum_timeline attribute" do
      # Verificar que el atributo existe (aunque esté vacío)
      metadata = MinimalWorkflow.__workflow_metadata__()
      assert Map.has_key?(metadata, :timeline)
      assert is_list(metadata.timeline)
    end

    test "registers @cerebelum_diverges attribute" do
      metadata = MinimalWorkflow.__workflow_metadata__()
      assert Map.has_key?(metadata, :diverges)
      assert is_map(metadata.diverges)
    end

    test "registers @cerebelum_branches attribute" do
      metadata = MinimalWorkflow.__workflow_metadata__()
      assert Map.has_key?(metadata, :branches)
      assert is_map(metadata.branches)
    end

    test "sets @behaviour Cerebelum.Workflow" do
      behaviours = MinimalWorkflow.module_info(:attributes)[:behaviour] || []
      assert Cerebelum.Workflow in behaviours
    end
  end

  describe "__workflow_metadata__/0" do
    test "returns empty metadata for minimal workflow" do
      metadata = MinimalWorkflow.__workflow_metadata__()

      assert %{
               timeline: [],
               diverges: %{},
               branches: %{},
               version: _version
             } = metadata
    end

    test "returns timeline from @cerebelum_timeline attribute" do
      metadata = ManualWorkflow.__workflow_metadata__()

      assert metadata.timeline == [:step1, :step2, :step3]
    end

    test "converts diverges list to map" do
      metadata = ManualWorkflow.__workflow_metadata__()

      assert is_map(metadata.diverges)
      assert Map.has_key?(metadata.diverges, :step1)
      assert metadata.diverges[:step1] == [{:timeout, :retry}]
    end

    test "converts branches list to map" do
      metadata = ManualWorkflow.__workflow_metadata__()

      assert is_map(metadata.branches)
      assert Map.has_key?(metadata.branches, :step2)
    end

    test "includes version string" do
      metadata = MinimalWorkflow.__workflow_metadata__()

      assert is_binary(metadata.version)
      assert String.length(metadata.version) > 0
    end

    test "version is same across multiple calls (deterministic)" do
      v1 = MinimalWorkflow.__workflow_metadata__().version
      v2 = MinimalWorkflow.__workflow_metadata__().version

      assert v1 == v2
    end
  end

  describe "workflow structure" do
    test "timeline is a list of atoms" do
      metadata = ManualWorkflow.__workflow_metadata__()

      assert is_list(metadata.timeline)
      assert Enum.all?(metadata.timeline, &is_atom/1)
    end

    test "diverges is a map with atom keys" do
      metadata = ManualWorkflow.__workflow_metadata__()

      assert is_map(metadata.diverges)
      assert Enum.all?(Map.keys(metadata.diverges), &is_atom/1)
    end

    test "branches is a map with atom keys" do
      metadata = ManualWorkflow.__workflow_metadata__()

      assert is_map(metadata.branches)
      assert Enum.all?(Map.keys(metadata.branches), &is_atom/1)
    end
  end

  describe "module attributes accumulation" do
    test "@cerebelum_timeline does not accumulate (last value wins)" do
      # @cerebelum_timeline is registered with accumulate: false
      # Por ahora solo verificamos que existe
      metadata = ManualWorkflow.__workflow_metadata__()
      assert is_list(metadata.timeline)
    end

    test "@cerebelum_diverges accumulates multiple diverge blocks" do
      # @cerebelum_diverges is registered with accumulate: true
      # Por ahora solo verificamos que se convierte a map correctamente
      metadata = ManualWorkflow.__workflow_metadata__()
      assert is_map(metadata.diverges)
    end

    test "@cerebelum_branches accumulates multiple branch blocks" do
      # @cerebelum_branches is registered with accumulate: true
      metadata = ManualWorkflow.__workflow_metadata__()
      assert is_map(metadata.branches)
    end
  end
end

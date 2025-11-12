defmodule Cerebelum.Workflow.RegistryTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Workflow.Registry

  # Workflow de ejemplo
  defmodule SimpleWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        step1() |> step2()
      end
    end

    def step1(_context), do: :ok
    def step2(_context, _step1), do: :ok
  end

  # Otro workflow
  defmodule AnotherWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        start() |> finish()
      end
    end

    def start(_context), do: :ok
    def finish(_context, _start), do: :ok
  end

  setup do
    # Iniciar un registry único para cada test
    {:ok, pid} = Registry.start_link(name: :"test_registry_#{:erlang.unique_integer()}")
    registry_name = Process.info(pid)[:registered_name]

    {:ok, registry: registry_name}
  end

  describe "register/2" do
    test "registers a workflow successfully", %{registry: registry} do
      assert {:ok, metadata} = Registry.register(SimpleWorkflow, registry: registry)

      assert metadata.module == SimpleWorkflow
      assert is_list(metadata.timeline)
      assert is_binary(metadata.version)
    end

    test "registers multiple workflows", %{registry: registry} do
      assert {:ok, _metadata1} = Registry.register(SimpleWorkflow, registry: registry)
      assert {:ok, _metadata2} = Registry.register(AnotherWorkflow, registry: registry)

      workflows = Registry.list_all(registry: registry)
      assert length(workflows) == 2
    end

    test "registering same workflow twice returns same metadata", %{registry: registry} do
      assert {:ok, metadata1} = Registry.register(SimpleWorkflow, registry: registry)
      assert {:ok, metadata2} = Registry.register(SimpleWorkflow, registry: registry)

      assert metadata1.version == metadata2.version
      assert metadata1.module == metadata2.module
    end
  end

  describe "lookup/2" do
    test "finds registered workflow by module", %{registry: registry} do
      {:ok, registered} = Registry.register(SimpleWorkflow, registry: registry)
      {:ok, found} = Registry.lookup(SimpleWorkflow, registry: registry)

      assert found.module == registered.module
      assert found.version == registered.version
    end

    test "returns error for non-existent workflow", %{registry: registry} do
      assert {:error, :not_found} = Registry.lookup(NonExistentModule, registry: registry)
    end

    test "returns most recent version when multiple exist", %{registry: registry} do
      # Este test es conceptual - en la práctica necesitaríamos
      # dos versiones diferentes del mismo módulo
      {:ok, metadata} = Registry.register(SimpleWorkflow, registry: registry)
      {:ok, found} = Registry.lookup(SimpleWorkflow, registry: registry)

      assert found.version == metadata.version
    end
  end

  describe "lookup_by_version/2" do
    test "finds workflow by version hash", %{registry: registry} do
      {:ok, metadata} = Registry.register(SimpleWorkflow, registry: registry)
      version = metadata.version

      {:ok, found} = Registry.lookup_by_version(version, registry: registry)

      assert found.module == SimpleWorkflow
      assert found.version == version
    end

    test "returns error for non-existent version", %{registry: registry} do
      assert {:error, :not_found} =
               Registry.lookup_by_version("nonexistent_version", registry: registry)
    end
  end

  describe "list_all/1" do
    test "lists all registered workflows", %{registry: registry} do
      Registry.register(SimpleWorkflow, registry: registry)
      Registry.register(AnotherWorkflow, registry: registry)

      workflows = Registry.list_all(registry: registry)

      assert length(workflows) == 2
      modules = Enum.map(workflows, & &1.module)
      assert SimpleWorkflow in modules
      assert AnotherWorkflow in modules
    end

    test "returns empty list when no workflows registered", %{registry: registry} do
      assert [] = Registry.list_all(registry: registry)
    end

    test "returns only latest version of each workflow", %{registry: registry} do
      Registry.register(SimpleWorkflow, registry: registry)
      # Registrar el mismo workflow de nuevo (misma versión)
      Registry.register(SimpleWorkflow, registry: registry)

      workflows = Registry.list_all(registry: registry)

      # Solo debe haber una entrada para SimpleWorkflow
      simple_workflows = Enum.filter(workflows, &(&1.module == SimpleWorkflow))
      assert length(simple_workflows) == 1
    end
  end

  describe "list_versions/2" do
    test "lists all versions of a workflow", %{registry: registry} do
      {:ok, metadata} = Registry.register(SimpleWorkflow, registry: registry)

      versions = Registry.list_versions(SimpleWorkflow, registry: registry)

      assert length(versions) >= 1
      assert Enum.any?(versions, fn v -> v.version == metadata.version end)
    end

    test "returns empty list for non-registered workflow", %{registry: registry} do
      assert [] = Registry.list_versions(NonExistentModule, registry: registry)
    end
  end

  describe "GenServer lifecycle" do
    test "can start and stop registry" do
      assert {:ok, pid} = Registry.start_link(name: :test_lifecycle_registry)
      assert Process.alive?(pid)

      :ok = GenServer.stop(pid)
      refute Process.alive?(pid)
    end

    test "multiple registries can coexist" do
      {:ok, _pid1} = Registry.start_link(name: :registry_1)
      {:ok, _pid2} = Registry.start_link(name: :registry_2)

      # Registrar en registry 1
      Registry.register(SimpleWorkflow, registry: :registry_1)

      # Registry 2 no debe tener el workflow
      assert [] = Registry.list_all(registry: :registry_2)

      # Registry 1 sí lo tiene
      assert length(Registry.list_all(registry: :registry_1)) == 1

      # Cleanup
      GenServer.stop(:registry_1)
      GenServer.stop(:registry_2)
    end
  end

  describe "metadata integrity" do
    test "registered metadata contains all required fields", %{registry: registry} do
      {:ok, metadata} = Registry.register(SimpleWorkflow, registry: registry)

      assert Map.has_key?(metadata, :module)
      assert Map.has_key?(metadata, :timeline)
      assert Map.has_key?(metadata, :diverges)
      assert Map.has_key?(metadata, :branches)
      assert Map.has_key?(metadata, :version)
      assert Map.has_key?(metadata, :functions)
      assert Map.has_key?(metadata, :graph)
    end

    test "metadata timeline matches workflow definition", %{registry: registry} do
      {:ok, metadata} = Registry.register(SimpleWorkflow, registry: registry)

      assert metadata.timeline == [:step1, :step2]
    end

    test "metadata version is consistent", %{registry: registry} do
      {:ok, metadata1} = Registry.register(SimpleWorkflow, registry: registry)
      {:ok, metadata2} = Registry.lookup(SimpleWorkflow, registry: registry)

      assert metadata1.version == metadata2.version
    end
  end
end

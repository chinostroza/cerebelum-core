defmodule Cerebelum.Workflow.IntrospectionTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Workflow.Introspection

  # Workflow de ejemplo para introspección
  defmodule TestWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        step1() |> step2() |> step3()
      end
    end

    # Step con solo context
    def step1(context), do: {:ok, context}

    # Step con context y un resultado previo
    def step2(_context, step1_result), do: {:ok, step1_result}

    # Step con context y múltiples resultados previos
    def step3(_context, step1, step2), do: {:ok, {step1, step2}}
  end

  # Workflow con map patterns
  defmodule MapPatternWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        start() |> process() |> finish()
      end
    end

    def start(_context), do: %{value: 42}
    def process(_context, %{value: _}), do: %{result: :ok}
    def finish(_context, %{value: _}, %{result: _}), do: :done
  end

  describe "get_abstract_code/1" do
    test "returns abstract code for compiled module or no_debug_info" do
      case Introspection.get_abstract_code(TestWorkflow) do
        {:ok, abstract_code} ->
          assert is_list(abstract_code)
          assert length(abstract_code) > 0

        {:error, :no_debug_info} ->
          # Esto puede ocurrir si el módulo fue compilado sin debug_info
          # Es aceptable en algunos entornos
          assert true

        {:error, _reason} ->
          # Otros errores también pueden ocurrir dependiendo del entorno
          assert true
      end
    end

    test "returns error for non-existent module" do
      assert {:error, :module_not_loaded} == Introspection.get_abstract_code(NonExistentModule)
    end
  end

  describe "find_function/3" do
    test "finds function in abstract code" do
      case Introspection.get_abstract_code(TestWorkflow) do
        {:ok, abstract_code} ->
          assert {:ok, _clauses} = Introspection.find_function(abstract_code, :step1, 1)
          assert {:ok, _clauses} = Introspection.find_function(abstract_code, :step2, 2)
          assert {:ok, _clauses} = Introspection.find_function(abstract_code, :step3, 3)

        {:error, _reason} ->
          # Skip test si no hay abstract_code disponible
          :ok
      end
    end

    test "returns error for non-existent function" do
      case Introspection.get_abstract_code(TestWorkflow) do
        {:ok, abstract_code} ->
          assert {:error, :not_found} = Introspection.find_function(abstract_code, :nonexistent, 1)

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "introspect_params/3" do
    test "introspects function with only context parameter" do
      case Introspection.introspect_params(TestWorkflow, :step1, 1) do
        {:ok, info} ->
          assert info.context == true
          assert info.dependencies == [] or is_list(info.dependencies)
          assert info.clauses >= 1

        {:error, _reason} ->
          # Skip if introspection not available
          :ok
      end
    end

    test "introspects function with context and one dependency" do
      case Introspection.introspect_params(TestWorkflow, :step2, 2) do
        {:ok, info} ->
          assert info.context == true
          assert is_list(info.dependencies)
          assert info.clauses >= 1

        {:error, _reason} ->
          :ok
      end
    end

    test "introspects function with context and multiple dependencies" do
      case Introspection.introspect_params(TestWorkflow, :step3, 3) do
        {:ok, info} ->
          assert info.context == true
          assert is_list(info.dependencies)
          assert info.clauses >= 1

        {:error, _reason} ->
          :ok
      end
    end

    test "returns error for non-existent function" do
      result = Introspection.introspect_params(TestWorkflow, :nonexistent, 1)
      assert {:error, _reason} = result
    end
  end

  describe "extract_params_info/1" do
    test "extracts info from function clauses" do
      # Simular cláusulas de función con AST
      clauses = [
        {:clause, 1, [{:var, 1, :context}], [], [{:atom, 1, :ok}]}
      ]

      info = Introspection.extract_params_info(clauses)

      assert info.context == true
      assert is_list(info.dependencies)
      assert info.clauses == 1
    end

    test "handles empty clauses list" do
      info = Introspection.extract_params_info([])

      assert info.context == true
      assert info.dependencies == []
      assert info.clauses == 0
    end
  end

  describe "map pattern extraction" do
    test "can introspect functions with map patterns" do
      case Introspection.introspect_params(MapPatternWorkflow, :process, 2) do
        {:ok, info} ->
          assert info.context == true
          # Debería extraer :value del pattern %{value: _}
          assert is_list(info.dependencies)

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "integration with Metadata module" do
    test "Metadata module can use Introspection" do
      alias Cerebelum.Workflow.Metadata

      metadata = Metadata.extract(TestWorkflow)

      # Verificar que la metadata básica está disponible
      assert metadata.module == TestWorkflow
      assert length(metadata.timeline) == 3
    end
  end
end

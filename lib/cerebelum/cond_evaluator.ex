defmodule Cerebelum.CondEvaluator do
  @moduledoc """
  Evaluador de expresiones condicionales para bloques `branch()`.

  Soporta:
  - Operadores de comparación: `>`, `<`, `>=`, `<=`, `==`, `!=`
  - Operadores booleanos: `and`, `or`, `not`
  - Literales: `true`, `false`
  - Variables desde bindings

  ## Ejemplos

      iex> conditions = [
      ...>   {quote(do: score > 0.8), :high_risk},
      ...>   {quote(do: true), :default}
      ...> ]
      iex> CondEvaluator.evaluate(conditions, %{score: 0.9})
      {:ok, :high_risk}

      iex> CondEvaluator.eval_condition(quote(do: x > 5), %{x: 10})
      true
  """

  @doc """
  Evalúa una lista de condiciones contra bindings.

  Retorna la acción asociada a la primera condición que sea true,
  o `:no_match` si ninguna es true.

  ## Parámetros

  - `conditions` - Lista de `{condition_ast, action}` tuples
  - `bindings` - Map con variables disponibles (ej: `%{score: 0.9}`)

  ## Ejemplos

      iex> conditions = [{quote(do: score > 0.5), :pass}]
      iex> CondEvaluator.evaluate(conditions, %{score: 0.9})
      {:ok, :pass}

      iex> CondEvaluator.evaluate(conditions, %{score: 0.3})
      :no_match
  """
  @spec evaluate([{condition :: Macro.t(), action :: any()}], bindings :: map()) ::
          {:ok, any()} | :no_match
  def evaluate([], _bindings), do: :no_match

  def evaluate([{condition_ast, action} | rest], bindings) do
    if eval_condition(condition_ast, bindings) do
      {:ok, action}
    else
      evaluate(rest, bindings)
    end
  end

  @doc """
  Evalúa una sola expresión condicional a boolean.

  ## Parámetros

  - `condition_ast` - AST de la condición (ej: `quote(do: score > 0.8)`)
  - `bindings` - Map con variables (ej: `%{score: 0.9}`)

  ## Ejemplos

      iex> CondEvaluator.eval_condition(quote(do: x > 5), %{x: 10})
      true

      iex> CondEvaluator.eval_condition(quote(do: x > 5), %{x: 3})
      false

      iex> CondEvaluator.eval_condition(quote(do: true), %{})
      true
  """
  @spec eval_condition(condition :: Macro.t(), bindings :: map()) :: boolean()
  def eval_condition(condition_ast, bindings) do
    # Extraer todas las variables del AST
    variables = extract_variables(condition_ast)

    # Verificar que todas las variables existen en bindings
    case find_missing_variable(variables, bindings) do
      {:missing, var_name} ->
        condition_string = Macro.to_string(condition_ast)

        raise KeyError,
          key: var_name,
          term: bindings,
          message: """
          Variable '#{var_name}' not found in bindings.

          Available variables: #{inspect(Map.keys(bindings))}

          Condition: #{condition_string}
          """

      :ok ->
        # Todas las variables existen, evaluar
        binding_list = Map.to_list(bindings)
        condition_string = Macro.to_string(condition_ast)

        try do
          {result, _new_bindings} = Code.eval_string(condition_string, binding_list)
          !!result
        rescue
          e in CompileError ->
            reraise CompileError,
                    [
                      description: """
                      Invalid condition syntax: #{condition_string}

                      Error: #{e.description}
                      """,
                      file: e.file,
                      line: e.line
                    ],
                    __STACKTRACE__
        end
    end
  end

  # Extrae todas las variables del AST
  defp extract_variables(ast) do
    {_ast, vars} =
      Macro.prewalk(ast, [], fn
        # Variable: {name, metadata, context}
        {var_name, _meta, context} = node, acc when is_atom(var_name) and is_atom(context) ->
          {node, [var_name | acc]}

        # Otros nodos
        node, acc ->
          {node, acc}
      end)

    Enum.uniq(vars)
  end

  # Busca la primera variable que no está en bindings
  defp find_missing_variable([], _bindings), do: :ok

  defp find_missing_variable([var_name | rest], bindings) do
    if Map.has_key?(bindings, var_name) do
      find_missing_variable(rest, bindings)
    else
      {:missing, var_name}
    end
  end
end

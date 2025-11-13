defmodule Cerebelum.Workflow do
  @moduledoc """
  Behaviour para definir workflows determinísticos en Cerebelum.

  ## Uso

  Para crear un workflow, usa `use Cerebelum.Workflow`:

      defmodule MyWorkflow do
        use Cerebelum.Workflow

        workflow do
          timeline do
            step1() |> step2() |> step3()
          end

          diverge from: step1() do
            :timeout -> :retry
            {:error, _} -> :failed
          end

          branch after: step2(), on: result do
            result > 0.8 -> :high_risk_path
            true -> :default_path
          end
        end

        def step1(context), do: # ...
        def step2(context, prev_result), do: # ...
        def step3(context, step1, step2), do: # ...
      end

  ## Callbacks Requeridos

  - `__workflow_metadata__/0` - Retorna metadata del workflow (timeline, diverges, branches, version)

  ## Metadata del Workflow

  El callback `__workflow_metadata__/0` debe retornar un map con:

  - `:timeline` - Lista ordenada de steps (atoms)
  - `:diverges` - Map de `step_name => diverge_config`
  - `:branches` - Map de `step_name => branch_config`
  - `:version` - SHA256 del bytecode del módulo
  """

  @doc """
  Retorna la metadata del workflow.

  ## Ejemplo

      iex> MyWorkflow.__workflow_metadata__()
      %{
        timeline: [:step1, :step2, :step3],
        diverges: %{
          step1: [...pattern matches...]
        },
        branches: %{
          step2: [...conditional branches...]
        },
        version: "abc123..."
      }
  """
  @callback __workflow_metadata__() :: %{
              timeline: [atom()],
              diverges: %{atom() => term()},
              branches: %{atom() => term()},
              version: String.t()
            }

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Cerebelum.Workflow

      # Module attributes para acumular metadata durante compilación
      Module.register_attribute(__MODULE__, :cerebelum_timeline, accumulate: false)
      Module.register_attribute(__MODULE__, :cerebelum_diverges, accumulate: true)
      Module.register_attribute(__MODULE__, :cerebelum_branches, accumulate: true)

      # Import DSL macros
      use Cerebelum.Workflow.DSL

      @before_compile Cerebelum.Workflow
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    # Obtener los attributes en compile-time
    timeline = Module.get_attribute(env.module, :cerebelum_timeline) || []
    diverges = Module.get_attribute(env.module, :cerebelum_diverges) || []
    branches = Module.get_attribute(env.module, :cerebelum_branches) || []

    # Construir metadata para validación
    metadata = %{
      timeline: timeline,
      diverges: Enum.into(diverges, %{}),
      branches: Enum.into(branches, %{})
    }

    # Validar en compile-time
    Cerebelum.Workflow.Validator.validate(env.module, metadata, env)

    quote do
      # Esta función será inyectada automáticamente
      def __workflow_metadata__ do
        %{
          timeline: @cerebelum_timeline || [],
          diverges: (@cerebelum_diverges || []) |> Enum.into(%{}),
          branches: (@cerebelum_branches || []) |> Enum.into(%{}),
          version: Cerebelum.Workflow.Versioning.compute_version(__MODULE__)
        }
      end
    end
  end
end

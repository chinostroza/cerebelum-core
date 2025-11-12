defmodule Cerebelum.Workflow.DSL do
  @moduledoc """
  DSL para definir workflows en Cerebelum.

  Este módulo es un **orquestador** que re-exporta todas las macros del DSL.

  ## Arquitectura - Package by Feature

  Cada feature tiene su propio directorio:

  ```
  dsl/
  ├── workflow/
  │   ├── macro.ex
  │   └── parser.ex
  ├── timeline/
  │   ├── macro.ex
  │   └── parser.ex
  ├── diverge/
  │   ├── macro.ex
  │   └── parser.ex
  └── branch/
      ├── macro.ex
      └── parser.ex
  ```

  **Beneficio**: Si necesitas modificar `timeline`, solo tocas `dsl/timeline/`.
  TODO lo relacionado con timeline está en un solo lugar.

  ## Principios

  ### Package by Feature (no by Layer)
  - ✅ `dsl/timeline/` - Feature completa (macro + parser)
  - ❌ `dsl/macros/timeline_macro.ex` + `dsl/parsers/timeline_parser.ex` - Separado por layer

  ### CERO Acoplamiento entre Features
  - Modificar `timeline/` → No afecta `diverge/`
  - Borrar `diverge/` → `rm -rf dsl/diverge/`
  - Agregar feature → `mkdir dsl/nueva_feature/`

  ### Cohesión Máxima
  - TODO timeline está en `dsl/timeline/`
  - TODO diverge está en `dsl/diverge/`
  - Todo está donde lo esperas encontrar

  ## Ejemplo

      use Cerebelum.Workflow

      workflow do
        timeline do
          validate_order() |> process_payment() |> ship_order()
        end

        diverge from: validate_order() do
          {:error, :out_of_stock} -> back_to(:check_inventory)
          {:error, _} -> :failed
        end

        branch after: process_payment(), on: result do
          result.amount > 1000 -> :high_value_path
          true -> :standard_path
        end
      end
  """

  # Hacer las macros disponibles para `use Cerebelum.Workflow.DSL`
  defmacro __using__(_opts) do
    quote do
      import Cerebelum.Workflow.DSL.Workflow.WorkflowMacro
      import Cerebelum.Workflow.DSL.Timeline.TimelineMacro
      import Cerebelum.Workflow.DSL.Diverge.DivergeMacro
      import Cerebelum.Workflow.DSL.Branch.BranchMacro
    end
  end
end

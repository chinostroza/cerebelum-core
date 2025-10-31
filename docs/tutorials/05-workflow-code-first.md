# Tutorial 5: Workflow Code-First Approach

**Tiempo estimado:** 20 minutos
**Prerrequisitos:** [Tutorial 4 - Fault Tolerance](04-fault-tolerance.md)

## Introducción

Cerebelum usa un **approach code-first** para workflows: defines workflows con **código Elixir puro**, no con JSON o maps. Esto da:

- ✅ **Compile-time validation** - errores antes de runtime
- ✅ **Type safety** con Dialyzer
- ✅ **IDE support** - autocompletado, navegación, refactoring
- ✅ **Testing trivial** - son funciones normales
- ✅ **Documentación** estándar con `@doc`

## El Anti-Pattern: Maps/JSON

```elixir
# ❌ NO HACER ESTO (frágil, sin validación)
workflow = %{
  "name" => "process_order",
  "nodes" => %{
    "start" => %{"function" => "start_processing"},  # ← String mágico
    "validate" => %{"function" => "validate_order"}, # ← Typo pasa desapercibido
    "charge" => %{"function" => "charge_card"}
  },
  "edges" => [
    %{"from" => "start", "to" => "validate"},
    %{"from" => "validate", "to" => "charge"}
  ]
}

# Si hay un error, lo descubres en RUNTIME 😢
```

**Problemas:**
- No hay validación en compile-time
- Typos pasan desapercibidos
- Sin autocompletado del IDE
- Difícil refactorizar
- No puedes usar pattern matching

## El Approach Correcto: Código Elixir

### Ejemplo Básico

```elixir
defmodule ProcessOrderWorkflow do
  use Cerebelum.Workflow

  @doc "Start processing a new order"
  @spec start(map()) :: {:ok, map()} | {:error, term()}
  def start(input) do
    {:ok, %{
      order_id: input.order_id,
      user_id: input.user_id,
      items: input.items,
      total: calculate_total(input.items)
    }}
  end

  @doc "Validate order items and inventory"
  def validate_order(state) do
    case InventoryService.check_availability(state.items) do
      {:ok, _} ->
        {:ok, state}

      {:error, :out_of_stock, item} ->
        {:error, {:out_of_stock, item}}
    end
  end

  @doc "Charge customer's credit card"
  def charge_card(state) do
    case PaymentService.charge(state.total, state.user_id) do
      {:ok, charge_id} ->
        {:ok, Map.put(state, :charge_id, charge_id)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Send confirmation email"
  def send_confirmation(state) do
    EmailService.send_order_confirmation(state.user_id, state.order_id)
    {:ok, state}
  end

  @doc "Handle payment failure"
  def handle_payment_error(state) do
    EmailService.send_payment_failed(state.user_id)
    {:ok, %{state | status: :payment_failed}}
  end

  # Define el workflow graph usando funciones
  workflow do
    edge &start/1 -> &validate_order/1
    edge &validate_order/1 -> &charge_card/1, when: {:ok, _}
    edge &validate_order/1 -> &handle_payment_error/1, when: {:error, _}
    edge &charge_card/1 -> &send_confirmation/1, when: {:ok, _}
    edge &charge_card/1 -> &handle_payment_error/1, when: {:error, _}
  end
end
```

**Ventajas inmediatas:**
```elixir
# ✅ Compile-time error si función no existe
edge &non_existent_function/1 -> &start/1
# ** (CompileError) undefined function non_existent_function/1

# ✅ Compile-time error si arity incorrecta
edge &start/2 -> &validate_order/1
# ** (CompileError) function start/2 is undefined or private

# ✅ Pattern matching normal
def validate_order(%{items: items} = state) when is_list(items) do
  # ...
end

# ✅ Type specs estándar
@spec validate_order(map()) :: {:ok, map()} | {:error, term()}
```

## Llamar Workflows desde otros Workflows

```elixir
defmodule ParentWorkflow do
  use Cerebelum.Workflow

  def orchestrate(input) do
    # ✅ Referencia a módulo - compile-time checked!
    {:ok, result} = execute_workflow(ProcessOrderWorkflow, input)

    {:ok, Map.put(input, :order_result, result)}
  end

  def notify_shipping(state) do
    # ✅ Otro workflow
    execute_workflow(ShippingWorkflow, %{
      order_id: state.order_result.order_id,
      address: state.address
    })
  end

  workflow do
    edge &orchestrate/1 -> &notify_shipping/1
  end
end
```

**El compilador verifica:**
- `ProcessOrderWorkflow` existe
- `ShippingWorkflow` existe
- `execute_workflow/2` tiene la firma correcta

## Metadata y Configuración

```elixir
defmodule ConfigurableWorkflow do
  use Cerebelum.Workflow

  # Metadata del workflow
  @workflow_name "configurable_workflow"
  @workflow_version "1.0.0"
  @workflow_description "A workflow with configurable behavior"

  def fetch_data(state) do
    # ✅ Configuración granular por nodo
    result = activity(
      &ExternalAPI.fetch/1,
      args: [state.query],
      retry_policy: [
        max_attempts: 5,
        initial_interval: :timer.seconds(1),
        backoff_coefficient: 2.0,
        retryable_errors: [:network_error, :timeout]
      ],
      timeout: :timer.seconds(30)
    )

    {:ok, Map.put(state, :data, result)}
  end

  def process_data(state) do
    # Node que puede tardar días
    result = long_running_process(state.data)
    {:ok, Map.put(state, :result, result)}
  end

  workflow do
    # Configuración por edge
    edge &fetch_data/1 -> &process_data/1,
      when: {:ok, _},
      timeout: :timer.hours(24)  # Este edge puede tardar 24 horas
  end
end
```

## Pattern Matching Avanzado

```elixir
defmodule SmartWorkflow do
  use Cerebelum.Workflow

  # Pattern matching en la firma
  def handle_success(%{status: :completed, result: result} = state) do
    IO.puts("Success: #{inspect(result)}")
    {:ok, state}
  end

  def handle_error(%{status: :failed, error: error} = state) do
    Logger.error("Workflow failed: #{inspect(error)}")
    {:error, error}
  end

  # Guards
  def process_large_batch(%{items: items} = state) when length(items) > 100 do
    # Procesamiento especial para lotes grandes
    process_in_parallel(items)
    {:ok, state}
  end

  def process_large_batch(%{items: items} = state) do
    # Procesamiento normal
    process_sequential(items)
    {:ok, state}
  end

  # Multiple clauses
  def calculate_discount(%{user_type: :premium, total: total} = state) do
    {:ok, %{state | discount: total * 0.20}}
  end

  def calculate_discount(%{user_type: :regular, total: total} = state) when total > 100 do
    {:ok, %{state | discount: total * 0.10}}
  end

  def calculate_discount(state) do
    {:ok, %{state | discount: 0}}
  end
end
```

## Composición de Workflows

### Sub-workflows

```elixir
defmodule PaymentWorkflow do
  use Cerebelum.Workflow

  def charge_card(state) do
    # Lógica de pago
    {:ok, Map.put(state, :payment_status, :charged)}
  end

  def send_receipt(state) do
    # Enviar recibo
    {:ok, state}
  end

  workflow do
    edge &charge_card/1 -> &send_receipt/1
  end
end

defmodule OrderWorkflow do
  use Cerebelum.Workflow

  def create_order(state) do
    # Crear orden
    {:ok, Map.put(state, :order_id, generate_id())}
  end

  def process_payment(state) do
    # ✅ Ejecutar sub-workflow
    case execute_workflow(PaymentWorkflow, state) do
      {:ok, result} ->
        {:ok, Map.merge(state, result)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fulfill_order(state) do
    # Cumplir orden
    {:ok, state}
  end

  workflow do
    edge &create_order/1 -> &process_payment/1
    edge &process_payment/1 -> &fulfill_order/1, when: {:ok, _}
  end
end
```

### Workflows Paralelos

```elixir
defmodule ParallelWorkflow do
  use Cerebelum.Workflow

  def fetch_data(state) do
    {:ok, state}
  end

  def parallel_processing(state) do
    # ✅ Ejecutar múltiples workflows en paralelo
    results = parallel([
      fn -> execute_workflow(ProcessA, state) end,
      fn -> execute_workflow(ProcessB, state) end,
      fn -> execute_workflow(ProcessC, state) end
    ])

    {:ok, Map.put(state, :parallel_results, results)}
  end

  def aggregate_results(state) do
    aggregated = aggregate(state.parallel_results)
    {:ok, Map.put(state, :final_result, aggregated)}
  end

  workflow do
    edge &fetch_data/1 -> &parallel_processing/1
    edge &parallel_processing/1 -> &aggregate_results/1
  end
end
```

## Testing Workflows

Como son funciones normales, testing es trivial:

```elixir
defmodule ProcessOrderWorkflowTest do
  use ExUnit.Case, async: true

  alias ProcessOrderWorkflow

  describe "start/1" do
    test "initializes order state correctly" do
      input = %{
        order_id: "ORD-123",
        user_id: "USR-456",
        items: [
          %{id: "ITEM-1", price: 10.0},
          %{id: "ITEM-2", price: 20.0}
        ]
      }

      assert {:ok, state} = ProcessOrderWorkflow.start(input)
      assert state.order_id == "ORD-123"
      assert state.total == 30.0
    end
  end

  describe "validate_order/1" do
    test "succeeds when items are in stock" do
      state = %{items: [%{id: "ITEM-1"}]}

      expect(InventoryService, :check_availability, fn _ ->
        {:ok, :available}
      end)

      assert {:ok, ^state} = ProcessOrderWorkflow.validate_order(state)
    end

    test "fails when items are out of stock" do
      state = %{items: [%{id: "OUT-OF-STOCK"}]}

      expect(InventoryService, :check_availability, fn _ ->
        {:error, :out_of_stock, "OUT-OF-STOCK"}
      end)

      assert {:error, {:out_of_stock, "OUT-OF-STOCK"}} =
        ProcessOrderWorkflow.validate_order(state)
    end
  end

  describe "full workflow" do
    test "completes successfully on happy path" do
      input = %{
        order_id: "ORD-123",
        user_id: "USR-456",
        items: [%{id: "ITEM-1", price: 10.0}]
      }

      # Mocks para todos los servicios externos
      expect(InventoryService, :check_availability, fn _ -> {:ok, :available} end)
      expect(PaymentService, :charge, fn _, _ -> {:ok, "CHG-789"} end)
      expect(EmailService, :send_order_confirmation, fn _, _ -> :ok end)

      {:ok, execution_id} = Cerebelum.start_workflow(ProcessOrderWorkflow, input)

      assert_receive {:execution_completed, ^execution_id}, 5_000
    end
  end
end
```

## Debugging y Observabilidad

```elixir
defmodule DebuggableWorkflow do
  use Cerebelum.Workflow

  require Logger

  def debug_node(state) do
    # ✅ Logging normal de Elixir
    Logger.info("Entering debug_node", state: state)

    result = do_something(state)

    # ✅ Métricas con Telemetry
    :telemetry.execute([:my_app, :workflow, :debug_node], %{
      duration: System.monotonic_time()
    }, %{result: result})

    # ✅ IO.inspect para debugging
    IO.inspect(result, label: "Debug Node Result")

    {:ok, result}
  end

  def instrumented_node(state) do
    # El macro `use Cerebelum.Workflow` instrumenta automáticamente
    # Esto emite eventos de telemetry:
    # - [:cerebelum, :workflow, :node, :start]
    # - [:cerebelum, :workflow, :node, :stop]
    # - [:cerebelum, :workflow, :node, :exception]

    {:ok, state}
  end
end
```

## Documentación

```elixir
defmodule WellDocumentedWorkflow do
  @moduledoc """
  Processes customer orders from creation to fulfillment.

  ## Features
  - Validates inventory availability
  - Processes payment securely
  - Sends confirmation emails
  - Handles errors gracefully

  ## Example
      iex> Cerebelum.start_workflow(WellDocumentedWorkflow, %{
      ...>   order_id: "ORD-123",
      ...>   user_id: "USR-456",
      ...>   items: [%{id: "ITEM-1", price: 10.0}]
      ...> })
      {:ok, "exec-abc-123"}
  """

  use Cerebelum.Workflow

  @doc """
  Initializes the order workflow.

  ## Parameters
  - `input.order_id` - Unique order identifier
  - `input.user_id` - Customer ID
  - `input.items` - List of items with prices

  ## Returns
  - `{:ok, state}` with calculated total
  """
  @spec start(map()) :: {:ok, map()}
  def start(input) do
    {:ok, %{
      order_id: input.order_id,
      user_id: input.user_id,
      items: input.items,
      total: calculate_total(input.items)
    }}
  end

  # ... más funciones documentadas ...

  workflow do
    @doc "Workflow graph showing the order processing flow"
    edge &start/1 -> &validate_order/1
    edge &validate_order/1 -> &charge_card/1, when: {:ok, _}
  end
end
```

## El Macro `use Cerebelum.Workflow`

Internamente, el macro hace:

```elixir
defmacro __using__(opts) do
  quote do
    @behaviour Cerebelum.Workflow

    # El módulo ES el workflow
    def __workflow_module__, do: __MODULE__
    def __workflow_name__ do
      __MODULE__
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
    end

    # Import DSL
    import Cerebelum.Workflow.DSL

    # Registro en compile-time
    @before_compile Cerebelum.Workflow.Compiler

    # Auto-instrumentación con Telemetry
    def __before_compile_instrumentation__ do
      # Wrap cada función del workflow con telemetry
    end
  end
end
```

**En compile-time, el macro:**
1. Valida que todas las funciones referenciadas existan
2. Valida que los edges formen un grafo válido
3. Genera metadata del workflow
4. Instrumenta funciones con telemetry
5. Registra el workflow en el registry

## Comparación: Temporal.io vs Cerebelum

**Temporal.io (Python):**
```python
@workflow.defn
class OrderWorkflow:
    @workflow.run
    async def run(self, order_id: str) -> dict:
        # Código imperativo
        order = await workflow.execute_activity(
            create_order,
            order_id,
            start_to_close_timeout=timedelta(seconds=10)
        )

        await workflow.sleep(timedelta(days=1))

        return {"order": order}
```

**Cerebelum (Elixir):**
```elixir
defmodule OrderWorkflow do
  use Cerebelum.Workflow

  # Código funcional
  def create_order(state) do
    activity(&create_order_impl/1,
      args: [state.order_id],
      timeout: :timer.seconds(10)
    )
  end

  def wait_one_day(state) do
    {:sleep, days: 1, continue_with: state}
  end

  workflow do
    edge &create_order/1 -> &wait_one_day/1
  end
end
```

**Ventajas de Cerebelum:**
- ✅ Pattern matching nativo
- ✅ Pipe operator
- ✅ Guards
- ✅ Multiple clauses
- ✅ Compile-time validation completa
- ✅ OTP supervision tree nativo

## Resumen

| Característica | Beneficio |
|----------------|-----------|
| **Funciones normales** | Testing trivial, documentación estándar |
| **Compile-time validation** | Errores antes de runtime |
| **Module = Workflow** | No strings mágicos, refactoring seguro |
| **Function references** | `&start/1` validado por compilador |
| **Pattern matching** | Expresividad máxima |
| **Type specs** | Dialyzer analysis |
| **@doc** | Documentación estándar |

## Ejercicio Final

Crea un workflow para reservar viajes que:
1. Verifica disponibilidad de vuelo y hotel en paralelo
2. Si ambos disponibles, carga el pago
3. Si el pago falla, cancela vuelo y hotel (saga)
4. Envía confirmación

<details>
<summary>Ver solución</summary>

```elixir
defmodule TravelBookingWorkflow do
  use Cerebelum.Workflow

  def start(input) do
    {:ok, %{
      user_id: input.user_id,
      flight_id: input.flight_id,
      hotel_id: input.hotel_id,
      total: input.total
    }}
  end

  def check_availability(state) do
    results = parallel([
      fn -> FlightService.check_availability(state.flight_id) end,
      fn -> HotelService.check_availability(state.hotel_id) end
    ])

    case results do
      [{:ok, flight}, {:ok, hotel}] ->
        {:ok, Map.merge(state, %{flight: flight, hotel: hotel})}

      _ ->
        {:error, :not_available}
    end
  end

  def book_services(state) do
    with {:ok, flight_booking} <- FlightService.book(state.flight),
         {:ok, hotel_booking} <- HotelService.book(state.hotel) do
      {:ok, Map.merge(state, %{
        flight_booking: flight_booking,
        hotel_booking: hotel_booking
      })}
    else
      error -> error
    end
  end

  def charge_payment(state) do
    case PaymentService.charge(state.total, state.user_id) do
      {:ok, charge_id} ->
        {:ok, Map.put(state, :charge_id, charge_id)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def send_confirmation(state) do
    EmailService.send_booking_confirmation(state.user_id, state)
    {:ok, state}
  end

  # Compensaciones
  def cancel_bookings(state) do
    if state[:hotel_booking] do
      HotelService.cancel(state.hotel_booking.id)
    end

    if state[:flight_booking] do
      FlightService.cancel(state.flight_booking.id)
    end

    {:ok, %{state | status: :cancelled}}
  end

  workflow do
    edge &start/1 -> &check_availability/1
    edge &check_availability/1 -> &book_services/1, when: {:ok, _}
    edge &book_services/1 -> &charge_payment/1, when: {:ok, _}
    edge &charge_payment/1 -> &send_confirmation/1, when: {:ok, _}

    # Saga: compensar en caso de fallo
    edge &charge_payment/1 -> &cancel_bookings/1, when: {:error, _}
    edge &book_services/1 -> &cancel_bookings/1, when: {:error, _}
  end
end
```
</details>

## Conclusión

El approach code-first de Cerebelum te da:
- 🚀 Productividad (IDE, refactoring, testing)
- 🛡️ Seguridad (compile-time validation, types)
- 📚 Mantenibilidad (código Elixir estándar)
- 🔧 Debugging (tools normales de Elixir)

**Todo el poder de Elixir, sin sacrificar la resiliencia de workflows.**

## Referencias

- [Elixir Guides - Modules and Functions](https://elixir-lang.org/getting-started/modules-and-functions.html)
- [José Valim - Designing Elixir Systems with OTP](https://pragprog.com/titles/jgotp/designing-elixir-systems-with-otp/)
- [Temporal.io - Workflow Definition](https://docs.temporal.io/workflows)

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
  def handle_payment_error(ctx, state) do
    EmailService.send_payment_failed(state.user_id)
    %{state | status: :payment_failed}
  end

  # Define el workflow usando sintaxis Compose-style
  workflow() do
    timeline() do
      start()
      |> validate_order()
      |> charge_card()
      |> send_confirmation()
      |> done()
    end

    diverge(validate_order) do
      :out_of_stock -> handle_payment_error() |> failed()
    end

    diverge(charge_card) do
      :payment_failed -> handle_payment_error() |> failed()
      :timeout -> retry(3, delay: 2000) |> charge_card()
    end
  end
end
```

**Ventajas inmediatas:**
```elixir
# ✅ Compile-time error si función no existe
timeline() do
  non_existent_function() |> start()
end
# ** (CompileError) undefined function non_existent_function/0

# ✅ Compile-time error si arity incorrecta
def start(ctx, state), do: state  # Firma correcta: (ctx, %{step_name: result})
def start(wrong_args), do: wrong_args  # Error en compile-time

# ✅ Pattern matching normal
def validate_order(ctx, %{start: state} = all_results) when is_list(state.items) do
  # Acceso a resultados previos por nombre
end

# ✅ Type specs estándar
@spec validate_order(Context.t(), map()) :: map() | no_return()
```

## Llamar Workflows desde otros Workflows

```elixir
defmodule ParentWorkflow do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> orchestrate()
      |> notify_shipping()
      |> done()
    end
  end

  def start(input), do: input

  def orchestrate(ctx, %{start: input}) do
    # ✅ Referencia a módulo - compile-time checked!
    result = subworkflow(ProcessOrderWorkflow) do
      input input
    end

    Map.put(input, :order_result, result)
  end

  def notify_shipping(ctx, %{orchestrate: state}) do
    # ✅ Otro workflow
    subworkflow(ShippingWorkflow) do
      input %{
        order_id: state.order_result.order_id,
        address: state.address
      }
    end
  end
end
```

**El compilador verifica:**
- `ProcessOrderWorkflow` existe
- `ShippingWorkflow` existe
- `subworkflow/2` tiene la firma correcta

## Metadata y Configuración

```elixir
defmodule ConfigurableWorkflow do
  use Cerebelum.Workflow

  # Metadata del workflow
  @workflow_name "configurable_workflow"
  @workflow_version "1.0.0"
  @workflow_description "A workflow with configurable behavior"

  workflow() do
    timeline() do
      start()
      |> fetch_data()
      |> process_data()
      |> done()
    end

    # Configuración de retry por step
    diverge(fetch_data) do
      :network_error ->
        retry() do
          attempts 5
          delay fn attempt -> attempt * 1000 end
          max_delay 30_000
          backoff :exponential
        end
        |> fetch_data()

      :timeout -> retry(3, delay: 2000) |> fetch_data()
    end
  end

  def start(input), do: input

  def fetch_data(ctx, %{start: state}) do
    # ✅ Llamada externa con manejo de errores
    case ExternalAPI.fetch(state.query) do
      {:ok, data} -> Map.put(state, :data, data)
      {:error, reason} -> error(reason)
    end
  end

  def process_data(ctx, %{fetch_data: state}) do
    # Step que puede tardar días
    result = long_running_process(state.data)
    Map.put(state, :result, result)
  end
end
```

## Pattern Matching Avanzado

```elixir
defmodule SmartWorkflow do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> process_batch()
      |> calculate_discount()
      |> handle_result()
      |> done()
    end

    branch(handle_result) do
      status == :completed -> finalize()
      status == :failed -> handle_error()
    end
  end

  # Pattern matching en la firma con segundo parámetro
  def handle_result(ctx, %{calculate_discount: %{status: :completed, result: result} = state}) do
    IO.puts("Success: #{inspect(result)}")
    state
  end

  def handle_error(ctx, %{calculate_discount: %{status: :failed, error: error} = state}) do
    Logger.error("Workflow failed: #{inspect(error)}")
    error(error)
  end

  # Guards - múltiples clauses
  def process_batch(ctx, %{start: %{items: items} = state}) when length(items) > 100 do
    # Procesamiento especial para lotes grandes
    result = process_in_parallel(items)
    %{state | processed: result}
  end

  def process_batch(ctx, %{start: %{items: items} = state}) do
    # Procesamiento normal
    result = process_sequential(items)
    %{state | processed: result}
  end

  # Multiple clauses para diferentes tipos de usuario
  def calculate_discount(ctx, %{process_batch: %{user_type: :premium, total: total} = state}) do
    %{state | discount: total * 0.20}
  end

  def calculate_discount(ctx, %{process_batch: %{user_type: :regular, total: total} = state})
      when total > 100 do
    %{state | discount: total * 0.10}
  end

  def calculate_discount(ctx, %{process_batch: state}) do
    %{state | discount: 0}
  end
end
```

## Composición de Workflows

### Sub-workflows

```elixir
defmodule PaymentWorkflow do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> charge_card()
      |> send_receipt()
      |> done()
    end
  end

  def start(input), do: input

  def charge_card(ctx, %{start: state}) do
    # Lógica de pago
    Map.put(state, :payment_status, :charged)
  end

  def send_receipt(ctx, %{charge_card: state}) do
    # Enviar recibo
    state
  end
end

defmodule OrderWorkflow do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> create_order()
      |> process_payment()
      |> fulfill_order()
      |> done()
    end

    diverge(process_payment) do
      :payment_failed -> handle_payment_error() |> failed()
    end
  end

  def start(input), do: input

  def create_order(ctx, %{start: state}) do
    # Crear orden
    Map.put(state, :order_id, generate_id())
  end

  def process_payment(ctx, %{create_order: state}) do
    # ✅ Ejecutar sub-workflow
    result = subworkflow(PaymentWorkflow) do
      input state
    end

    Map.merge(state, result)
  end

  def fulfill_order(ctx, %{process_payment: state}) do
    # Cumplir orden
    state
  end

  def handle_payment_error(ctx, state) do
    %{state | status: :payment_error}
  end
end
```

### Workflows Paralelos

```elixir
defmodule ParallelWorkflow do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> fetch_data()
      |> parallel_processing()
      |> aggregate_results()
      |> done()
    end
  end

  def start(input), do: input

  def fetch_data(ctx, %{start: state}) do
    state
  end

  def parallel_processing(ctx, %{fetch_data: state}) do
    # ✅ Ejecutar múltiples agentes en paralelo
    parallel() do
      agents [
        {ProcessA, state},
        {ProcessB, state},
        {ProcessC, state}
      ]
      timeout 60_000
      on_failure :continue
    end
  end

  def aggregate_results(ctx, %{parallel_processing: results}) do
    aggregated = aggregate(results)
    Map.put(%{}, :final_result, aggregated)
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

      assert state = ProcessOrderWorkflow.start(input)
      assert state.order_id == "ORD-123"
      assert state.total == 30.0
    end
  end

  describe "validate_order/2" do
    test "succeeds when items are in stock" do
      ctx = %Cerebelum.Context{}
      prev_results = %{start: %{items: [%{id: "ITEM-1"}]}}

      expect(InventoryService, :check_availability, fn _ ->
        {:ok, :available}
      end)

      assert state = ProcessOrderWorkflow.validate_order(ctx, prev_results)
      assert state.items == [%{id: "ITEM-1"}]
    end

    test "fails when items are out of stock" do
      ctx = %Cerebelum.Context{}
      prev_results = %{start: %{items: [%{id: "OUT-OF-STOCK"}]}}

      expect(InventoryService, :check_availability, fn _ ->
        {:error, :out_of_stock, "OUT-OF-STOCK"}
      end)

      assert_raise Cerebelum.WorkflowError, fn ->
        ProcessOrderWorkflow.validate_order(ctx, prev_results)
      end
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

  workflow() do
    @doc "Workflow graph showing the order processing flow"

    timeline() do
      start()
      |> validate_order()
      |> charge_card()
      |> done()
    end

    diverge(validate_order) do
      :invalid_data -> failed()
    end

    diverge(charge_card) do
      :payment_failed -> failed()
    end
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

  workflow() do
    timeline() do
      start()
      |> create_order()
      |> wait_one_day()
      |> done()
    end

    diverge(create_order) do
      :timeout -> retry(3, delay: 2000) |> create_order()
    end
  end

  def start(input), do: input

  # Código funcional
  def create_order(ctx, %{start: state}) do
    # Llamada externa con timeout
    case create_order_impl(state.order_id) do
      {:ok, order} -> order
      {:error, :timeout} -> error(:timeout)
    end
  end

  def wait_one_day(ctx, %{create_order: state}) do
    # Esperar un día (sin bloquear el BEAM)
    receive_signal() do
      type :continue
      timeout :timer.hours(24)
      on_timeout -> state  # Continuar automáticamente
    end
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

  workflow() do
    timeline() do
      start()
      |> check_availability()
      |> book_services()
      |> charge_payment()
      |> send_confirmation()
      |> done()
    end

    # Manejo de errores con compensación (Saga pattern)
    diverge(check_availability) do
      :not_available -> failed()
    end

    diverge(book_services) do
      :booking_failed -> cancel_bookings() |> failed()
    end

    diverge(charge_payment) do
      :payment_failed -> cancel_bookings() |> failed()
      :timeout -> retry(3, delay: 2000) |> charge_payment()
    end
  end

  def start(input) do
    %{
      user_id: input.user_id,
      flight_id: input.flight_id,
      hotel_id: input.hotel_id,
      total: input.total
    }
  end

  def check_availability(ctx, %{start: state}) do
    # Verificar en paralelo
    parallel() do
      agents [
        {FlightService, %{flight_id: state.flight_id}},
        {HotelService, %{hotel_id: state.hotel_id}}
      ]
      timeout 30_000
    end
    |> case do
      %{FlightService: {:ok, flight}, HotelService: {:ok, hotel}} ->
        Map.merge(state, %{flight: flight, hotel: hotel})

      _ ->
        error(:not_available)
    end
  end

  def book_services(ctx, %{check_availability: state}) do
    with {:ok, flight_booking} <- FlightService.book(state.flight),
         {:ok, hotel_booking} <- HotelService.book(state.hotel) do
      Map.merge(state, %{
        flight_booking: flight_booking,
        hotel_booking: hotel_booking
      })
    else
      {:error, _} -> error(:booking_failed)
    end
  end

  def charge_payment(ctx, %{book_services: state}) do
    case PaymentService.charge(state.total, state.user_id) do
      {:ok, charge_id} ->
        Map.put(state, :charge_id, charge_id)

      {:error, :timeout} ->
        error(:timeout)

      {:error, reason} ->
        error(:payment_failed)
    end
  end

  def send_confirmation(ctx, %{charge_payment: state}) do
    EmailService.send_booking_confirmation(state.user_id, state)
    state
  end

  # Compensación (Saga pattern)
  def cancel_bookings(ctx, state) do
    if state[:hotel_booking] do
      HotelService.cancel(state.hotel_booking.id)
    end

    if state[:flight_booking] do
      FlightService.cancel(state.flight_booking.id)
    end

    %{state | status: :cancelled}
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

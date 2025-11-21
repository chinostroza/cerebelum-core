# Signal System Design - v0.3.0

**Module:** cerebelum-core
**Target Version:** 0.3.0
**Status:** Design Phase
**Author:** Development Team
**Date:** 2025-11-21

---

## 1. Executive Summary

The Signal System enables workflows to **hibernate and wait for external events** from any source:
- 📱 Mobile approvals (HITL)
- 🌐 Webhooks (Stripe, external APIs)
- 🤖 IoT sensor events
- 🔔 System notifications

**Key Principles:**
- ✅ **Backward Compatible** - Existing `{:wait_for_approval, ...}` continues working
- ✅ **Generic & Extensible** - Works with any external event
- ✅ **HTTP-First** - REST API for signals
- ✅ **Event Sourced** - Complete audit trail
- ✅ **Resilient** - Signals can arrive before or after wait
- ✅ **Tested** - >90% test coverage

---

## 2. Architecture Overview

### 2.1 High-Level Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Workflow Execution                        │
│                                                              │
│  step1() → step2() → wait_for_signal("payment_confirmed")  │
│                              ↓                               │
│                    [HIBERNATE - State: :waiting_for_signal] │
│                              ↓                               │
│                    [Waiting for external event...]          │
└─────────────────────────────────────────────────────────────┘
                               ↓
                    External System Sends Signal
                               ↓
┌─────────────────────────────────────────────────────────────┐
│  POST /api/v1/executions/{execution_id}/signals/{name}     │
│  Body: { "data": { "amount": 100, "status": "confirmed" } }│
└─────────────────────────────────────────────────────────────┘
                               ↓
                    Signal Delivery to Workflow
                               ↓
┌─────────────────────────────────────────────────────────────┐
│                    Workflow Resumes                          │
│                                                              │
│  step3(signal_data) → step4() → completed                   │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Core Components

```
┌──────────────────────────────────────────────────────────────┐
│                   HTTP API Layer (Phoenix)                    │
│  - POST /api/v1/executions/:id/signals/:name                 │
│  - GET  /api/v1/executions/:id/pending_signals               │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│              Cerebelum.Execution.SignalDispatcher             │
│  - Validates signal                                           │
│  - Finds execution PID via ExecutionRegistry                  │
│  - Delivers signal or queues if not waiting yet              │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│              Cerebelum.Infrastructure.SignalQueue             │
│  - ETS-based in-memory queue                                 │
│  - Stores signals that arrive before wait_for_signal         │
│  - Auto-cleanup on timeout or delivery                       │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│          Cerebelum.Infrastructure.ExecutionRegistry           │
│  - Registry mapping: execution_id → PID                      │
│  - Auto-cleanup on process death                             │
│  - Used for signal delivery                                  │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│              Execution Engine (gen_statem)                    │
│  - New state: :waiting_for_signal                            │
│  - Handles {:signal, name, data} events                      │
│  - Timeout management                                        │
└──────────────────────────────────────────────────────────────┘
```

---

## 3. Detailed Component Design

### 3.1 Engine Extensions

#### 3.1.1 New State: `:waiting_for_signal`

```elixir
# State machine diagram
:executing_step
    ↓ (step returns {:wait_for_signal, name, opts})
:waiting_for_signal
    ↓ (receives {:signal, name, data})
:executing_step (next step)
```

#### 3.1.2 Engine.Data Extensions

```elixir
# lib/cerebelum/execution/engine/data.ex

@type t :: %__MODULE__{
  # ... existing fields ...

  # Signal-specific fields
  signal_name: String.t() | nil,
  signal_timeout_ms: non_neg_integer() | nil,
  signal_started_at: integer() | nil,
  signal_step_name: atom() | nil
}

defstruct [
  # ... existing fields ...
  signal_name: nil,
  signal_timeout_ms: nil,
  signal_started_at: nil,
  signal_step_name: nil
]
```

#### 3.1.3 Step Return Value

```elixir
# In workflow step
def wait_for_payment(_ctx, prev_result) do
  {:wait_for_signal, "payment_confirmed",
   [timeout_seconds: 3600, metadata: %{order_id: 123}]}
end

# Returns:
# - signal_name: "payment_confirmed"
# - timeout: 1 hour
# - metadata: Optional data to store
```

### 3.2 ExecutionRegistry

**Purpose:** Map `execution_id` → `PID` for signal delivery

```elixir
# lib/cerebelum/infrastructure/execution_registry.ex

defmodule Cerebelum.Infrastructure.ExecutionRegistry do
  @moduledoc """
  Registry for mapping execution IDs to process PIDs.

  Uses Elixir Registry with auto-cleanup on process termination.
  """

  @registry_name __MODULE__

  def start_link do
    Registry.start_link(keys: :unique, name: @registry_name)
  end

  @doc "Register a new execution"
  @spec register(String.t(), pid()) :: {:ok, pid()} | {:error, term()}
  def register(execution_id, pid) do
    case Registry.register(@registry_name, execution_id, nil) do
      {:ok, _} -> {:ok, pid}
      {:error, {:already_registered, existing_pid}} ->
        {:error, {:already_registered, existing_pid}}
    end
  end

  @doc "Find PID for an execution_id"
  @spec find(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def find(execution_id) do
    case Registry.lookup(@registry_name, execution_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc "Unregister execution (called on process termination)"
  @spec unregister(String.t()) :: :ok
  def unregister(execution_id) do
    Registry.unregister(@registry_name, execution_id)
  end
end
```

**Auto-registration:** Engine registers itself on start:

```elixir
# In Engine.init/1
def init(opts) do
  # ... existing code ...

  # Register in ExecutionRegistry
  ExecutionRegistry.register(context.execution_id, self())

  # ... continue ...
end
```

### 3.3 SignalQueue

**Purpose:** Queue signals that arrive BEFORE `wait_for_signal`

**Scenario:**
```
1. Webhook sends signal at T=0
2. Workflow reaches wait_for_signal at T=100ms
3. Signal must be delivered when workflow starts waiting
```

**Implementation:**

```elixir
# lib/cerebelum/infrastructure/signal_queue.ex

defmodule Cerebelum.Infrastructure.SignalQueue do
  @moduledoc """
  ETS-based queue for pending signals.

  Stores signals that arrive before wait_for_signal is called.
  Auto-expires signals after configurable TTL.
  """

  use GenServer

  @table_name :cerebelum_signal_queue
  @default_ttl_ms 60_000  # 1 minute

  # Table schema: {execution_id, signal_name, data, timestamp}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    :ets.new(@table_name, [:set, :public, :named_table])
    schedule_cleanup()
    {:ok, %{}}
  end

  @doc "Enqueue a signal for future delivery"
  @spec enqueue(String.t(), String.t(), map()) :: :ok
  def enqueue(execution_id, signal_name, data) do
    timestamp = System.monotonic_time(:millisecond)
    key = {execution_id, signal_name}
    :ets.insert(@table_name, {key, data, timestamp})
    :ok
  end

  @doc "Dequeue signal if available"
  @spec dequeue(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def dequeue(execution_id, signal_name) do
    key = {execution_id, signal_name}
    case :ets.lookup(@table_name, key) do
      [{^key, data, _timestamp}] ->
        :ets.delete(@table_name, key)
        {:ok, data}
      [] ->
        {:error, :not_found}
    end
  end

  @doc "Check if signal is pending"
  @spec pending?(String.t(), String.t()) :: boolean()
  def pending?(execution_id, signal_name) do
    key = {execution_id, signal_name}
    :ets.member(@table_name, key)
  end

  # Cleanup expired signals every 30 seconds
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 30_000)
  end

  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)
    expired_keys =
      :ets.select(@table_name, [
        {{{:"$1", :"$2"}, :_, :"$3"},
         [{:<, :"$3", {:-, now, @default_ttl_ms}}],
         [{{:"$1", :"$2"}}]}
      ])

    Enum.each(expired_keys, fn key -> :ets.delete(@table_name, key) end)
    schedule_cleanup()
    {:noreply, state}
  end
end
```

### 3.4 SignalDispatcher

**Purpose:** Orchestrate signal delivery

```elixir
# lib/cerebelum/execution/signal_dispatcher.ex

defmodule Cerebelum.Execution.SignalDispatcher do
  @moduledoc """
  Handles signal delivery to workflow executions.

  Flow:
  1. Find execution PID via ExecutionRegistry
  2. Check if execution is waiting for this signal
  3. If waiting → deliver immediately
  4. If not waiting → queue in SignalQueue
  """

  alias Cerebelum.Infrastructure.{ExecutionRegistry, SignalQueue}
  alias Cerebelum.Execution.Engine

  @doc "Dispatch a signal to an execution"
  @spec dispatch(String.t(), String.t(), map()) ::
    {:ok, :delivered} | {:ok, :queued} | {:error, term()}
  def dispatch(execution_id, signal_name, signal_data) do
    case ExecutionRegistry.find(execution_id) do
      {:ok, pid} ->
        # Check if process is waiting for this signal
        if waiting_for_signal?(pid, signal_name) do
          # Deliver immediately
          :gen_statem.call(pid, {:signal, signal_name, signal_data})
          {:ok, :delivered}
        else
          # Queue for later delivery
          SignalQueue.enqueue(execution_id, signal_name, signal_data)
          {:ok, :queued}
        end

      {:error, :not_found} ->
        # Execution not running - queue signal (might start soon)
        SignalQueue.enqueue(execution_id, signal_name, signal_data)
        {:ok, :queued}
    end
  end

  @doc "Check if execution is waiting for a specific signal"
  @spec waiting_for_signal?(pid(), String.t()) :: boolean()
  def waiting_for_signal?(pid, signal_name) do
    status = Engine.get_status(pid)
    status.state == :waiting_for_signal && status.signal_name == signal_name
  end
end
```

### 3.5 State Handler: `:waiting_for_signal`

```elixir
# lib/cerebelum/execution/engine/state_handlers.ex

def waiting_for_signal(:enter, _old_state, data) do
  Logger.info("Entering :waiting_for_signal state, waiting for: #{data.signal_name}")

  # Emit SignalRequestedEvent
  {version, data} = Data.next_event_version(data)
  event = Events.SignalRequestedEvent.new(
    data.context.execution_id,
    data.signal_name,
    data.signal_step_name,
    data.signal_timeout_ms,
    version
  )
  EventStore.append(data.context.execution_id, event, version)

  # Check if signal is already queued
  case SignalQueue.dequeue(data.context.execution_id, data.signal_name) do
    {:ok, signal_data} ->
      # Signal already arrived! Deliver immediately
      Logger.info("Signal #{data.signal_name} was already queued, delivering now")
      {:keep_state, data, [{:next_event, :internal, {:signal_arrived, signal_data}}]}

    {:error, :not_found} ->
      # Wait for signal
      timeout_action = if data.signal_timeout_ms do
        [{:state_timeout, data.signal_timeout_ms, :signal_timeout}]
      else
        []
      end

      {:keep_state, data, timeout_action}
  end
end

def waiting_for_signal(:internal, {:signal_arrived, signal_data}, data) do
  # Same logic as {:call, from}, {:signal, ...} but without reply
  handle_signal_delivery(data, signal_data, nil)
end

def waiting_for_signal({:call, from}, {:signal, signal_name, signal_data}, data) do
  # Validate signal name matches
  if signal_name != data.signal_name do
    Logger.warning("Received wrong signal: #{signal_name}, expected: #{data.signal_name}")
    {:keep_state, data, [{:reply, from, {:error, :wrong_signal}}]}
  else
    handle_signal_delivery(data, signal_data, from)
  end
end

def waiting_for_signal(:state_timeout, :signal_timeout, data) do
  Logger.error("Signal timeout for: #{data.signal_name} after #{data.signal_timeout_ms}ms")

  # Emit SignalTimeoutEvent
  {version, data} = Data.next_event_version(data)
  event = Events.SignalTimeoutEvent.new(
    data.context.execution_id,
    data.signal_name,
    data.signal_timeout_ms,
    version
  )
  EventStore.append(data.context.execution_id, event, version)

  # Fail execution
  error_info = ErrorInfo.from_signal_timeout(
    data.signal_step_name,
    data.signal_name,
    data.signal_timeout_ms,
    data.context.execution_id
  )

  data = Data.mark_failed(data, error_info)
  {:next_state, :failed, data}
end

# Helper
defp handle_signal_delivery(data, signal_data, from) do
  elapsed_ms = System.monotonic_time(:millisecond) - data.signal_started_at

  # Emit SignalReceivedEvent
  {version, data} = Data.next_event_version(data)
  event = Events.SignalReceivedEvent.new(
    data.context.execution_id,
    data.signal_name,
    signal_data,
    elapsed_ms,
    version
  )
  EventStore.append(data.context.execution_id, event, version)

  # Store signal data as step result
  data = Data.store_result(data, data.signal_step_name, {:ok, signal_data})

  # Clear signal state
  data = %{data |
    signal_name: nil,
    signal_timeout_ms: nil,
    signal_started_at: nil,
    signal_step_name: nil
  }

  # Advance to next step
  data = Data.advance_step(data)

  reply_action = if from, do: [{:reply, from, {:ok, :delivered}}], else: []

  if Data.finished?(data) do
    {:next_state, :completed, data, reply_action}
  else
    next_step = Data.current_step_name(data)
    data = Data.update_context_step(data, next_step)
    {:next_state, :executing_step, data, reply_action ++ [{:next_event, :internal, :execute}]}
  end
end
```

---

## 4. Event Sourcing

### 4.1 New Events

```elixir
# lib/cerebelum/events.ex

defmodule Cerebelum.Events.SignalRequestedEvent do
  @moduledoc "Emitted when workflow starts waiting for a signal"

  defstruct [
    :execution_id,
    :signal_name,
    :step_name,
    :timeout_ms,
    :timestamp,
    :version
  ]

  def new(execution_id, signal_name, step_name, timeout_ms, version) do
    %__MODULE__{
      execution_id: execution_id,
      signal_name: signal_name,
      step_name: step_name,
      timeout_ms: timeout_ms,
      timestamp: DateTime.utc_now(),
      version: version
    }
  end
end

defmodule Cerebelum.Events.SignalReceivedEvent do
  @moduledoc "Emitted when signal is successfully delivered"

  defstruct [
    :execution_id,
    :signal_name,
    :signal_data,
    :elapsed_ms,
    :timestamp,
    :version
  ]

  def new(execution_id, signal_name, signal_data, elapsed_ms, version) do
    %__MODULE__{
      execution_id: execution_id,
      signal_name: signal_name,
      signal_data: signal_data,
      elapsed_ms: elapsed_ms,
      timestamp: DateTime.utc_now(),
      version: version
    }
  end
end

defmodule Cerebelum.Events.SignalTimeoutEvent do
  @moduledoc "Emitted when signal timeout is reached"

  defstruct [
    :execution_id,
    :signal_name,
    :timeout_ms,
    :timestamp,
    :version
  ]

  def new(execution_id, signal_name, timeout_ms, version) do
    %__MODULE__{
      execution_id: execution_id,
      signal_name: signal_name,
      timeout_ms: timeout_ms,
      timestamp: DateTime.utc_now(),
      version: version
    }
  end
end
```

---

## 5. HTTP API (Phoenix)

### 5.1 Routes

```elixir
# lib/cerebelum_web/router.ex

scope "/api/v1", CerebelumWeb do
  pipe_through :api

  # Signal endpoints
  post "/executions/:execution_id/signals/:signal_name", SignalController, :send_signal
  get "/executions/:execution_id/pending_signals", SignalController, :list_pending

  # Backward compatible approval endpoints
  post "/approvals/:execution_id/approve", ApprovalController, :approve
  post "/approvals/:execution_id/reject", ApprovalController, :reject
end
```

### 5.2 Signal Controller

```elixir
# lib/cerebelum_web/controllers/signal_controller.ex

defmodule CerebelumWeb.SignalController do
  use CerebelumWeb, :controller

  alias Cerebelum.Execution.SignalDispatcher

  @doc "Send a signal to an execution"
  def send_signal(conn, %{"execution_id" => execution_id, "signal_name" => signal_name} = params) do
    signal_data = Map.get(params, "data", %{})

    case SignalDispatcher.dispatch(execution_id, signal_name, signal_data) do
      {:ok, :delivered} ->
        json(conn, %{
          status: "delivered",
          execution_id: execution_id,
          signal_name: signal_name
        })

      {:ok, :queued} ->
        json(conn, %{
          status: "queued",
          execution_id: execution_id,
          signal_name: signal_name,
          message: "Signal queued, will be delivered when execution starts waiting"
        })

      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{error: inspect(reason)})
    end
  end

  @doc "List pending signals for an execution"
  def list_pending(conn, %{"execution_id" => execution_id}) do
    # Implementation: Query SignalQueue ETS table
    pending = SignalQueue.list_pending(execution_id)
    json(conn, %{execution_id: execution_id, pending_signals: pending})
  end
end
```

---

## 6. Backward Compatibility

### 6.1 Approval Still Works

```elixir
# Existing approval workflow - NO CHANGES NEEDED
def review_document(_ctx, {:ok, document}) do
  {:wait_for_approval,
   [type: :manual, timeout_minutes: 60],
   %{document_id: document.id}}
end

# Approval.approve(pid, response) still works!
```

### 6.2 Approval HTTP Wrapper

```elixir
# lib/cerebelum_web/controllers/approval_controller.ex

defmodule CerebelumWeb.ApprovalController do
  use CerebelumWeb, :controller

  alias Cerebelum.Infrastructure.ExecutionRegistry
  alias Cerebelum.Execution.Approval

  def approve(conn, %{"execution_id" => execution_id} = params) do
    response = Map.get(params, "response", %{})

    case ExecutionRegistry.find(execution_id) do
      {:ok, pid} ->
        case Approval.approve(pid, response) do
          {:ok, :approved} ->
            json(conn, %{status: "approved", execution_id: execution_id})

          {:error, reason} ->
            conn |> put_status(400) |> json(%{error: inspect(reason)})
        end

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Execution not found"})
    end
  end

  def reject(conn, %{"execution_id" => execution_id, "reason" => reason}) do
    case ExecutionRegistry.find(execution_id) do
      {:ok, pid} ->
        case Approval.reject(pid, reason) do
          {:ok, :rejected} ->
            json(conn, %{status: "rejected", execution_id: execution_id})

          {:error, reason} ->
            conn |> put_status(400) |> json(%{error: inspect(reason)})
        end

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Execution not found"})
    end
  end
end
```

---

## 7. Testing Strategy

### 7.1 Test Coverage Target: >90%

#### 7.1.1 Unit Tests

```elixir
# test/cerebelum/infrastructure/execution_registry_test.exs
- register/2
- find/1
- unregister/1
- auto-cleanup on process death

# test/cerebelum/infrastructure/signal_queue_test.exs
- enqueue/3
- dequeue/2
- pending?/2
- auto-expiry cleanup

# test/cerebelum/execution/signal_dispatcher_test.exs
- dispatch when execution waiting
- dispatch when execution not waiting (queue)
- dispatch to non-existent execution (queue)

# test/cerebelum/execution/engine/waiting_for_signal_test.exs
- enter state with queued signal
- enter state without queued signal
- receive correct signal
- receive wrong signal
- timeout handling
- multiple signals in sequence
```

#### 7.1.2 Integration Tests

```elixir
# test/cerebelum/integration/signal_integration_test.exs

defmodule SignalIntegrationTest do
  use ExUnit.Case

  test "workflow waits for signal and continues" do
    # Start workflow
    {:ok, pid} = Engine.start_link(workflow_module: SignalWorkflow, inputs: %{})
    execution_id = get_execution_id(pid)

    # Wait for :waiting_for_signal state
    Process.sleep(50)
    assert Engine.get_status(pid).state == :waiting_for_signal

    # Send signal via HTTP API
    signal_data = %{"amount" => 100, "currency" => "USD"}
    {:ok, :delivered} = SignalDispatcher.dispatch(execution_id, "payment_received", signal_data)

    # Workflow should complete
    Process.sleep(50)
    assert Engine.get_status(pid).state == :completed
  end

  test "signal arrives before wait_for_signal (queued scenario)" do
    {:ok, pid} = Engine.start_link(workflow_module: SlowStartWorkflow, inputs: %{})
    execution_id = get_execution_id(pid)

    # Send signal immediately (before workflow reaches wait_for_signal)
    SignalDispatcher.dispatch(execution_id, "early_signal", %{data: "test"})

    # Signal should be queued
    assert SignalQueue.pending?(execution_id, "early_signal")

    # Wait for workflow to reach wait_for_signal
    Process.sleep(200)

    # Signal should be auto-delivered from queue
    refute SignalQueue.pending?(execution_id, "early_signal")
    assert Engine.get_status(pid).state == :completed
  end

  test "signal timeout fails workflow" do
    {:ok, pid} = Engine.start_link(workflow_module: TimeoutWorkflow, inputs: %{})

    # Wait for timeout (1 second)
    Process.sleep(1100)

    status = Engine.get_status(pid)
    assert status.state == :failed
    assert status.error.kind == :signal_timeout
  end
end
```

#### 7.1.3 Backward Compatibility Tests

```elixir
# test/cerebelum/integration/backward_compatibility_test.exs

test "existing approval workflows still work" do
  {:ok, pid} = Engine.start_link(workflow_module: ApprovalWorkflow, inputs: %{})

  Process.sleep(50)
  assert Engine.get_status(pid).state == :waiting_for_approval

  # Old API still works
  Approval.approve(pid, %{approved_by: "Alice"})

  Process.sleep(50)
  assert Engine.get_status(pid).state == :completed
end

test "approval HTTP API works" do
  {:ok, pid} = Engine.start_link(workflow_module: ApprovalWorkflow, inputs: %{})
  execution_id = get_execution_id(pid)

  # New HTTP API
  conn = post(conn, "/api/v1/approvals/#{execution_id}/approve", %{
    response: %{approved_by: "Alice"}
  })

  assert json_response(conn, 200)["status"] == "approved"
end
```

### 7.2 Property-Based Testing

```elixir
# test/cerebelum/execution/signal_property_test.exs

use ExUnitProperties

property "signals are never lost" do
  check all execution_id <- string(:alphanumeric),
            signal_name <- string(:alphanumeric),
            signal_data <- map_of(string(:alphanumeric), term()) do

    # Send signal
    SignalDispatcher.dispatch(execution_id, signal_name, signal_data)

    # Signal must be either delivered or queued
    assert SignalQueue.pending?(execution_id, signal_name) or
           signal_was_delivered?(execution_id, signal_name)
  end
end
```

---

## 8. Implementation Phases

### Phase 1: Foundation (Week 1)
- [ ] ExecutionRegistry module + tests
- [ ] SignalQueue module + tests
- [ ] Engine.Data extensions
- [ ] Signal events definition

### Phase 2: Engine Integration (Week 1-2)
- [ ] `:waiting_for_signal` state handler
- [ ] Step executor handles `{:wait_for_signal, ...}`
- [ ] SignalDispatcher module
- [ ] Integration tests

### Phase 3: HTTP API (Week 2)
- [ ] Phoenix app setup (cerebelum-web)
- [ ] SignalController
- [ ] ApprovalController (backward compat)
- [ ] API tests

### Phase 4: Mobile HITL (Week 2-3)
- [ ] Mobile SDK integration
- [ ] FCM/APNS notification dispatch
- [ ] Device token registry
- [ ] End-to-end mobile tests

### Phase 5: Documentation & Polish (Week 3)
- [ ] API documentation
- [ ] Usage examples (IoT, webhooks, mobile)
- [ ] Performance testing
- [ ] Security audit

---

## 9. Usage Examples

### 9.1 Mobile HITL (Human Approval)

```elixir
defmodule ExpenseApprovalWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      validate_expense() |>
      wait_for_manager_approval() |>
      process_payment()
    end
  end

  def validate_expense(_ctx, inputs) do
    {:ok, %{amount: inputs["amount"], valid: true}}
  end

  def wait_for_manager_approval(_ctx, {:ok, expense}) do
    # Workflow hibernates here
    {:wait_for_signal, "manager_approval_#{expense.amount}",
     [timeout_hours: 24, metadata: expense]}
  end

  def process_payment(_ctx, {:ok, expense}, {:ok, approval}) do
    # approval = %{"approved_by" => "Alice", "timestamp" => "..."}
    {:ok, %{paid: true, approved_by: approval["approved_by"]}}
  end
end

# Mobile app sends:
# POST /api/v1/executions/{id}/signals/manager_approval_100
# { "data": { "approved_by": "Alice" } }
```

### 9.2 IoT Sensor Event

```elixir
defmodule TemperatureMonitorWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      start_monitoring() |>
      wait_for_temp_alert() |>
      send_notification()
    end
  end

  def start_monitoring(_ctx, inputs) do
    {:ok, %{sensor_id: inputs["sensor_id"]}}
  end

  def wait_for_temp_alert(_ctx, {:ok, sensor}) do
    # Workflow hibernates until sensor triggers
    {:wait_for_signal, "temp_alert_#{sensor.sensor_id}",
     [timeout_hours: 72]}  # 3 days
  end

  def send_notification(_ctx, {:ok, sensor}, {:ok, alert}) do
    # alert = %{"temperature" => 85, "timestamp" => "..."}
    notify_admin("Temperature alert: #{alert["temperature"]}°C")
    {:ok, :notified}
  end
end

# IoT device sends:
# POST /api/v1/executions/{id}/signals/temp_alert_SENSOR_123
# { "data": { "temperature": 85, "timestamp": "2025-11-21T10:00:00Z" } }
```

### 9.3 Webhook Integration (Stripe Payment)

```elixir
defmodule PaymentWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      create_payment_intent() |>
      wait_for_payment_confirmation() |>
      fulfill_order()
    end
  end

  def create_payment_intent(_ctx, inputs) do
    intent = Stripe.create_payment_intent(inputs["amount"])
    {:ok, %{payment_intent_id: intent.id}}
  end

  def wait_for_payment_confirmation(_ctx, {:ok, payment}) do
    # Workflow hibernates until Stripe webhook arrives
    {:wait_for_signal, "stripe_payment_#{payment.payment_intent_id}",
     [timeout_minutes: 30]}
  end

  def fulfill_order(_ctx, {:ok, payment}, {:ok, stripe_event}) do
    # stripe_event = %{"status" => "succeeded", "amount" => 1000}
    {:ok, %{order_fulfilled: true}}
  end
end

# Stripe webhook handler sends:
# POST /api/v1/executions/{id}/signals/stripe_payment_pi_123
# { "data": { "status": "succeeded", "amount": 1000 } }
```

---

## 10. Security Considerations

### 10.1 Signal Authentication

```elixir
# Add authentication middleware
plug CerebelumWeb.Plugs.VerifySignalAuth

# Verify HMAC signature on signal requests
# Or require API key/JWT token
```

### 10.2 Signal Validation

```elixir
# Validate signal_name format (prevent injection)
# Validate execution_id exists
# Rate limiting on signal endpoints
```

### 10.3 Signal TTL

```elixir
# Auto-expire queued signals after TTL
# Prevent memory leaks from abandoned signals
```

---

## 11. Success Metrics

- ✅ >90% test coverage
- ✅ Zero breaking changes to existing approval system
- ✅ <10ms signal delivery latency (p99)
- ✅ 100% signal delivery reliability (no lost signals)
- ✅ Support 100k+ concurrent waiting workflows
- ✅ Mobile HITL working end-to-end

---

## 12. Appendix

### 12.1 Comparison: Approval vs Signal

| Feature | `{:wait_for_approval, ...}` | `{:wait_for_signal, ...}` |
|---------|------------------------------|----------------------------|
| **Use Case** | Human approvals | Any external event |
| **API** | `Approval.approve(pid)` | HTTP POST signal |
| **Semantics** | Specific (approval/reject) | Generic (any data) |
| **Mobile** | Via HTTP wrapper | Native HTTP |
| **IoT** | ❌ Not suitable | ✅ Perfect fit |
| **Webhooks** | ❌ Not suitable | ✅ Perfect fit |
| **Event Sourcing** | ✅ Complete | ✅ Complete |
| **Status** | ✅ Implemented | 🟡 To implement |

### 12.2 Migration Guide

**No migration needed!** Existing workflows continue working.

**Optional:** Migrate approval to signal:

```elixir
# Before
{:wait_for_approval, [timeout_minutes: 60], %{...}}

# After (more generic)
{:wait_for_signal, "approval_received", [timeout_minutes: 60]}
```

---

**End of Design Document**

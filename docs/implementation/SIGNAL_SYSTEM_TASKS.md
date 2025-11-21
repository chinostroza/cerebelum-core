# Signal System - Implementation Tasks

**Version:** v0.3.0
**Design Doc:** [specs/08-signal-system-design-v0.3.0.md](../../specs/08-signal-system-design-v0.3.0.md)
**Start Date:** 2025-11-21
**Target:** 3 weeks

---

## 📊 Progress Tracker

```
Phase 1: Foundation          [░░░░░░░░░░] 0%  (0/6 tasks)
Phase 2: Engine Integration  [░░░░░░░░░░] 0%  (0/7 tasks)
Phase 3: HTTP API            [░░░░░░░░░░] 0%  (0/5 tasks)
Phase 4: Mobile HITL         [░░░░░░░░░░] 0%  (0/6 tasks)
Phase 5: Documentation       [░░░░░░░░░░] 0%  (0/4 tasks)
───────────────────────────────────────────────
Overall Progress             [░░░░░░░░░░] 0%  (0/28 tasks)
```

---

## 🎯 Phase 1: Foundation (Week 1 - Days 1-3)

### Task 1.1: ExecutionRegistry Module
**Priority:** P0 (Critical)
**Estimated Time:** 4 hours
**Dependencies:** None

**Implementation:**
- [ ] Create `lib/cerebelum/infrastructure/execution_registry.ex`
  ```elixir
  defmodule Cerebelum.Infrastructure.ExecutionRegistry do
    @moduledoc """
    Registry for mapping execution IDs to process PIDs.
    Uses Elixir Registry with auto-cleanup on process termination.
    """

    @registry_name __MODULE__

    def start_link(_opts) do
      Registry.start_link(keys: :unique, name: @registry_name)
    end

    def child_spec(opts) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [opts]},
        type: :supervisor
      }
    end

    def register(execution_id, pid \\ self())
    def find(execution_id)
    def unregister(execution_id)
    def list_all()
  end
  ```

- [ ] Add to supervision tree in `lib/cerebelum/application.ex`:
  ```elixir
  children = [
    # ... existing ...
    Cerebelum.Infrastructure.ExecutionRegistry,
    # ...
  ]
  ```

- [ ] Modify `Engine.init/1` to auto-register:
  ```elixir
  def init(opts) do
    # ... existing code ...
    ExecutionRegistry.register(context.execution_id, self())
    # ... continue ...
  end
  ```

**Tests:**
- [ ] `test/cerebelum/infrastructure/execution_registry_test.exs`
  - `register/2` successfully registers
  - `register/2` returns error if already registered
  - `find/1` returns {:ok, pid} for existing
  - `find/1` returns {:error, :not_found} for missing
  - `unregister/1` removes entry
  - Auto-cleanup on process death (spawn process, kill it, verify cleanup)
  - `list_all/0` returns all registered executions

**Acceptance Criteria:**
- ✅ All tests pass
- ✅ Coverage >95%
- ✅ No race conditions on concurrent register/find
- ✅ Memory cleanup verified (no leaks)

---

### Task 1.2: SignalQueue Module
**Priority:** P0 (Critical)
**Estimated Time:** 6 hours
**Dependencies:** None

**Implementation:**
- [ ] Create `lib/cerebelum/infrastructure/signal_queue.ex`
  ```elixir
  defmodule Cerebelum.Infrastructure.SignalQueue do
    use GenServer

    @table_name :cerebelum_signal_queue
    @default_ttl_ms 60_000

    # Public API
    def enqueue(execution_id, signal_name, data)
    def dequeue(execution_id, signal_name)
    def pending?(execution_id, signal_name)
    def list_pending(execution_id)
    def clear_all(execution_id)

    # GenServer callbacks
    def init(_)
    def handle_info(:cleanup, state)  # Expire old signals
  end
  ```

- [ ] Add to supervision tree

**Tests:**
- [ ] `test/cerebelum/infrastructure/signal_queue_test.exs`
  - `enqueue/3` stores signal
  - `dequeue/2` returns and removes signal
  - `dequeue/2` returns {:error, :not_found} if not present
  - `pending?/2` correctly identifies pending signals
  - `list_pending/1` returns all signals for execution_id
  - `clear_all/1` removes all signals for execution_id
  - Auto-expiry after TTL (test with short TTL)
  - Concurrent enqueue/dequeue (property test)
  - Multiple signals with same execution_id but different names

**Acceptance Criteria:**
- ✅ All tests pass
- ✅ Coverage >95%
- ✅ No memory leaks (expired signals cleaned up)
- ✅ Handles 10k+ queued signals

---

### Task 1.3: Engine.Data Extensions
**Priority:** P0 (Critical)
**Estimated Time:** 2 hours
**Dependencies:** None

**Implementation:**
- [ ] Modify `lib/cerebelum/execution/engine/data.ex`:
  ```elixir
  @type t :: %__MODULE__{
    # ... existing fields ...

    # Signal-specific fields
    signal_name: String.t() | nil,
    signal_timeout_ms: non_neg_integer() | nil,
    signal_started_at: integer() | nil,
    signal_step_name: atom() | nil
  }

  defstruct [
    # ... existing ...
    signal_name: nil,
    signal_timeout_ms: nil,
    signal_started_at: nil,
    signal_step_name: nil
  ]
  ```

- [ ] Update `build_status/2` to include signal info when in `:waiting_for_signal` state

**Tests:**
- [ ] Verify struct compiles
- [ ] `build_status/2` includes signal fields
- [ ] No breaking changes to existing workflows

**Acceptance Criteria:**
- ✅ No compilation errors
- ✅ All existing tests still pass
- ✅ Dialyzer happy

---

### Task 1.4: Signal Events Definition
**Priority:** P0 (Critical)
**Estimated Time:** 3 hours
**Dependencies:** None

**Implementation:**
- [ ] Add to `lib/cerebelum/events.ex`:
  ```elixir
  defmodule Cerebelum.Events.SignalRequestedEvent do
    defstruct [:execution_id, :signal_name, :step_name, :timeout_ms, :timestamp, :version]
    def new(execution_id, signal_name, step_name, timeout_ms, version)
  end

  defmodule Cerebelum.Events.SignalReceivedEvent do
    defstruct [:execution_id, :signal_name, :signal_data, :elapsed_ms, :timestamp, :version]
    def new(execution_id, signal_name, signal_data, elapsed_ms, version)
  end

  defmodule Cerebelum.Events.SignalTimeoutEvent do
    defstruct [:execution_id, :signal_name, :timeout_ms, :timestamp, :version]
    def new(execution_id, signal_name, timeout_ms, version)
  end
  ```

- [ ] Update EventStore schema if needed (JSON serialization)

**Tests:**
- [ ] Event struct creation
- [ ] Serialization/deserialization
- [ ] EventStore.append works with new events

**Acceptance Criteria:**
- ✅ Events compile
- ✅ EventStore handles new events
- ✅ JSON serialization works

---

### Task 1.5: ErrorInfo Extensions
**Priority:** P1 (High)
**Estimated Time:** 2 hours
**Dependencies:** None

**Implementation:**
- [ ] Add to `lib/cerebelum/execution/error_info.ex`:
  ```elixir
  def from_signal_timeout(step_name, signal_name, timeout_ms, execution_id) do
    %__MODULE__{
      kind: :signal_timeout,
      step: step_name,
      message: "Signal '#{signal_name}' timeout after #{timeout_ms}ms",
      execution_id: execution_id,
      metadata: %{signal_name: signal_name, timeout_ms: timeout_ms}
    }
  end
  ```

**Tests:**
- [ ] Error creation
- [ ] Error formatting

**Acceptance Criteria:**
- ✅ Error messages are clear
- ✅ Includes all relevant metadata

---

### Task 1.6: Phase 1 Integration Test
**Priority:** P1 (High)
**Estimated Time:** 2 hours
**Dependencies:** Tasks 1.1-1.5

**Implementation:**
- [ ] Create `test/cerebelum/infrastructure/foundation_integration_test.exs`
  - Test ExecutionRegistry + SignalQueue interaction
  - Register execution, enqueue signal, find execution, dequeue signal
  - Verify no memory leaks after process cleanup

**Acceptance Criteria:**
- ✅ All Phase 1 components work together
- ✅ No race conditions
- ✅ Memory usage stable

---

## 🔧 Phase 2: Engine Integration (Week 1-2 - Days 4-10)

### Task 2.1: StepExecutor - Handle {:wait_for_signal, ...}
**Priority:** P0 (Critical)
**Estimated Time:** 4 hours
**Dependencies:** Phase 1

**Implementation:**
- [ ] Modify `lib/cerebelum/execution/step_executor.ex`:
  ```elixir
  # Add pattern matching in execute_step result handling
  def execute_step(...) do
    result = apply(workflow_module, step_name, args)

    case result do
      {:wait_for_signal, signal_name, opts} ->
        {:ok, {:wait_for_signal, signal_name, opts}}

      # ... existing patterns ...
    end
  end
  ```

**Tests:**
- [ ] Step returns `{:wait_for_signal, "test_signal", []}` is handled
- [ ] Options parsing (timeout_seconds, timeout_minutes, timeout_hours)

**Acceptance Criteria:**
- ✅ StepExecutor recognizes wait_for_signal return
- ✅ Options validated

---

### Task 2.2: State Handler - :waiting_for_signal (Entry)
**Priority:** P0 (Critical)
**Estimated Time:** 6 hours
**Dependencies:** Task 2.1

**Implementation:**
- [ ] Add to `lib/cerebelum/execution/engine/state_handlers.ex`:
  ```elixir
  def waiting_for_signal(:enter, _old_state, data) do
    Logger.info("Entering :waiting_for_signal state, waiting for: #{data.signal_name}")

    # Emit SignalRequestedEvent
    {version, data} = Data.next_event_version(data)
    event = Events.SignalRequestedEvent.new(...)
    EventStore.append(data.context.execution_id, event, version)

    # Check if signal already queued
    case SignalQueue.dequeue(data.context.execution_id, data.signal_name) do
      {:ok, signal_data} ->
        # Deliver immediately
        {:keep_state, data, [{:next_event, :internal, {:signal_arrived, signal_data}}]}

      {:error, :not_found} ->
        # Wait with timeout
        timeout_action = ...
        {:keep_state, data, timeout_action}
    end
  end
  ```

**Tests:**
- [ ] State entry emits event
- [ ] Queued signal auto-delivered
- [ ] No queued signal → wait state
- [ ] Timeout configured correctly

**Acceptance Criteria:**
- ✅ Event emitted
- ✅ Queued signals delivered
- ✅ Timeouts work

---

### Task 2.3: State Handler - Signal Delivery
**Priority:** P0 (Critical)
**Estimated Time:** 6 hours
**Dependencies:** Task 2.2

**Implementation:**
- [ ] Add signal delivery handlers:
  ```elixir
  def waiting_for_signal(:internal, {:signal_arrived, signal_data}, data)
  def waiting_for_signal({:call, from}, {:signal, signal_name, signal_data}, data)
  ```

- [ ] Implement `handle_signal_delivery/3` helper
- [ ] Emit SignalReceivedEvent
- [ ] Store signal data as step result
- [ ] Advance to next step

**Tests:**
- [ ] Internal delivery (from queue)
- [ ] External delivery (via call)
- [ ] Wrong signal name rejected
- [ ] Signal data stored in results
- [ ] Next step executed

**Acceptance Criteria:**
- ✅ Signals delivered correctly
- ✅ Workflow continues to next step
- ✅ Event sourcing complete

---

### Task 2.4: State Handler - Timeout
**Priority:** P0 (Critical)
**Estimated Time:** 3 hours
**Dependencies:** Task 2.3

**Implementation:**
- [ ] Add timeout handler:
  ```elixir
  def waiting_for_signal(:state_timeout, :signal_timeout, data) do
    # Emit timeout event
    # Mark execution as failed
    {:next_state, :failed, data}
  end
  ```

**Tests:**
- [ ] Timeout triggers after specified duration
- [ ] Timeout event emitted
- [ ] Execution marked as failed
- [ ] Error info includes signal name and timeout

**Acceptance Criteria:**
- ✅ Timeouts work reliably
- ✅ Error messages clear

---

### Task 2.5: State Handler - get_status
**Priority:** P1 (High)
**Estimated Time:** 2 hours
**Dependencies:** Task 2.2

**Implementation:**
- [ ] Add get_status handler:
  ```elixir
  def waiting_for_signal({:call, from}, :get_status, data) do
    status = Data.build_status(data, :waiting_for_signal)

    status_with_signal = Map.merge(status, %{
      signal_name: data.signal_name,
      signal_timeout_ms: data.signal_timeout_ms,
      signal_elapsed_ms: ...,
      signal_remaining_ms: ...
    })

    {:keep_state, data, [{:reply, from, status_with_signal}]}
  end
  ```

**Tests:**
- [ ] Status includes signal info
- [ ] Elapsed/remaining time accurate

**Acceptance Criteria:**
- ✅ Status complete and accurate

---

### Task 2.6: SignalDispatcher Module
**Priority:** P0 (Critical)
**Estimated Time:** 5 hours
**Dependencies:** Tasks 2.1-2.5

**Implementation:**
- [ ] Create `lib/cerebelum/execution/signal_dispatcher.ex`:
  ```elixir
  defmodule Cerebelum.Execution.SignalDispatcher do
    def dispatch(execution_id, signal_name, signal_data)
    def waiting_for_signal?(pid, signal_name)
  end
  ```

**Tests:**
- [ ] Dispatch to waiting execution (delivered)
- [ ] Dispatch to non-waiting execution (queued)
- [ ] Dispatch to non-existent execution (queued)
- [ ] Concurrent dispatches

**Acceptance Criteria:**
- ✅ 100% signal delivery (no lost signals)
- ✅ Correct queuing logic

---

### Task 2.7: Phase 2 Integration Tests
**Priority:** P0 (Critical)
**Estimated Time:** 8 hours
**Dependencies:** Tasks 2.1-2.6

**Implementation:**
- [ ] Create `test/cerebelum/integration/signal_integration_test.exs`
  - End-to-end signal workflow
  - Signal arrives before wait (queued)
  - Signal arrives after wait (delivered)
  - Multiple signals in sequence
  - Signal timeout
  - Wrong signal name

- [ ] Create example workflows:
  ```elixir
  defmodule SignalWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        step1() |> wait_for_signal() |> step3()
      end
    end

    def wait_for_signal(_ctx, _) do
      {:wait_for_signal, "test_signal", [timeout_seconds: 10]}
    end
  end
  ```

**Tests:**
- [ ] Happy path (signal delivered, workflow completes)
- [ ] Timeout path (no signal, workflow fails)
- [ ] Early signal (queued then delivered)
- [ ] Multiple workflows waiting for different signals
- [ ] Event replay from SignalReceivedEvent works

**Acceptance Criteria:**
- ✅ All integration scenarios pass
- ✅ Event sourcing complete (replay works)
- ✅ No flaky tests

---

## 🌐 Phase 3: HTTP API (Week 2 - Days 11-14)

### Task 3.1: Setup cerebelum-web Phoenix App
**Priority:** P0 (Critical)
**Estimated Time:** 6 hours
**Dependencies:** Phase 2

**Implementation:**
- [ ] Navigate to `/Users/dev/Documents/zea/cerebelum-io/cerebelum-web`
- [ ] Initialize Phoenix app (if not exists):
  ```bash
  mix phx.new cerebelum_web --no-html --no-assets
  ```

- [ ] Update `mix.exs` dependencies:
  ```elixir
  {:cerebelum_core, path: "../cerebelum-core"},
  {:phoenix, "~> 1.7"},
  {:plug_cowboy, "~> 2.7"}
  ```

- [ ] Configure `config/dev.exs`, `config/test.exs`, `config/prod.exs`

**Tests:**
- [ ] Phoenix app starts
- [ ] Health check endpoint works

**Acceptance Criteria:**
- ✅ Phoenix app functional
- ✅ Can import Cerebelum modules

---

### Task 3.2: SignalController
**Priority:** P0 (Critical)
**Estimated Time:** 5 hours
**Dependencies:** Task 3.1

**Implementation:**
- [ ] Create `lib/cerebelum_web/controllers/signal_controller.ex`:
  ```elixir
  defmodule CerebelumWeb.SignalController do
    use CerebelumWeb, :controller

    def send_signal(conn, %{"execution_id" => id, "signal_name" => name} = params)
    def list_pending(conn, %{"execution_id" => id})
  end
  ```

- [ ] Add routes in `lib/cerebelum_web/router.ex`:
  ```elixir
  scope "/api/v1", CerebelumWeb do
    pipe_through :api

    post "/executions/:execution_id/signals/:signal_name", SignalController, :send_signal
    get "/executions/:execution_id/pending_signals", SignalController, :list_pending
  end
  ```

**Tests:**
- [ ] `test/cerebelum_web/controllers/signal_controller_test.exs`
  - POST signal returns 200 and "delivered"
  - POST signal returns 200 and "queued"
  - POST to invalid execution_id returns 404
  - GET pending signals returns list

**Acceptance Criteria:**
- ✅ API works via HTTP
- ✅ JSON responses correct

---

### Task 3.3: ApprovalController (Backward Compat)
**Priority:** P1 (High)
**Estimated Time:** 4 hours
**Dependencies:** Task 3.1

**Implementation:**
- [ ] Create `lib/cerebelum_web/controllers/approval_controller.ex`:
  ```elixir
  defmodule CerebelumWeb.ApprovalController do
    use CerebelumWeb, :controller

    def approve(conn, %{"execution_id" => id} = params)
    def reject(conn, %{"execution_id" => id, "reason" => reason})
  end
  ```

- [ ] Add routes:
  ```elixir
  post "/approvals/:execution_id/approve", ApprovalController, :approve
  post "/approvals/:execution_id/reject", ApprovalController, :reject
  ```

**Tests:**
- [ ] POST approve works with existing approval workflow
- [ ] POST reject works
- [ ] 404 for non-existent execution

**Acceptance Criteria:**
- ✅ Backward compatibility verified
- ✅ Old approval workflows work via HTTP

---

### Task 3.4: API Documentation
**Priority:** P2 (Medium)
**Estimated Time:** 3 hours
**Dependencies:** Tasks 3.2, 3.3

**Implementation:**
- [ ] Create `docs/api/SIGNALS_API.md`:
  - Endpoint documentation
  - Request/response examples
  - Error codes
  - Authentication (if applicable)

- [ ] Add OpenAPI/Swagger spec (optional)

**Acceptance Criteria:**
- ✅ API fully documented
- ✅ Examples work

---

### Task 3.5: Phase 3 Integration Tests
**Priority:** P0 (Critical)
**Estimated Time:** 4 hours
**Dependencies:** Tasks 3.1-3.3

**Implementation:**
- [ ] Create `test/cerebelum_web/integration/api_integration_test.exs`
  - Start workflow via Elixir API
  - Send signal via HTTP API
  - Verify workflow completes
  - Test approval HTTP API

**Acceptance Criteria:**
- ✅ HTTP → Core integration works
- ✅ All API endpoints functional

---

## 📱 Phase 4: Mobile HITL Integration (Week 2-3 - Days 15-21)

### Task 4.1: Device Token Registry
**Priority:** P1 (High)
**Estimated Time:** 6 hours
**Dependencies:** Phase 3

**Implementation:**
- [ ] Create `lib/cerebelum/infrastructure/device_registry.ex`:
  ```elixir
  defmodule Cerebelum.Infrastructure.DeviceRegistry do
    # Store user_id → device_tokens mapping
    # Support FCM (Android) and APNS (iOS)

    def register_device(user_id, platform, device_token)
    def get_devices(user_id)
    def remove_device(user_id, device_token)
  end
  ```

- [ ] Database schema (Ecto):
  ```elixir
  create table(:devices) do
    add :user_id, :string, null: false
    add :platform, :string, null: false  # "android" | "ios"
    add :device_token, :string, null: false
    add :last_active, :utc_datetime

    timestamps()
  end

  create index(:devices, [:user_id])
  create unique_index(:devices, [:device_token])
  ```

**Tests:**
- [ ] Register device
- [ ] Get devices for user
- [ ] Remove device
- [ ] Handle duplicate tokens

**Acceptance Criteria:**
- ✅ Database migrations run
- ✅ CRUD operations work

---

### Task 4.2: Notification Dispatcher (FCM/APNS)
**Priority:** P1 (High)
**Estimated Time:** 8 hours
**Dependencies:** Task 4.1

**Implementation:**
- [ ] Add dependencies to `cerebelum-core/mix.exs`:
  ```elixir
  {:pigeon, "~> 2.0"},  # FCM/APNS client
  {:kadabra, "~> 0.6"}  # HTTP/2 for APNS
  ```

- [ ] Create `lib/cerebelum/infrastructure/notification_dispatcher.ex`:
  ```elixir
  defmodule Cerebelum.Infrastructure.NotificationDispatcher do
    def send_approval_notification(user_id, execution_id, task_type, data)

    defp send_fcm(device_token, payload)
    defp send_apns(device_token, payload)
  end
  ```

- [ ] Configure FCM/APNS credentials in `config/runtime.exs`

**Tests:**
- [ ] Mock FCM/APNS (use Bypass or Mox)
- [ ] Notification sent to all user devices
- [ ] Handle failed sends gracefully

**Acceptance Criteria:**
- ✅ Notifications send successfully
- ✅ Error handling robust

---

### Task 4.3: Approval Workflow → Notification Integration
**Priority:** P1 (High)
**Estimated Time:** 4 hours
**Dependencies:** Task 4.2

**Implementation:**
- [ ] Hook notification dispatch into `:waiting_for_approval` state:
  ```elixir
  def waiting_for_approval(:enter, _old_state, data) do
    # ... existing code ...

    # Dispatch notification
    if data.approval_data[:user_id] do
      NotificationDispatcher.send_approval_notification(
        data.approval_data.user_id,
        data.context.execution_id,
        data.approval_type,
        data.approval_data
      )
    end

    # ... continue ...
  end
  ```

**Tests:**
- [ ] Approval request triggers notification
- [ ] Notification includes correct data

**Acceptance Criteria:**
- ✅ Notifications sent on approval request

---

### Task 4.4: Mobile SDK - Task Sync Endpoint
**Priority:** P0 (Critical)
**Estimated Time:** 5 hours
**Dependencies:** Task 3.2

**Implementation:**
- [ ] Update `KtorSyncService.kt` URL to real backend:
  ```kotlin
  // From: https://api.cerebelum.io/v1/tasks/sync
  // To: http://localhost:4000/api/v1/tasks/sync (dev)
  ```

- [ ] Create backend endpoint in `ApprovalController`:
  ```elixir
  def sync_tasks(conn, %{"tasks" => tasks}) do
    # tasks = [%{"id" => execution_id, "result" => approval_data}, ...]

    Enum.each(tasks, fn %{"id" => id, "result" => result} ->
      SignalDispatcher.dispatch(id, "mobile_approval", result)
    end)

    json(conn, %{status: "synced", count: length(tasks)})
  end
  ```

**Tests:**
- [ ] Sync endpoint receives tasks
- [ ] Tasks dispatched as signals
- [ ] Workflows resume

**Acceptance Criteria:**
- ✅ Mobile → Backend sync works

---

### Task 4.5: Mobile SDK - FCM Integration
**Priority:** P1 (High)
**Estimated Time:** 6 hours
**Dependencies:** Task 4.2

**Implementation:**
- [ ] Update `CerebelumMessagingService.kt`:
  - Send device token to backend on app start
  - Handle data notifications correctly

- [ ] Create backend endpoint:
  ```elixir
  post "/devices/register", DeviceController, :register
  # Body: {"user_id": "...", "platform": "android", "device_token": "..."}
  ```

**Tests:**
- [ ] Token registration works
- [ ] Notifications received on device

**Acceptance Criteria:**
- ✅ End-to-end notification delivery

---

### Task 4.6: Phase 4 End-to-End Test
**Priority:** P0 (Critical)
**Estimated Time:** 8 hours
**Dependencies:** Tasks 4.1-4.5

**Implementation:**
- [ ] Create full flow test:
  1. Start approval workflow
  2. Backend sends FCM notification
  3. Mobile SDK receives notification
  4. User approves in mobile app
  5. Mobile syncs to backend
  6. Workflow continues

- [ ] Use emulator/simulator or mock

**Acceptance Criteria:**
- ✅ Full HITL flow works
- ✅ No manual intervention needed

---

## 📚 Phase 5: Documentation & Polish (Week 3 - Days 22+)

### Task 5.1: Usage Documentation
**Priority:** P2 (Medium)
**Estimated Time:** 6 hours

**Implementation:**
- [ ] Create `docs/guides/SIGNALS.md`:
  - How to use `{:wait_for_signal, ...}`
  - IoT examples
  - Webhook examples
  - Mobile HITL examples

- [ ] Update README.md

**Acceptance Criteria:**
- ✅ Examples work
- ✅ Clear and comprehensive

---

### Task 5.2: Performance Testing
**Priority:** P2 (Medium)
**Estimated Time:** 6 hours

**Implementation:**
- [ ] Benchmark signal delivery latency
  - Target: <10ms p99
- [ ] Load test: 10k concurrent waiting workflows
- [ ] Memory usage profiling

**Acceptance Criteria:**
- ✅ Performance meets targets
- ✅ No memory leaks

---

### Task 5.3: Security Audit
**Priority:** P1 (High)
**Estimated Time:** 4 hours

**Implementation:**
- [ ] Review signal validation
- [ ] Check for injection vulnerabilities
- [ ] Verify authentication/authorization
- [ ] Rate limiting on API endpoints

**Acceptance Criteria:**
- ✅ No security issues found

---

### Task 5.4: Final Integration Tests
**Priority:** P0 (Critical)
**Estimated Time:** 4 hours

**Implementation:**
- [ ] Run ALL tests (unit + integration)
- [ ] Verify backward compatibility
- [ ] Test state reconstruction from events
- [ ] Verify no breaking changes

**Acceptance Criteria:**
- ✅ >90% test coverage
- ✅ Zero breaking changes
- ✅ All workflows work

---

## ✅ Definition of Done

### Code Quality
- [ ] All tests pass (>90% coverage)
- [ ] Dialyzer passes (no type errors)
- [ ] Credo passes (code quality)
- [ ] No compiler warnings

### Functionality
- [ ] Signals work end-to-end
- [ ] Approval backward compatibility verified
- [ ] Mobile HITL works
- [ ] IoT/webhook examples functional

### Documentation
- [ ] API documented
- [ ] Usage guide complete
- [ ] Design doc updated

### Performance
- [ ] <10ms signal delivery (p99)
- [ ] 100k+ concurrent waiting workflows
- [ ] No memory leaks

### Security
- [ ] No injection vulnerabilities
- [ ] Authentication implemented
- [ ] Rate limiting in place

---

## 🚨 Risk Mitigation

### Risk 1: Breaking Existing Approval System
**Mitigation:**
- Run approval tests after every change
- Keep `:waiting_for_approval` state untouched
- Add new code, don't modify old

### Risk 2: Signal Queue Memory Leaks
**Mitigation:**
- Aggressive TTL (60s default)
- Periodic cleanup job
- Memory profiling tests

### Risk 3: Race Conditions
**Mitigation:**
- Property-based testing (StreamData)
- Concurrent test scenarios
- Careful ETS/Registry usage

### Risk 4: Mobile Integration Issues
**Mitigation:**
- Mock FCM/APNS in tests
- Emulator testing
- Incremental rollout

---

## 📞 Support & Questions

- **Design Questions:** See `specs/08-signal-system-design-v0.3.0.md`
- **Architecture:** See design doc Section 3
- **Testing:** See design doc Section 7

---

**Last Updated:** 2025-11-21
**Next Review:** End of Week 1 (Day 7)

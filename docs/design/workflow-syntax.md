# Workflow Syntax Design - Code-First Approach

**Status:** Draft - Design Iteration
**Last Updated:** 2024-10-31
**Context:** This document captures the iterative design decisions for Cerebelum's code-first workflow syntax.

---

## Table of Contents

1. [Design Philosophy](#design-philosophy)
2. [Core Concepts](#core-concepts)
3. [Workflow Syntax](#workflow-syntax)
4. [Message Passing with Pattern Matching](#message-passing-with-pattern-matching)
5. [Timeline vs Diverge vs Branch](#timeline-vs-diverge-vs-branch)
6. [Context and State Management](#context-and-state-management)
7. [Complete Example](#complete-example)
8. [How the Engine Works](#how-the-engine-works)
9. [Design Decisions Log](#design-decisions-log)

---

## Design Philosophy

### Goals

1. **Code-First**: Workflows are pure Elixir modules, not JSON/maps
2. **Compile-Time Safety**: Function existence, arity, and types validated by compiler
3. **Idiomatically Elixir**: Leverage pattern matching, guards, and function clauses
4. **Actor Model Friendly**: Immutable context, message passing between functions
5. **Clean Timeline**: Declarative workflow definition without noise
6. **Zero Magic**: Explicit dependencies using atoms and pattern matching

### Anti-Goals

- ❌ No JSON/map-based DSL
- ❌ No string-based function references
- ❌ No implicit "normalization" of names (e.g., `load_expected_transfers` → `expected_transfers`)
- ❌ No shared mutable state
- ❌ No custom structs required for every message

---

## Core Concepts

### 1. Workflow = Module

Each workflow is an Elixir module using `use Cerebelum.Workflow`:

```elixir
defmodule MyApp.ProcessOrder do
  use Cerebelum.Workflow

  workflow do
    timeline do
      start()
      |> validate_order()
      |> charge_payment()
      |> ship_order()
      |> finish_success()
    end
  end

  # Functions define the workflow nodes
  def start(context), do: {:ok, context}
  def validate_order(context, %{...}), do: {:ok, ...}
  # ...
end
```

### 2. Timeline = Happy Path

The `timeline` block defines the main execution path (the "sacred timeline"):

```elixir
timeline do
  start()
  |> step_1()
  |> step_2()
  |> step_3()
  |> finish()
end
```

### 3. Diverge = Error Handling

`diverge` handles errors and exceptional cases (deviations from the timeline):

```elixir
diverge from: :fetch_bank_data do
  {:ok, %{failed: [_|_]}} when context.retry_count < 3 ->
    retry() |> back_to(:fetch_bank_data)

  {:ok, %{failed: [_|_]}} ->
    finish_partial_failure()

  _ -> continue()
end
```

### 4. Branch = Business Logic Decisions

`branch` handles normal business logic branching (both paths are valid):

```elixir
branch from: :analyze_amount do
  {:ok, %{amount: amt}} when amt >= 10_000 ->
    request_manual_approval() |> skip_to(:save)

  {:ok, %{amount: _}} ->
    auto_approve() |> skip_to(:save)
end
```

---

## Workflow Syntax

### Timeline Block

```elixir
workflow do
  timeline do
    start()
    |> load_data()
    |> process_data()
    |> save_results()
    |> finish_success()
  end
end
```

**Rules:**
- Uses pipeline operator `|>`
- No parameters visible (clean, declarative)
- Read top-to-bottom
- Represents the "happy path"

### Diverge Block

```elixir
diverge from: :function_name do
  pattern1 when guard1 -> action1
  pattern2 when guard2 -> action2
  _ -> continue()
end
```

**Used for:**
- Error handling
- Retry logic
- Timeout handling
- Failure recovery

### Branch Block

```elixir
branch from: :function_name do
  pattern1 when guard1 -> action1
  pattern2 when guard2 -> action2
end
```

**Used for:**
- Business logic decisions
- Amount thresholds
- Conditional flows
- All paths are valid business cases

### Flow Control Actions

```elixir
# Continue in the timeline
continue()

# Go back to a previous step (retry/loop)
back_to(:function_name)

# Skip ahead to a specific step (convergence)
skip_to(:function_name)

# Pause execution without blocking BEAM
{:sleep, [seconds: 30], state}

# Wait for human approval (HITL)
{:wait_for_approval, [type: :manual_review], state}

# Execute tasks in parallel
{:parallel, [task1, task2, task3], state}
```

---

## Message Passing with Pattern Matching

### The Problem: How to Pass Data Between Functions?

**Rejected Approaches:**

1. ❌ **Shared state accumulator** - Violates actor model
2. ❌ **String-based names with normalization** - Too magic, error-prone
3. ❌ **Custom structs for every message** - Too much boilerplate

**Chosen Approach: Atoms + Pattern Matching**

### How It Works

Each function receives:
1. **Context** (always first parameter) - Immutable execution metadata
2. **Results map** (second parameter) - Map with atom keys referencing previous results

```elixir
def fetch_bank_movements(context, %{load_expected_transfers: expected}) do
  #                                ↑ Atom key            ↑ Local variable
  results = BankAPI.fetch(context.bank_accounts, context.date)
  {:ok, %{movements: ..., failed: ...}}
end
```

### Pattern Matching Examples

**Single dependency:**
```elixir
def process_data(context, %{load_data: data}) do
  {:ok, transform(data)}
end
```

**Multiple dependencies:**
```elixir
def match_transactions(context, %{
  load_expected_transfers: expected,
  fetch_bank_movements: bank_data
}) do
  all_movements = Map.values(bank_data.movements) |> List.flatten()
  {matched, discrep} = Matcher.match(expected, all_movements)
  {:ok, %{matched: matched, discrepancies: discrep}}
end
```

**Deep pattern matching:**
```elixir
def analyze(context, %{
  match_transactions: %{discrepancies: discreps},
  fetch_bank_movements: %{failed: failed_banks}
}) do
  # Extract only what you need
  {:ok, %{analysis: DiscrepancyAnalyzer.analyze(discreps, failed_banks)}}
end
```

**With guards:**
```elixir
def process(context, %{fetch_data: %{status: :complete, items: items}})
    when length(items) > 0 do
  {:ok, items}
end

def process(context, %{fetch_data: %{status: :empty}}) do
  {:error, :no_data}
end
```

### Engine Resolution Algorithm

```elixir
# The engine maintains a results cache
cache = %{
  load_expected_transfers: [transfer1, transfer2],
  fetch_bank_movements: %{movements: ..., failed: []},
  match_transactions: %{matched: ..., discrepancies: ...}
}

# When calling a function, it inspects parameter patterns
def match_transactions(context, %{
  fetch_bank_movements: bank_data,
  load_expected_transfers: expected
}) do
  # Engine extracts required atoms: [:fetch_bank_movements, :load_expected_transfers]
  # Engine builds map from cache
  # Engine calls: match_transactions(context, cache)
end
```

**Key Points:**
- ✅ Atom keys are **exact function names** (no normalization)
- ✅ Pattern matching is **pure Elixir** (no DSL magic)
- ✅ Engine injects **complete cache as map**
- ✅ Functions extract **only what they need** via pattern matching

---

## Timeline vs Diverge vs Branch

### Timeline: The Sacred Path

The main execution flow when everything goes right.

```elixir
timeline do
  start()
  |> load_data()
  |> process_data()
  |> save_results()
  |> finish()
end
```

**Characteristics:**
- Sequential execution
- Happy path
- No error handling
- Clean and readable

### Diverge: Error Recovery

Handles errors, failures, and exceptional cases.

```elixir
diverge from: :fetch_api_data do
  # Network timeout - retry
  {:error, :timeout} when context.retry_count < 3 ->
    increment_retry() |> back_to(:fetch_api_data)

  # Max retries exceeded - fail
  {:error, :timeout} ->
    finish_with_error(:max_retries_exceeded)

  # Success - continue timeline
  {:ok, _} -> continue()
end
```

**When to use:**
- API failures
- Timeouts
- Network errors
- Retry logic
- Recovery mechanisms

**Semantics:** "Something went wrong, how do we recover?"

### Branch: Business Logic

Handles normal business decisions where all paths are valid.

```elixir
branch from: :check_amount do
  # Large amount - needs approval
  {:ok, %{amount: amt}} when amt >= 10_000 ->
    request_approval() |> skip_to(:finalize)

  # Small amount - auto-approve
  {:ok, %{amount: amt}} when amt < 10_000 ->
    auto_approve() |> skip_to(:finalize)
end
```

**When to use:**
- Amount thresholds
- User role-based routing
- Feature flags
- A/B testing paths
- Business rule branching

**Semantics:** "Based on data, which valid path do we take?"

### Comparison Table

| Aspect | Timeline | Diverge | Branch |
|--------|----------|---------|--------|
| **Purpose** | Happy path | Error handling | Business logic |
| **All paths valid?** | Yes (sequential) | No (recovery) | Yes (alternatives) |
| **Metrics** | Duration, throughput | Error rate, retry count | Distribution % |
| **Example** | Process order | Network timeout | Amount threshold |
| **Alerting** | Slowness | High error rate | Skewed distribution |

---

## Context and State Management

### Context: Immutable Execution Metadata

The `context` is immutable and flows through the entire workflow:

```elixir
defmodule Context do
  @enforce_keys [:execution_id, :workflow_version, :started_at]
  defstruct [
    # Identity
    :execution_id,        # UUID for this execution
    :workflow_version,    # Version of workflow code
    :correlation_id,      # For distributed tracing

    # Timestamps
    :started_at,
    :updated_at,

    # User inputs (from workflow invocation)
    :date,
    :user_id,
    :bank_accounts,

    # Workflow state
    retry_count: 0,
    iteration: 0,

    # Metadata
    tags: [],
    metadata: %{}
  ]
end
```

**Rules:**
- ✅ Context is **immutable** (functional)
- ✅ Context is **always the first parameter** to every function
- ✅ Context contains **workflow-level state** (retry counts, iterations)
- ✅ Context contains **user inputs** (date, accounts, etc.)
- ❌ Context does NOT contain **results** (those are in the cache)

### Results Cache: Function Outputs

The engine maintains a cache of results indexed by function name:

```elixir
# Internal engine state
%{
  context: %Context{execution_id: "exec-123", ...},

  results: %{
    load_expected_transfers: [transfer1, transfer2],
    fetch_bank_movements: %{movements: ..., failed: []},
    match_transactions: %{matched: ..., discrepancies: ...}
  },

  current_step: :analyze_discrepancies
}
```

**Rules:**
- ✅ Results are indexed by **function name atom**
- ✅ Each function produces **one result** (stored in cache)
- ✅ Functions access results via **pattern matching**
- ✅ Cache persists across retries and loops

### Message Types (Function Return Values)

```elixir
# Success - continue to next step
{:ok, result}

# Error - trigger diverge or fail
{:error, reason}

# Sleep - pause execution without blocking
{:sleep, [seconds: 60], state}

# Parallel - execute tasks concurrently
{:parallel, [task1, task2], state}

# Wait for approval - human-in-the-loop
{:wait_for_approval, [type: :manual_review], state}

# Custom tagged returns for branching
{:needs_approval, result}
{:auto_approved, result}
{:retry_required, result}
```

---

## Complete Example

### Bank Reconciliation Workflow

```elixir
defmodule Fintech.Workflows.BankReconciliation do
  use Cerebelum.Workflow

  @moduledoc """
  Multi-bank reconciliation workflow.

  Fetches movements from multiple banks (Santander, BBVA, BancoEstado),
  matches them against expected transfers, and handles discrepancies.
  """

  # ============================================================================
  # WORKFLOW DEFINITION
  # ============================================================================

  workflow do
    timeline do
      start()
      |> load_expected_transfers()
      |> fetch_bank_movements()
      |> match_transactions()
      |> analyze_discrepancies()
      |> update_database()
      |> generate_report()
      |> send_notifications()
      |> finish_success()
    end

    # Error handling: Bank API failures
    diverge from: :fetch_bank_movements do
      {:ok, %{failed: [_|_]}} when context.retry_count < 3 ->
        increment_retry_count() |> back_to(:fetch_bank_movements)

      {:ok, %{failed: [_|_]}} ->
        finish_partial_failure()

      _ -> continue()
    end

    # Business logic: Approval routing
    branch from: :analyze_discrepancies do
      {:ok, %{major: [_|_]}} ->
        request_manual_approval()
        |> process_approval_decision()
        |> skip_to(:update_database)

      {:ok, %{major: [], minor: [_|_]}} ->
        auto_approve_minor()
        |> skip_to(:update_database)

      _ -> continue()
    end
  end

  # ============================================================================
  # FUNCTIONS (Workflow Nodes)
  # ============================================================================

  @doc "Initialize workflow context"
  def start(context) do
    {:ok, context}
  end

  @doc "Load expected transfers from database"
  def load_expected_transfers(context) do
    transfers =
      ExpectedTransfer
      |> where([t], fragment("DATE(?)", t.scheduled_at) == ^context.date)
      |> where([t], t.status == :pending)
      |> Repo.all()

    {:ok, transfers}
  end

  @doc "Fetch movements from all banks in parallel"
  def fetch_bank_movements(context, %{load_expected_transfers: _expected}) do
    # Execute in parallel
    results =
      context.bank_accounts
      |> Enum.map(&Task.async(fn -> fetch_from_bank(&1, context.date) end))
      |> Task.await_many(timeout: 30_000)

    movements = extract_successful_movements(results)
    failed = extract_failed_banks(results)

    {:ok, %{
      movements: movements,
      failed: failed,
      fetched_at: DateTime.utc_now()
    }}
  end

  @doc "Match expected transfers with actual bank movements"
  def match_transactions(context, %{
    load_expected_transfers: expected,
    fetch_bank_movements: bank_data
  }) do
    all_movements = Map.values(bank_data.movements) |> List.flatten()
    {matched, discrepancies} = Matcher.match(expected, all_movements)

    {:ok, %{
      matched: matched,
      discrepancies: discrepancies
    }}
  end

  @doc "Analyze discrepancies and categorize by severity"
  def analyze_discrepancies(context, %{
    match_transactions: %{discrepancies: discreps}
  }) do
    analysis = DiscrepancyAnalyzer.categorize(discreps)

    minor = Enum.filter(analysis, &(&1.amount < 10_000))
    major = Enum.filter(analysis, &(&1.amount >= 10_000))

    {:ok, %{
      minor: minor,
      major: major,
      total_amount: calculate_total_amount(analysis)
    }}
  end

  @doc "Update database with matched transfers"
  def update_database(context, %{
    match_transactions: %{matched: matched},
    analyze_discrepancies: analysis
  }) do
    Repo.transaction(fn ->
      # Mark matched transfers as reconciled
      Enum.each(matched, fn match ->
        ExpectedTransfer
        |> Repo.get(match.transfer_id)
        |> ExpectedTransfer.mark_as_reconciled(match.bank_movement_id)
        |> Repo.update!()
      end)

      # Log discrepancies
      log_discrepancies(analysis)
    end)

    {:ok, :saved}
  end

  @doc "Generate reconciliation report"
  def generate_report(context, %{
    match_transactions: match_result,
    analyze_discrepancies: analysis,
    fetch_bank_movements: bank_data
  }) do
    report = %ReconciliationReport{
      execution_id: context.execution_id,
      date: context.date,
      matched_count: length(match_result.matched),
      minor_discrepancies_count: length(analysis.minor),
      major_discrepancies_count: length(analysis.major),
      failed_banks: bank_data.failed,
      generated_at: DateTime.utc_now()
    }

    {:ok, Repo.insert!(report)}
  end

  @doc "Send notifications (email, Slack)"
  def send_notifications(context, %{generate_report: report}) do
    Mailer.send_reconciliation_report(report)
    SlackNotifier.post_summary(report)
    {:ok, :sent}
  end

  @doc "Finish workflow successfully"
  def finish_success(context, %{match_transactions: result}) do
    {:ok, %{
      status: :completed,
      execution_id: context.execution_id,
      matched_count: length(result.matched)
    }}
  end

  # ============================================================================
  # HELPER FUNCTIONS (Private)
  # ============================================================================

  defp fetch_from_bank(account, date) do
    case BankAPI.get_movements(account.bank_id, account.account_number, date) do
      {:ok, movements} -> {:ok, %{bank_id: account.bank_id, movements: movements}}
      {:error, reason} -> {:error, %{bank_id: account.bank_id, reason: reason}}
    end
  end

  defp extract_successful_movements(results) do
    results
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.into(%{}, fn {:ok, %{bank_id: id, movements: mvts}} -> {id, mvts} end)
  end

  defp extract_failed_banks(results) do
    results
    |> Enum.filter(&match?({:error, _}, &1))
    |> Enum.map(fn {:error, %{bank_id: id}} -> id end)
  end

  defp calculate_total_amount(discrepancies) do
    Enum.reduce(discrepancies, Money.new(0, :CLP), fn d, acc ->
      Money.add(acc, d.amount)
    end)
  end

  defp log_discrepancies(analysis) do
    # Log to database or external service
    :ok
  end
end
```

### Usage

```elixir
# Execute the workflow
{:ok, execution} = Cerebelum.execute_workflow(
  Fintech.Workflows.BankReconciliation,
  %{
    date: Date.utc_today() |> Date.add(-1),
    user_id: "system",
    bank_accounts: [
      %{bank_id: "santander", account_number: "12345678"},
      %{bank_id: "bbva", account_number: "87654321"},
      %{bank_id: "banco_estado", account_number: "11223344"}
    ]
  }
)

# Check execution status
Cerebelum.get_execution_status(execution.id)

# Time-travel debugging
Cerebelum.Debug.replay(execution.id)
Cerebelum.Debug.state_at_step(execution.id, :match_transactions)
```

---

## How the Engine Works

### 1. Workflow Registration

```elixir
# When module is compiled
defmodule MyWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      start() |> process() |> finish()
    end
  end
end

# The macro extracts:
# - Timeline graph structure
# - Diverge/branch definitions
# - Function list
# - Module bytecode (for versioning)
```

### 2. Execution Flow

```elixir
# Initial state
state = %{
  context: %Context{
    execution_id: "exec-123",
    date: ~D[2024-01-15],
    retry_count: 0
  },
  results: %{},
  current_step: :start
}

# Execute timeline
for step <- [:start, :load_expected_transfers, :fetch_bank_movements, ...] do
  # 1. Inspect function parameters
  params = introspect_function_params(MyWorkflow, step)
  # => [:context, %{load_expected_transfers: _}]

  # 2. Build arguments from cache
  args = [state.context, state.results]

  # 3. Execute function
  result = apply(MyWorkflow, step, args)

  # 4. Handle return value
  case result do
    {:ok, value} ->
      # Save result in cache
      state = put_in(state.results[step], value)

      # Check for diverge/branch
      handle_diverge_or_branch(step, result, state)

    {:error, reason} ->
      handle_error(reason, state)

    {:sleep, opts, value} ->
      handle_sleep(opts, value, state)
  end
end
```

### 3. Parameter Introspection

```elixir
defmodule Cerebelum.Engine.Introspection do
  def introspect_function_params(module, function_name) do
    # Get module BEAM bytecode
    {:ok, {_, [{:abstract_code, {_, ac}}]}} =
      :beam_lib.chunks(module, [:abstract_code])

    # Find function definition
    {:function, _, ^function_name, arity, clauses} =
      find_function(ac, function_name)

    # Extract first clause parameters
    {:clause, _, params, _, _} = hd(clauses)

    # Parse parameter patterns
    Enum.map(params, &parse_param_pattern/1)
  end

  defp parse_param_pattern({:var, _, :context}) do
    :context
  end

  defp parse_param_pattern({:map, _, fields}) do
    # Extract atom keys from map pattern
    # %{load_expected_transfers: x, fetch_bank: y}
    # => [:load_expected_transfers, :fetch_bank]
    extract_atom_keys(fields)
  end
end
```

### 4. Result Resolution

```elixir
defmodule Cerebelum.Engine.Resolver do
  def build_function_args(params, context, results_cache) do
    Enum.map(params, fn
      :context ->
        context

      required_atoms when is_list(required_atoms) ->
        # Build map with required results
        Map.take(results_cache, required_atoms)
    end)
  end
end

# Example:
# Function: match_transactions(context, %{
#   load_expected_transfers: expected,
#   fetch_bank_movements: bank_data
# })
#
# params = [:context, [:load_expected_transfers, :fetch_bank_movements]]
#
# build_function_args(params, context, cache)
# => [
#   %Context{...},
#   %{
#     load_expected_transfers: [transfer1, transfer2],
#     fetch_bank_movements: %{movements: ...}
#   }
# ]
```

### 5. Diverge/Branch Evaluation

```elixir
defmodule Cerebelum.Engine.Flow do
  def handle_diverge(step, result, state) do
    # Get diverge definition for this step
    diverge_clauses = get_diverge_clauses(state.workflow, step)

    # Evaluate each clause with pattern matching
    Enum.find_value(diverge_clauses, fn {pattern, guard, action} ->
      if pattern_matches?(result, pattern) and guard_passes?(guard, state.context) do
        execute_action(action, state)
      end
    end) || continue_timeline(state)
  end
end
```

---

## Design Decisions Log

### Decision 1: Timeline + Diverge + Branch (vs single "edge" keyword)

**Date:** 2024-10-31

**Problem:** Original design had individual `edge` declarations which were hard to read and didn't show the main flow clearly.

**Considered:**
- A) Individual `edge` declarations
- B) `flow` + `branch`
- C) `timeline` + `diverge` + `branch`

**Chosen:** C - `timeline` + `diverge` + `branch`

**Rationale:**
- `timeline` clearly shows the happy path
- `diverge` vs `branch` separates errors from business logic
- Inspired by multiverse/timeline terminology (natural metaphor)
- Better observability (can track divergence rate vs branch distribution)

### Decision 2: Pattern Matching with Atom Keys (vs custom structs)

**Date:** 2024-10-31

**Problem:** How to pass data between functions without creating boilerplate structs or using magic name normalization.

**Considered:**
- A) Custom struct for each message
- B) String-based names with normalization
- C) Variable names matching function names
- D) Atoms as keyword list keys
- E) Atoms as map keys with pattern matching

**Chosen:** E - Atoms as map keys with pattern matching

**Rationale:**
- Idiomatically Elixir (pattern matching is core)
- No boilerplate (no struct definitions needed)
- No magic (exact atom matching)
- Works with guards and deep pattern matching
- Familiar (like working with Plug.Conn, Ecto.Changeset)

**Example:**
```elixir
def match_transactions(context, %{
  load_expected_transfers: expected,
  fetch_bank_movements: bank_data
}) do
  # Pattern match extracts only what's needed
end
```

### Decision 3: Exact Atom Matching (vs name normalization)

**Date:** 2024-10-31

**Problem:** Should we normalize function names to match parameter names?

**Considered:**
- A) Normalize: `load_expected_transfers` → `expected_transfers`
- B) Exact match: parameter must be `:load_expected_transfers`

**Chosen:** B - Exact atom matching

**Rationale:**
- No magic/surprises
- Clear errors (atom not found)
- Refactoring-friendly (rename function = update all references)
- Compile-time safety

### Decision 4: Context as First Parameter (vs implicit)

**Date:** 2024-10-31

**Problem:** How should functions access the execution context?

**Considered:**
- A) Implicit global context
- B) Context as first parameter (explicit)
- C) Context in results map

**Chosen:** B - Context as first parameter

**Rationale:**
- Explicit (you see it in the signature)
- Testable (easy to inject)
- Familiar (like `conn` in Plug, `socket` in Phoenix)
- Immutable (passed by value)

### Decision 5: Results as Second Parameter Map (vs positional args)

**Date:** 2024-10-31

**Problem:** How to handle multiple dependencies?

**Considered:**
- A) Positional: `fn(context, prev, prev-1, prev-2)`
- B) Keyword list: `fn(context, load_data: x, process: y)`
- C) Map: `fn(context, %{load_data: x, process: y})`

**Chosen:** C - Map with pattern matching

**Rationale:**
- Order-independent (can request any previous result)
- Pattern matching works naturally
- Can destructure deeply
- Works with guards

---

## Next Steps

1. **Implement `use Cerebelum.Workflow` macro**
   - Extract timeline, diverge, branch definitions
   - Validate graph structure at compile-time
   - Generate workflow metadata

2. **Implement execution engine**
   - Context management
   - Results cache
   - Parameter introspection
   - Function execution
   - Flow control (diverge/branch)

3. **Implement time-travel debugging**
   - Event sourcing for all executions
   - State reconstruction
   - Step-by-step replay

4. **Create example workflows**
   - Bank reconciliation (this document)
   - E-commerce order processing
   - Multi-step approval workflow
   - Data pipeline with retries

5. **Write comprehensive tests**
   - Macro expansion tests
   - Engine execution tests
   - Pattern matching resolution tests
   - Error handling tests

---

## References

- [Elixir Pattern Matching](https://elixir-lang.org/getting-started/pattern-matching.html)
- [OTP GenServer](https://hexdocs.pm/elixir/GenServer.html)
- [Temporal Workflows](https://docs.temporal.io/workflows)
- [LangGraph](https://langchain-ai.github.io/langgraph/)
- [Elixir Macros](https://elixir-lang.org/getting-started/meta/macros.html)

---

**End of Document**

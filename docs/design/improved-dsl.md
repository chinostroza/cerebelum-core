# Cerebelum Improved DSL - Concise Syntax

**Status:** Design
**Created:** 2025-11-10
**Goal:** Make workflow code more concise while maintaining all power and expressiveness

---

## Table of Contents

1. [Overview](#overview)
2. [Comparison: Before vs After](#comparison-before-vs-after)
3. [Timeline Syntax](#timeline-syntax)
4. [Diverge Syntax](#diverge-syntax)
5. [Branch Syntax](#branch-syntax)
6. [Parallel & Communication](#parallel--communication)
7. [Complete Examples](#complete-examples)
8. [Implementation](#implementation)

---

## Overview

The improved DSL uses Elixir macros (like Ecto and Phoenix) to provide multiple syntax options:
- **Concise syntax** for simple cases (80% of workflows)
- **Flexible syntax** for complex cases (20% of workflows)
- **No magic** - everything compiles to the same ExecutionEngine code

**Philosophy:** Code-first but reads like pseudocode.

---

## Comparison: Before vs After

### Example: Simple Order Workflow

**Before (current):**
```elixir
defmodule OrderWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      start()
      |> load_order()
      |> validate_payment()
      |> process_payment()
      |> ship_order()
      |> finish_success()
    end

    diverge from process_payment do
      {:error, :payment_failed} when context.retry_count < 3 ->
        increment_retry() |> back_to(process_payment)

      {:error, :payment_failed} ->
        cancel_order() |> finish_failed()

      {:ok, _} ->
        continue()
    end

    branch from validate_payment do
      {:ok, %{amount: amt}} when amt >= 10_000 ->
        request_approval() |> skip_to(ship_order)

      {:ok, %{amount: _}} ->
        continue()
    end
  end

  def load_order(context, _deps) do
    order = Repo.get(Order, context.order_id)
    {:ok, order}
  end

  def process_payment(context, %{validate_payment: validation}) do
    result = PaymentService.charge(validation.amount)
    result
  end
end
```

**After (improved):**
```elixir
defmodule OrderWorkflow do
  use Cerebelum.Workflow

  # Concise timeline - list of atoms
  flow :start, :load_order, :validate_payment, :process_payment, :ship_order, :done

  # Concise error handling
  on_error :process_payment do
    :payment_failed, retry: 3 -> :process_payment
    :payment_failed -> cancel_order() |> :failed
  end

  # Concise branching
  when_match :validate_payment do
    amount >= 10_000 -> request_approval() |> :ship_order
  end

  # Steps with implicit deps via pattern matching
  step load_order(ctx) do
    Repo.get(Order, ctx.order_id)
  end

  step process_payment(%{validate_payment: v}) do
    PaymentService.charge(v.amount)
  end
end
```

**Improvements:**
- ✅ 50% less lines
- ✅ `flow` instead of `timeline do...end`
- ✅ `on_error` instead of `diverge from...do`
- ✅ `when_match` instead of `branch from...do`
- ✅ `step` macro with automatic `{:ok, result}` wrapping
- ✅ Pattern matching in function head (no need for second param)
- ✅ Atoms for targets (`:done` instead of `finish_success()`)

---

## Timeline Syntax

### Option 1: Atom list (most concise)

```elixir
# Simple linear flow
flow :start, :load, :process, :save, :done
```

**Compiles to:**
```elixir
workflow do
  timeline do
    start()
    |> load()
    |> process()
    |> save()
    |> finish_success()
  end
end
```

### Option 2: Arrow syntax (visual)

```elixir
# Arrow shows flow direction
flow :start -> :load -> :process -> :save -> :done
```

### Option 3: Block syntax (when you need logic)

```elixir
# Full control when needed
flow do
  start()
  |> load()
  |> maybe_transform()  # conditional step
  |> process()
  |> done()
end
```

### Aliases for common endings:

```elixir
:done       # -> finish_success()
:failed     # -> finish_failed()
:cancelled  # -> finish_cancelled()
:timeout    # -> finish_timeout()
```

---

## Diverge Syntax

### Option 1: Concise `on_error`

```elixir
# Simple retry logic
on_error :process_payment do
  :payment_failed, retry: 3 -> :process_payment
  :payment_failed -> :failed
  :timeout -> :failed
end
```

**Compiles to:**
```elixir
diverge from process_payment do
  {:error, :payment_failed} when context.retry_count < 3 ->
    increment_retry() |> back_to(process_payment)

  {:error, :payment_failed} ->
    finish_failed()

  {:error, :timeout} ->
    finish_failed()

  {:ok, _} ->
    continue()
end
```

### Option 2: Inline guard syntax

```elixir
on_error :fetch_data do
  :timeout when retry < 3 -> retry(:fetch_data)
  :timeout -> :failed
  :not_found -> skip_to(:use_default)
end
```

### Option 3: With actions

```elixir
on_error :process_payment do
  :payment_failed, retry: 3, delay: 5000 -> :process_payment
  :payment_failed -> cancel_order() |> :failed
  :insufficient_funds -> request_more_funds() |> :process_payment
end
```

---

## Branch Syntax

### Option 1: Concise `when_match`

```elixir
# Condition-based routing
when_match :validate_payment do
  amount >= 10_000 -> request_approval() |> :ship_order
  amount < 1_000 -> auto_approve() |> :ship_order
end
```

**Compiles to:**
```elixir
branch from validate_payment do
  {:ok, %{amount: amt}} when amt >= 10_000 ->
    request_approval() |> skip_to(ship_order)

  {:ok, %{amount: amt}} when amt < 1_000 ->
    auto_approve() |> skip_to(ship_order)

  _ ->
    continue()
end
```

### Option 2: Pattern matching sugar

```elixir
when_match :analyze_risk do
  {risk, :high} -> manual_review() |> :approval
  {risk, :medium} -> automated_check() |> :approval
  {risk, :low} -> :ship_order
end
```

### Option 3: With helpers

```elixir
# Multiple conditions
when_match :validate_order do
  vip_customer? and amount > 5_000 -> :priority_queue
  amount > 10_000 -> :approval_required
  else -> :continue
end
```

---

## Parallel & Communication

### Option 1: Concise parallel syntax

```elixir
# Simple parallel agents
step run_agents do
  parallel [ResearchAgent, WriterAgent, CriticAgent],
    with: %{topic: "AI safety"},
    timeout: 60_000
end
```

### Option 2: With communication

```elixir
# Agents that communicate
step run_team do
  parallel [
    {LeaderAgent, role: :coordinator},
    {WorkerAgent, role: :executor},
    {ReviewerAgent, role: :validator}
  ], timeout: 120_000
end
```

### Message sending (concise)

```elixir
# Broadcast
step research_and_share do
  findings = conduct_research()
  broadcast :research_complete, findings
  ok(findings)
end
```

### Message receiving (concise)

```elixir
# Receive with pattern matching
step wait_for_research do
  receive_from ResearchAgent do
    :research_complete, data -> ok(data)
    :error, reason -> error(reason)
  after 30_000 ->
    timeout()
  end
end

# Or even simpler
step wait_for_research do
  await ResearchAgent, :research_complete, timeout: 30_000
end
```

---

## Complete Examples

### Example 1: Bank Reconciliation (Concise)

```elixir
defmodule BankReconciliation do
  use Cerebelum.Workflow

  flow :start,
       :load_expected,
       :fetch_movements,
       :match_transactions,
       :analyze_discrepancies,
       :save,
       :done

  on_error :fetch_movements do
    :bank_timeout, retry: 3 -> :fetch_movements
    :bank_timeout -> :failed
  end

  when_match :analyze_discrepancies do
    has_major_issues? -> request_approval() |> :save
  end

  step load_expected(ctx) do
    ExpectedTransfer
    |> where(date: ^ctx.date, status: :pending)
    |> Repo.all()
  end

  step fetch_movements(%{load_expected: expected}) do
    banks = extract_banks(expected)
    fetch_from_banks(banks, parallel: true)
  end

  step match_transactions(%{load_expected: exp, fetch_movements: mov}) do
    Matcher.match(exp, mov.movements)
  end

  step analyze_discrepancies(%{match_transactions: %{discrepancies: disc}}) do
    DiscrepancyAnalyzer.categorize(disc)
  end

  step save(%{match_transactions: matched, analyze_discrepancies: analysis}) do
    Repo.transaction(fn ->
      mark_as_reconciled(matched)
      log_discrepancies(analysis)
    end)
  end
end
```

**Comparison:**
- Before: ~150 lines
- After: ~45 lines
- Same functionality, 70% less code

### Example 2: Multi-Agent Content Creation

```elixir
defmodule ContentCreation do
  use Cerebelum.Workflow

  flow :start,
       :analyze_requirements,
       :parallel_research,
       :generate_outline,
       :parallel_writing,
       :review,
       :publish,
       :done

  when_match :review do
    quality >= 0.8 -> :publish
    quality >= 0.6 -> request_human_review() |> :review
    else -> regenerate() |> :parallel_writing
  end

  step analyze_requirements(ctx) do
    RequirementsAnalyzer.analyze(ctx.brief, ctx.audience)
  end

  step parallel_research(%{analyze_requirements: reqs}) do
    parallel [
      {WebResearcher, topics: reqs.topics},
      {CompetitorAnalyzer, industry: reqs.industry},
      {TrendAnalyzer, keywords: reqs.keywords}
    ], timeout: 60_000
  end

  step generate_outline(%{analyze_requirements: reqs, parallel_research: research}) do
    OutlineGenerator.create(reqs, research)
  end

  step parallel_writing(%{generate_outline: outline}) do
    # Generate each section in parallel
    sections = outline.sections
    |> Enum.map(fn section ->
      {SectionWriter, section: section, tone: ctx.tone}
    end)

    parallel sections, timeout: 120_000
  end

  step review(%{parallel_writing: sections}) do
    QualityReviewer.review(sections)
  end

  step publish(%{parallel_writing: sections, review: review}) do
    content = assemble_content(sections)
    Publisher.publish(content, review.metadata)
  end
end
```

### Example 3: Group Chat with Communication

```elixir
defmodule GroupChat do
  use Cerebelum.Workflow

  flow :start,
       :init_conversation,
       :run_rounds,
       :consolidate,
       :done

  # Loop control with branch
  when_match :run_rounds do
    round < max_rounds and not consensus? -> next_round() |> :run_rounds
    consensus? -> :consolidate
    else -> :consolidate
  end

  step init_conversation(ctx) do
    ok(%{
      topic: ctx.topic,
      agents: [ResearchAgent, WriterAgent, CriticAgent],
      history: [],
      round: 0,
      max_rounds: 10
    })
  end

  step run_rounds(%{init_conversation: state}) do
    # Select next speaker
    next_speaker = select_speaker(state)

    # Execute agent
    result = execute_subworkflow(next_speaker, %{
      topic: state.topic,
      history: state.history,
      round: state.round
    })

    # Update state
    new_history = state.history ++ [%{
      agent: next_speaker,
      round: state.round,
      message: result.message
    }]

    ok(%{state |
      history: new_history,
      round: state.round + 1,
      consensus: check_consensus(new_history)
    })
  end

  step consolidate(%{run_rounds: state}) do
    synthesize_conversation(state.history)
  end

  # Agent implementations (concise)
  defmodule ResearchAgent do
    use Cerebelum.Workflow

    flow :start, :research, :share, :done

    step research(ctx) do
      findings = conduct_research(ctx.topic, ctx.history)
      ok(findings)
    end

    step share(%{research: findings}) do
      broadcast :research_complete, findings
      ok(findings)
    end
  end

  defmodule WriterAgent do
    use Cerebelum.Workflow

    flow :start, :wait_research, :write, :done

    step wait_research do
      await ResearchAgent, :research_complete, timeout: 30_000
    end

    step write(%{wait_research: research}) do
      content = generate_content(research)
      broadcast :draft_ready, content
      ok(content)
    end
  end
end
```

---

## Step Macro Features

### Automatic result wrapping

```elixir
# You write:
step load_order(ctx) do
  Repo.get(Order, ctx.order_id)
end

# Compiles to:
def load_order(context, _deps) do
  result = Repo.get(Order, context.order_id)
  {:ok, result}
end
```

### Pattern matching on dependencies

```elixir
# You write:
step process_payment(%{load_order: order}) do
  PaymentService.charge(order.amount)
end

# Compiles to:
def process_payment(context, %{load_order: order}) do
  result = PaymentService.charge(order.amount)
  {:ok, result}
end
```

### Explicit error handling

```elixir
step risky_operation do
  case ExternalAPI.call() do
    {:ok, data} -> ok(data)
    {:error, reason} -> error(reason)
  end
end
```

### Access to context when needed

```elixir
step process_with_context(ctx, %{load_data: data}) do
  # Access both context and dependencies
  result = process(data, user_id: ctx.user_id)
  ok(result)
end
```

---

## Helper Functions

### Result helpers (like Rust)

```elixir
ok(value)          # -> {:ok, value}
error(reason)      # -> {:error, reason}
timeout()          # -> {:timeout, %{}}
partial(data)      # -> {:partial, data}
```

### Flow control helpers

```elixir
retry(step)              # -> back_to(step) with increment
skip_to(step)            # -> skip_to(step)
cancel()                 # -> finish_cancelled()
```

### Message helpers

```elixir
broadcast(type, data)                    # Broadcast to all peers
send_to(agent, type, data)              # Send to specific agent
await(agent, type, opts)                # Wait for message (simple)
receive_from(agent, do: clauses)        # Wait with pattern matching
```

### Parallel helpers

```elixir
parallel(agents, opts)                   # Run agents in parallel
parallel_map(list, fn item -> ... end)  # Map over list in parallel
```

---

## Implementation

### Main macro file structure

```elixir
# lib/cerebelum/workflow/dsl.ex
defmodule Cerebelum.Workflow.DSL do

  # Timeline macros
  defmacro flow(steps) when is_list(steps) do
    # Handle: flow [:start, :load, :process, :done]
  end

  defmacro flow({:->>, _, _} = pipeline) do
    # Handle: flow :start -> :load -> :process -> :done
  end

  # Error handling macros
  defmacro on_error(step_name, do: clauses) do
    # Handle: on_error :step do ... end
  end

  # Branching macros
  defmacro when_match(step_name, do: clauses) do
    # Handle: when_match :step do ... end
  end

  # Step macro
  defmacro step(call, do: block) do
    # Handle: step name(params) do ... end
  end

  # Helper functions
  def ok(value), do: {:ok, value}
  def error(reason), do: {:error, reason}
  def timeout(), do: {:timeout, %{}}

  # Parallel helpers
  defmacro parallel(agents, opts \\ []) do
    # Handle: parallel [Agent1, Agent2], opts
  end

  # Message helpers
  defmacro await(agent, message_type, opts \\ []) do
    # Handle: await Agent, :msg_type, timeout: 5000
  end

  defmacro receive_from(agent, do: clauses) do
    # Handle: receive_from Agent do ... end
  end
end
```

### Module attribute accumulation

```elixir
defmodule Cerebelum.Workflow do
  defmacro __using__(_opts) do
    quote do
      import Cerebelum.Workflow.DSL

      Module.register_attribute(__MODULE__, :timeline_steps, accumulate: false)
      Module.register_attribute(__MODULE__, :error_handlers, accumulate: true)
      Module.register_attribute(__MODULE__, :branch_handlers, accumulate: true)

      @before_compile Cerebelum.Workflow
    end
  end

  defmacro __before_compile__(env) do
    timeline = Module.get_attribute(env.module, :timeline_steps)
    errors = Module.get_attribute(env.module, :error_handlers)
    branches = Module.get_attribute(env.module, :branch_handlers)

    # Generate workflow/0 macro expansion
    quote do
      def __workflow_metadata__ do
        %{
          timeline: unquote(Macro.escape(timeline)),
          diverge: unquote(Macro.escape(errors)),
          branch: unquote(Macro.escape(branches))
        }
      end
    end
  end
end
```

---

## Comparison Table

| Feature | Before (Current) | After (Improved) | Reduction |
|---------|------------------|------------------|-----------|
| **Timeline** | `timeline do ... |> ... end` | `flow :start, :load, :done` | 60% |
| **Error handling** | `diverge from step do ... end` | `on_error :step do ... end` | 40% |
| **Branching** | `branch from step do ... end` | `when_match :step do ... end` | 40% |
| **Functions** | `def name(ctx, %{deps}) do {:ok, ...} end` | `step name(%{deps}) do ... end` | 50% |
| **Messages** | `receive do {:msg_from_peer, ...} end` | `await Agent, :msg` | 70% |
| **Parallel** | `{:parallel_subworkflows, [...], opts}` | `parallel [...], opts` | 50% |

**Overall:** 50-70% less code with same functionality and expressiveness.

---

## Migration Path

### Phase 1: Add new macros, keep old syntax working

Both syntaxes work:
```elixir
# Old (still works)
workflow do
  timeline do
    start() |> load() |> done()
  end
end

# New (also works)
flow :start, :load, :done
```

### Phase 2: Documentation shows new syntax

All examples use concise syntax, old syntax in "Advanced" section.

### Phase 3: (Optional) Deprecation warnings

```elixir
@deprecated "Use `flow` instead of `timeline do...end`"
defmacro timeline(do: block), do: ...
```

---

## Benefits

1. ✅ **50-70% less code** - More concise without losing expressiveness
2. ✅ **Easier to learn** - Simpler syntax for beginners
3. ✅ **Still powerful** - Complex cases use full syntax
4. ✅ **No magic** - Everything compiles to same ExecutionEngine code
5. ✅ **Like Ecto/Phoenix** - Follows Elixir conventions
6. ✅ **LSP support** - It's still Elixir, tooling works
7. ✅ **Gradual adoption** - Old syntax keeps working

---

**End of Document**

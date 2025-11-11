# Workflow Syntax Design - Code-First Approach

**Status:** Draft - Final Syntax
**Last Updated:** 2025-11-10
**Context:** This document defines the final syntax for Cerebelum's code-first workflow DSL.

---

## Table of Contents

1. [Design Philosophy](#design-philosophy)
2. [Core Syntax](#core-syntax)
3. [Timeline](#timeline)
4. [Error Handling with Diverge](#error-handling-with-diverge)
5. [Branching with Branch](#branching-with-branch)
6. [Functions](#functions)
7. [Parallel Execution](#parallel-execution)
8. [Agent Communication](#agent-communication)
9. [External Signals](#external-signals)
10. [Subworkflows](#subworkflows)
11. [Complete Examples](#complete-examples)
12. [Syntax Reference](#syntax-reference)

---

## Design Philosophy

### Goals

1. **Code-First**: Workflows are pure Elixir modules, not JSON/YAML
2. **Concise**: Minimal boilerplate, maximum clarity
3. **Idiomatic Elixir**: Leverages pipes, pattern matching, atoms
4. **Explicit over Magic**: Clear what's happening at each step
5. **Scalable**: Built on BEAM/OTP for millions of concurrent workflows

### Principles

- ✅ Timeline shows happy path clearly
- ✅ Atoms with `:` for values, without `:` for identifiers
- ✅ Pattern matching for data flow
- ✅ Retry strategies inspired by Ktor
- ✅ Zero overhead for unused features

---

## Core Syntax

### Quick Example

```elixir
defmodule PaymentWorkflow do
  use Cerebelum.Workflow

  # Happy path - no start() or done()
  timeline do
    validate_payment()
    |> process_payment()
    |> send_receipt()
  end

  # Error handling with retry
  diverge validate_payment do
    :timeout -> retry(3, delay: 2000) |> validate_payment()
    :invalid_card -> notify_customer() |> failed()
  end

  # Conditional branching
  branch process_payment do
    amount > 10_000 -> request_approval()
    amount <= 10_000 -> charge_payment()
  end

  # Function definitions
  fn validate_payment(ctx) do
    case PaymentAPI.validate(ctx.card) do
      {:ok, data} -> data
      {:error, :timeout} -> error(:timeout)
    end
  end
end
```

---

## Timeline

### Syntax

```elixir
timeline do
  step1()
  |> step2()
  |> step3()
  |> step4()
end
```

### Rules

- **No `start()` or `done()`** - implicitly starts at first step, ends at last
- **Uses pipe operator** `|>` for visual flow
- **Steps are function names** without `:`
- **Read top-to-bottom** as the happy path

### Examples

```elixir
# Simple workflow
timeline do
  load_data()
  |> process_data()
  |> save_results()
end

# Complex workflow
timeline do
  validate_application()
  |> verify_documents()
  |> parallel_risk_analysis()
  |> consensus_decision()
  |> human_review()
  |> generate_report()
  |> notify_applicant()
end
```

---

## Error Handling with Diverge

### Syntax

```elixir
diverge step_name do
  :error_type -> action()
  :error_type -> retry(...) |> action()
  :error_type -> step1() |> step2() |> action()
end
```

### Simple Retry

```elixir
diverge validate_payment do
  # Retry with fixed delay
  :timeout -> retry(3, delay: 2000) |> validate_payment()

  # Retry without delay
  :transient_error -> retry(5) |> validate_payment()

  # No retry - go to different step
  :invalid_card -> notify_customer() |> failed()

  # No retry - terminate
  :fraud_detected -> failed()
end
```

### Advanced Retry with Block

```elixir
diverge fetch_data do
  # Linear backoff - 3s, 6s, 9s, 12s, 15s
  :api_timeout ->
    retry do
      attempts 5
      delay fn attempt -> attempt * 3000 end
    end
    |> fetch_data()

  # Exponential backoff - 1s, 2s, 4s, 8s, 16s (max 30s)
  :rate_limited ->
    retry do
      attempts 10
      delay fn attempt -> round(:math.pow(2, attempt) * 1000) end
      max_delay 30_000
      backoff :exponential
    end
    |> fetch_data()

  # With jitter to avoid thundering herd
  :service_busy ->
    retry do
      attempts 5
      delay 5000
      jitter 0.2  # ±20% random
    end
    |> fetch_data()
end
```

### Retry with Intermediate Steps

```elixir
diverge process_payment do
  # Execute steps before retrying
  :gateway_error ->
    retry(3, delay: 5000)
    |> log_retry()
    |> notify_admin()
    |> process_payment()

  # Different path on error
  :insufficient_funds ->
    notify_customer()
    |> request_additional_payment()
    |> failed()
end
```

### Retry Configuration Options

```elixir
retry(
  attempts,                          # Required: number of attempts
  delay: ms | fn,                    # Fixed delay or function
  backoff: :exponential | :linear,   # Backoff strategy
  max_delay: ms,                     # Maximum delay
  jitter: true | float               # Randomization
)

# Examples:
retry(3, delay: 2000)
retry(5, delay: fn attempt -> attempt * 3000 end)
retry(10, delay: 1000, backoff: :exponential, max_delay: 60_000)
retry(5, delay: 5000, jitter: true)
```

---

## Branching with Branch

### Syntax

```elixir
branch step_name do
  condition1 -> destination1()
  condition2 -> destination2()
  condition3 -> destination3()
end
```

### Examples

```elixir
# Simple branching
branch check_amount do
  amount > 10_000 -> request_approval()
  amount <= 10_000 -> auto_approve()
end

# Complex conditions
branch consensus_decision do
  risk_level == :critical -> cancelled()
  risk_level == :high and amount > 100_000 -> escalate_to_committee()
  risk_level == :high -> human_review()
  risk_level == :medium and credit_score > 700 -> auto_approve()
  risk_level == :medium -> human_review()
  risk_level == :low -> generate_report()
end

# With intermediate steps
branch verify_identity do
  identity_verified and age >= 18 -> continue_application()
  identity_verified and age < 18 -> notify_guardian() |> request_approval()
  not identity_verified -> request_documents() |> verify_identity()
end
```

### Rules

- **Fields without `:`** - `risk_level`, `amount`, `status` are fields from previous step
- **Values with `:`** - `:high`, `:low`, `:approved` are atom values
- **Steps without `:`** - `escalate_committee`, `human_review` are function names

---

## Functions

### Syntax

```elixir
fn function_name(ctx) do
  # body
  result  # Auto-wrapped in {:ok, result}
end

fn function_name(ctx, deps) do
  # Access previous results via pattern matching
  result
end
```

### Examples

```elixir
# Simple function
fn validate_payment(ctx) do
  PaymentAPI.validate(ctx.card_number)
end

# With dependencies
fn process_payment(ctx, %{validate_payment: validated}) do
  PaymentGateway.charge(validated.amount)
end

# Multiple dependencies
fn match_transactions(ctx, %{
  load_expected: expected,
  fetch_movements: movements
}) do
  Matcher.match(expected, movements)
end

# With error handling
fn fetch_credit_score(ctx) do
  case CreditBureau.fetch(ctx.ssn) do
    {:ok, score} -> score
    {:error, :timeout} -> error(:bureau_timeout)
    {:error, :not_found} -> error(:no_credit_history)
  end
end

# Deep pattern matching
fn analyze(ctx, %{
  match_transactions: %{discrepancies: discreps},
  fetch_movements: %{failed: failed_banks}
}) do
  DiscrepancyAnalyzer.analyze(discreps, failed_banks)
end
```

### Helper Functions

```elixir
# Return error (triggers diverge)
error(:error_type)

# Return timeout
timeout(%{reason: "took too long"})

# Terminate workflow
done()      # Success
failed()    # Failure
cancelled() # Cancelled
```

---

## Parallel Execution

### Syntax

```elixir
fn step_name(ctx, deps) do
  parallel [
    {Agent1, %{data: ...}},
    {Agent2, %{data: ...}},
    {Agent3, %{data: ...}}
  ],
  timeout: ms,
  on_failure: :stop | :continue,
  min_successes: n
end
```

### Examples

```elixir
# Simple parallel execution
fn parallel_risk_analysis(ctx, %{validate_application: data}) do
  parallel [
    {CreditScoreAgent, %{applicant_id: data.applicant.id}},
    {FinancialAnalysisAgent, %{documents: data.documents}},
    {FraudDetectionAgent, %{applicant: data.applicant}}
  ], timeout: 120_000
end

# With error handling
fn robust_analysis(ctx, deps) do
  parallel [
    {Agent1, %{data: deps.input}},
    {Agent2, %{data: deps.input}},
    {Agent3, %{data: deps.input}}
  ],
  timeout: 60_000,
  on_failure: :continue,   # Don't fail if one fails
  min_successes: 2         # Need at least 2 to succeed
end

# Access results
fn consolidate_results(ctx, %{parallel_risk_analysis: results}) do
  # results is a list of agent outputs
  scores = Enum.map(results, & &1.risk_score)
  avg_score = Enum.sum(scores) / length(scores)

  %{
    average_score: avg_score,
    individual_scores: scores
  }
end
```

---

## Agent Communication

### Overview

Parallel agents can communicate using **broadcast**, **await**, **send_to**, and **receive_from**.

### Broadcast & Await

```elixir
defmodule ProducerAgent do
  use Cerebelum.Workflow

  timeline do
    process_data()
    |> broadcast_results()
  end

  fn broadcast_results(ctx, %{process_data: result}) do
    # Broadcast to all peers in parallel group
    broadcast(:data_ready, %{
      from: ProducerAgent,
      result: result,
      timestamp: DateTime.utc_now()
    })

    result
  end
end

defmodule ConsumerAgent do
  use Cerebelum.Workflow

  timeline do
    wait_for_data()
    |> process_received()
  end

  fn wait_for_data(ctx) do
    # Wait for broadcast from ProducerAgent
    await ProducerAgent, :data_ready, timeout: 30_000
  end

  fn process_received(ctx, %{wait_for_data: received}) do
    # received contains the broadcast payload
    %{
      original: received.result,
      processed_at: DateTime.utc_now()
    }
  end
end
```

### Send To & Receive From

```elixir
defmodule CoordinatorAgent do
  use Cerebelum.Workflow

  timeline do
    prepare_task()
    |> send_task()
    |> wait_response()
  end

  fn send_task(ctx, %{prepare_task: task}) do
    # Send to specific agent
    send_to(WorkerAgent, :task_assigned, task)
    task
  end

  fn wait_response(ctx) do
    # Receive from specific agent
    receive_from(WorkerAgent, :task_complete, timeout: 60_000)
  end
end

defmodule WorkerAgent do
  use Cerebelum.Workflow

  timeline do
    wait_task()
    |> execute_task()
    |> send_result()
  end

  fn wait_task(ctx) do
    receive_from(CoordinatorAgent, :task_assigned, timeout: 30_000)
  end

  fn send_result(ctx, %{execute_task: result}) do
    send_to(CoordinatorAgent, :task_complete, result)
    result
  end
end
```

### Communication Helpers

```elixir
# Broadcast to all peers
broadcast(:message_type, data)

# Await broadcast from agent
await AgentModule, :message_type, timeout: ms

# Send to specific agent
send_to(AgentModule, :message_type, data)

# Receive from specific agent
receive_from(AgentModule, :message_type, timeout: ms)
```

---

## External Signals

### Overview

Workflows can wait for external events (approvals, webhooks, etc.) using `receive_signal`.

### Syntax

```elixir
fn step_name(ctx, deps) do
  receive_signal do
    {:signal_type, data} -> result
    {:other_signal, data} -> other_result
  after timeout ->
    {:timeout, %{}}
  end
end
```

### Example: Human Approval

```elixir
fn wait_for_approval(ctx, %{submit_request: request}) do
  # Notify approver
  ApprovalSystem.notify(ctx.approver_email, request)

  # Wait for external signal
  receive_signal do
    {:approval_decision, %{approved: true, approver: approver}} ->
      %{approved: true, approver: approver, approved_at: DateTime.utc_now()}

    {:approval_decision, %{approved: false, reason: reason}} ->
      error(:approval_rejected)

    {:cancel_request, _data} ->
      error(:request_cancelled)

  after 3_600_000 ->  # 1 hour
    error(:approval_timeout)
  end
end

# Diverge handles errors
diverge wait_for_approval do
  :approval_rejected -> notify_applicant() |> failed()
  :approval_timeout -> escalate_to_manager()
  :request_cancelled -> cancelled()
end
```

### Sending Signals from External Systems

```elixir
# From Elixir code
Cerebelum.send_signal(
  "exec-uuid-123",           # execution_id
  :approval_decision,        # signal name
  %{approved: true, approver: "john@example.com"}
)

# From HTTP API
POST /workflows/exec-123/signal
{
  "signal": "approval_decision",
  "data": {
    "approved": true,
    "approver": "john@example.com"
  }
}
```

---

## Subworkflows

### Syntax

```elixir
fn step_name(ctx, deps) do
  subworkflow(SubWorkflowModule, %{data: ...})
end
```

### Example

```elixir
# Main workflow
fn verify_documents(ctx, %{validate_application: data}) do
  subworkflow(DocumentVerification, %{
    documents: data.documents,
    required_types: [:id, :proof_of_income]
  })
end

# Subworkflow
defmodule DocumentVerification do
  use Cerebelum.Workflow

  timeline do
    extract_data()
    |> validate_format()
    |> verify_authenticity()
  end

  fn extract_data(ctx) do
    Enum.map(ctx.documents, &OCR.extract/1)
  end

  fn validate_format(ctx, %{extract_data: extracted}) do
    Enum.all?(extracted, &valid_format?/1)
  end

  fn verify_authenticity(ctx, %{validate_format: validated}) do
    Enum.all?(validated, &authentic?/1)
  end
end
```

---

## Complete Examples

### Example 1: Payment Processing

```elixir
defmodule PaymentWorkflow do
  use Cerebelum.Workflow

  timeline do
    validate_payment()
    |> check_fraud()
    |> process_payment()
    |> send_receipt()
  end

  diverge validate_payment do
    :timeout -> retry(3, delay: 2000) |> validate_payment()
    :invalid_card -> notify_customer() |> failed()
  end

  diverge process_payment do
    :insufficient_funds -> notify_customer() |> request_payment() |> failed()
    :gateway_error ->
      retry do
        attempts 5
        delay fn attempt -> attempt * 2000 end
        max_delay 30_000
      end
      |> process_payment()
  end

  branch check_fraud do
    fraud_score > 0.8 -> cancel_payment() |> failed()
    fraud_score > 0.5 -> request_verification()
    fraud_score <= 0.5 -> process_payment()
  end

  fn validate_payment(ctx) do
    case PaymentAPI.validate(ctx.card) do
      {:ok, validated} -> validated
      {:error, :timeout} -> error(:timeout)
      {:error, :invalid} -> error(:invalid_card)
    end
  end

  fn check_fraud(ctx, %{validate_payment: payment}) do
    score = FraudDetector.score(payment)
    %{fraud_score: score, validated_payment: payment}
  end

  fn process_payment(ctx, %{check_fraud: check}) do
    case PaymentGateway.charge(check.validated_payment) do
      {:ok, transaction} -> transaction
      {:error, :insufficient_funds} -> error(:insufficient_funds)
      {:error, :gateway_error} -> error(:gateway_error)
    end
  end

  fn send_receipt(ctx, %{process_payment: transaction}) do
    Email.send_receipt(ctx.customer_email, transaction)
    %{receipt_sent: true}
  end
end
```

### Example 2: Loan Application with Multi-Agent

```elixir
defmodule LoanApplication do
  use Cerebelum.Workflow

  timeline do
    validate_application()
    |> verify_documents()
    |> parallel_risk_analysis()
    |> consensus_decision()
    |> human_review()
    |> generate_report()
  end

  diverge validate_application do
    :api_timeout ->
      retry do
        attempts 5
        delay fn attempt -> attempt * 3000 end
        max_delay 30_000
      end
      |> log_retry()
      |> validate_application()

    :invalid_data -> notify_applicant() |> failed()
  end

  branch consensus_decision do
    risk_level == :critical -> cancelled()
    risk_level == :high and amount > 100_000 -> escalate_to_committee()
    risk_level == :high -> human_review()
    risk_level == :low -> generate_report()
  end

  fn validate_application(ctx) do
    case ApplicationAPI.validate(ctx.application_id) do
      {:ok, data} -> data
      {:error, :timeout} -> error(:api_timeout)
      {:error, :invalid} -> error(:invalid_data)
    end
  end

  fn verify_documents(ctx, %{validate_application: data}) do
    subworkflow(DocumentVerification, %{
      documents: data.documents,
      required_types: [:id, :proof_of_income]
    })
  end

  fn parallel_risk_analysis(ctx, deps) do
    parallel [
      {CreditScoreAgent, %{applicant_id: deps.validate_application.applicant.id}},
      {FinancialAnalysisAgent, %{documents: deps.verify_documents}},
      {FraudDetectionAgent, %{applicant: deps.validate_application.applicant}}
    ],
    timeout: 120_000,
    on_failure: :continue,
    min_successes: 2
  end

  fn consensus_decision(ctx, %{parallel_risk_analysis: results}) do
    scores = Enum.map(results, & &1.risk_score)
    avg_score = Enum.sum(scores) / length(scores)

    %{
      risk_level: calculate_risk_level(avg_score),
      amount: ctx.loan_amount,
      scores: results
    }
  end

  fn human_review(ctx, %{consensus_decision: decision}) do
    ReviewSystem.notify_reviewer(ctx.execution_id, decision)

    receive_signal do
      {:review_complete, %{approved: true, reviewer: reviewer}} ->
        %{approved: true, reviewer: reviewer, reviewed_at: DateTime.utc_now()}

      {:review_complete, %{approved: false, reason: reason}} ->
        error(:review_rejected)

    after 7_200_000 ->  # 2 hours
      error(:review_timeout)
    end
  end
end

# Agent with communication
defmodule CreditScoreAgent do
  use Cerebelum.Workflow

  timeline do
    fetch_credit_data()
    |> calculate_score()
    |> broadcast_results()
    |> listen_for_fraud()
    |> finalize()
  end

  diverge fetch_credit_data do
    :bureau_timeout -> retry(3, delay: 3000) |> fetch_credit_data()
    :bureau_unavailable -> failed()
  end

  fn fetch_credit_data(ctx) do
    case CreditBureau.fetch(ctx.applicant_id) do
      {:ok, data} -> data
      {:error, :timeout} -> error(:bureau_timeout)
      {:error, :unavailable} -> error(:bureau_unavailable)
    end
  end

  fn calculate_score(ctx, %{fetch_credit_data: data}) do
    score = RiskModel.calculate(data)
    %{risk_score: score, credit_data: data}
  end

  fn broadcast_results(ctx, %{calculate_score: result}) do
    broadcast(:credit_analysis_complete, %{
      agent: CreditScoreAgent,
      risk_score: result.risk_score
    })
    result
  end

  fn listen_for_fraud(ctx, %{calculate_score: analysis}) do
    case await FraudDetectionAgent, :fraud_alert, timeout: 10_000 do
      {:ok, %{fraud_detected: true, severity: severity}} ->
        # Adjust score if fraud detected
        adjusted = min(1.0, analysis.risk_score + severity * 0.3)
        %{analysis | risk_score: adjusted, fraud_flagged: true}

      _ ->
        Map.put(analysis, :fraud_flagged, false)
    end
  end

  fn finalize(ctx, %{listen_for_fraud: final}) do
    final
  end
end
```

---

## Syntax Reference

### Timeline

```elixir
timeline do
  step1()
  |> step2()
  |> step3()
end
```

### Diverge

```elixir
# Simple
diverge step_name do
  :error_type -> retry(N, delay: MS) |> step()
  :error_type -> step1() |> step2() |> failed()
end

# Complex
diverge step_name do
  :error_type ->
    retry do
      attempts N
      delay fn attempt -> MS end
      max_delay MS
      backoff :exponential
      jitter 0.2
    end
    |> step()
end
```

### Branch

```elixir
branch step_name do
  condition1 -> destination1()
  condition2 -> destination2()
end
```

### Functions

```elixir
fn function_name(ctx) do
  result  # Auto-wrapped in {:ok, result}
end

fn function_name(ctx, deps) do
  result
end
```

### Parallel

```elixir
parallel [
  {Agent1, %{...}},
  {Agent2, %{...}}
],
timeout: MS,
on_failure: :stop | :continue,
min_successes: N
```

### Communication

```elixir
broadcast(:message_type, data)
await AgentModule, :message_type, timeout: MS
send_to(AgentModule, :message_type, data)
receive_from(AgentModule, :message_type, timeout: MS)
```

### Signals

```elixir
receive_signal do
  {:signal_type, data} -> result
after timeout -> {:timeout, %{}}
end
```

### Subworkflows

```elixir
subworkflow(ModuleName, %{data: ...})
```

### Helpers

```elixir
error(:type)      # Trigger diverge
timeout(data)     # Timeout error
done()            # Success
failed()          # Failure
cancelled()       # Cancelled
```

### Naming Rules

- **Steps (no `:`)** - `validate_payment`, `CreditScoreAgent`
- **Error types (with `:`)** - `:timeout`, `:invalid_card`
- **Values (with `:`)** - `:high`, `:low`, `:approved`
- **Fields (no `:`)** - `risk_level`, `amount`, `status`
- **Keywords (with `:`)** - `retry:`, `delay:`, `timeout:`

---

**End of Document**

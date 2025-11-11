# Workflow Syntax Design - Code-First Approach

**Status:** Final
**Last Updated:** 2025-11-11
**Style:** Compose-like (funciones componibles)
**Context:** Este documento define la sintaxis final del DSL de Cerebelum, inspirado en Jetpack Compose de Kotlin.

---

## Tabla de Contenidos

1. [Filosofía de Diseño](#filosofía-de-diseño)
2. [Sintaxis Core](#sintaxis-core)
3. [Timeline](#timeline)
4. [Error Handling](#error-handling)
5. [Branching](#branching)
6. [Parallel Execution](#parallel-execution)
7. [Agent Communication](#agent-communication)
8. [External Signals](#external-signals)
9. [Subworkflows](#subworkflows)
10. [Ejemplos Completos](#ejemplos-completos)
11. [Sintaxis Reference](#sintaxis-reference)

---

## Filosofía de Diseño

### Principio Fundamental

**Todas las palabras clave son funciones componibles** - inspirado en Jetpack Compose de Kotlin.

```elixir
workflow() do           # Función componible
  timeline() do         # Función componible
    start()            # Función
    |> step1()         # Función
    |> done()          # Función
  end
end
```

### Objetivos

1. **Compose-like**: Todo son funciones que se componen
2. **Idiomático Elixir**: Usa `do...end`, pattern matching, pipes
3. **Explícito**: `start()` y `done()` visibles
4. **Type-safe**: Validación en compile-time via macros
5. **Escalable**: Built on BEAM/OTP

### Anti-Objetivos

- ❌ No crear un lenguaje nuevo (nos quedamos en Elixir)
- ❌ No usar `{}` para bloques (son tuplas en Elixir)
- ❌ No keywords como `fun` (no existe en Elixir)

---

## Sintaxis Core

### Ejemplo Rápido

```elixir
defmodule PaymentWorkflow do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> validate_payment()
      |> process_payment()
      |> send_receipt()
      |> done()
    end

    diverge(validate_payment) do
      :timeout -> retry(3, delay: 2000) |> validate_payment()
      :invalid_card -> notify_customer() |> failed()
    end

    branch(process_payment) do
      amount > 10_000 -> request_approval()
      amount <= 10_000 -> charge_payment()
    end
  end

  def validate_payment(ctx) do
    case PaymentAPI.validate(ctx.card) do
      {:ok, data} -> data
      {:error, :timeout} -> error(:timeout)
    end
  end
end
```

---

## Timeline

### Sintaxis

```elixir
timeline() do
  start()
  |> step1()
  |> step2()
  |> step3()
  |> done()
end
```

### Reglas

- **`start()` explícito** - Marca inicio del workflow
- **`done()` explícito** - Marca fin exitoso
- **Pipe operator `|>`** - Flujo visual de arriba hacia abajo
- **Steps son funciones** - Sin `:` en el nombre

### Ejemplos

```elixir
# Timeline simple
workflow() do
  timeline() do
    start()
    |> load_data()
    |> process_data()
    |> save_results()
    |> done()
  end
end

# Timeline complejo
workflow() do
  timeline() do
    start()
    |> validate_application()
    |> verify_documents()
    |> parallel_risk_analysis()
    |> consensus_decision()
    |> human_review()
    |> generate_report()
    |> notify_applicant()
    |> done()
  end
end
```

---

## Error Handling

### Sintaxis

```elixir
diverge(step_name) do
  :error_type -> action()
  :error_type -> retry(...) |> action()
  :error_type -> step1() |> step2() |> action()
end
```

### Retry Simple

```elixir
diverge(validate_payment) do
  # Retry con delay fijo
  :timeout -> retry(3, delay: 2000) |> validate_payment()

  # Retry sin delay
  :transient_error -> retry(5) |> validate_payment()

  # Sin retry - diferente destino
  :invalid_card -> notify_customer() |> failed()

  # Sin retry - termina
  :fraud_detected -> failed()
end
```

### Retry Complejo (Ktor-style)

```elixir
diverge(fetch_data) do
  # Linear backoff - 3s, 6s, 9s, 12s, 15s
  :api_timeout ->
    retry() do
      attempts 5
      delay fn attempt -> attempt * 3000 end
    end
    |> fetch_data()

  # Exponential backoff - 1s, 2s, 4s, 8s, 16s (max 30s)
  :rate_limited ->
    retry() do
      attempts 10
      delay fn attempt -> round(:math.pow(2, attempt) * 1000) end
      max_delay 30_000
      backoff :exponential
    end
    |> log_rate_limit()
    |> fetch_data()

  # Con jitter - evita thundering herd
  :service_busy ->
    retry() do
      attempts 5
      delay 5000
      jitter 0.2  # ±20% random
    end
    |> fetch_data()
end
```

### Retry con Steps Intermedios

```elixir
diverge(process_payment) do
  :gateway_error ->
    retry(3, delay: 5000)
    |> log_retry()
    |> notify_admin()
    |> process_payment()

  :insufficient_funds ->
    notify_customer()
    |> request_additional_payment()
    |> failed()
end
```

### Opciones de Retry

```elixir
retry(
  attempts,                          # Requerido: número de intentos
  delay: ms | fn,                    # Delay fijo o función
  backoff: :exponential | :linear,   # Estrategia de backoff
  max_delay: ms,                     # Delay máximo
  jitter: true | float               # Randomización ±%
)

# Ejemplos:
retry(3, delay: 2000)
retry(5, delay: fn attempt -> attempt * 3000 end)
retry(10, delay: 1000, backoff: :exponential, max_delay: 60_000)
```

---

## Branching

### Sintaxis

```elixir
branch(step_name) do
  condition1 -> destination1()
  condition2 -> destination2()
  condition3 -> destination3()
end
```

### Ejemplos

```elixir
# Branch simple
branch(check_amount) do
  amount > 10_000 -> request_approval()
  amount <= 10_000 -> auto_approve()
end

# Branch complejo
branch(consensus_decision) do
  risk_level == :critical -> cancelled()
  risk_level == :high and amount > 100_000 -> escalate_to_committee()
  risk_level == :high -> human_review()
  risk_level == :medium and credit_score > 700 -> auto_approve()
  risk_level == :medium -> human_review()
  risk_level == :low -> generate_report()
end

# Branch con steps intermedios
branch(verify_identity) do
  identity_verified and age >= 18 -> continue_application()
  identity_verified and age < 18 -> notify_guardian() |> request_approval()
  not identity_verified -> request_documents() |> verify_identity()
end
```

### Reglas de Naming en Branch

- **Campos sin `:`** - `risk_level`, `amount`, `status` (variables del step anterior)
- **Valores con `:`** - `:high`, `:low`, `:approved` (átomos)
- **Steps sin `:`** - `escalate_committee`, `human_review` (nombres de funciones)

---

## Parallel Execution

### Sintaxis

```elixir
def step_name(ctx, deps) do
  parallel() do
    agents [
      {Agent1, %{data: ...}},
      {Agent2, %{data: ...}},
      {Agent3, %{data: ...}}
    ]
    timeout ms
    on_failure :stop | :continue
    min_successes n
  end
end
```

### Ejemplo

```elixir
def parallel_risk_analysis(ctx, %{validate_application: data}) do
  parallel() do
    agents [
      {CreditScoreAgent, %{applicant_id: data.applicant.id}},
      {FinancialAnalysisAgent, %{documents: data.documents}},
      {FraudDetectionAgent, %{applicant: data.applicant}}
    ]
    timeout 120_000
    on_failure :continue
    min_successes 2
  end
end

def consolidate_results(ctx, %{parallel_risk_analysis: results}) do
  # results es una lista con el resultado de cada agente:
  # [
  #   %{agent: CreditScoreAgent, risk_score: 0.3},
  #   %{agent: FinancialAnalysisAgent, risk_score: 0.5},
  #   %{agent: FraudDetectionAgent, risk_score: 0.2}
  # ]

  scores = Enum.map(results, & &1.risk_score)
  avg_score = Enum.sum(scores) / length(scores)

  %{average_risk: avg_score, individual_scores: scores}
end
```

### Agentes

```elixir
defmodule CreditScoreAgent do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> fetch_credit_score()
      |> calculate_risk()
      |> done()
    end
  end

  def fetch_credit_score(ctx) do
    CreditBureau.fetch(ctx.applicant_id)
  end

  def calculate_risk(ctx, %{fetch_credit_score: credit_data}) do
    score = RiskModel.calculate(credit_data)

    # Esto es lo que retorna al parallel
    %{
      agent: CreditScoreAgent,
      risk_score: score
    }
  end
end
```

---

## Agent Communication

### Broadcast & Await

Comunicación 1-a-todos (broadcast).

```elixir
# Producer Agent
defmodule ResearchAgent do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> conduct_research()
      |> broadcast_findings()
      |> done()
    end
  end

  def conduct_research(ctx) do
    findings = ExternalAPI.research(ctx.topic)
    %{findings: findings}
  end

  def broadcast_findings(ctx, %{conduct_research: research}) do
    # Broadcast a TODOS los peers
    broadcast(:research_complete) do
      %{
        from: ResearchAgent,
        findings: research.findings,
        timestamp: DateTime.utc_now()
      }
    end

    %{agent: ResearchAgent, findings: research.findings}
  end
end

# Consumer Agent
defmodule WriterAgent do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> wait_for_research()
      |> write_content()
      |> done()
    end
  end

  def wait_for_research(ctx) do
    # Espera broadcast de ResearchAgent
    await(ResearchAgent, :research_complete) do
      timeout 60_000
      on_timeout -> %{findings: "no data"}
    end
  end

  def write_content(ctx, %{wait_for_research: research_data}) do
    content = ContentGenerator.write(research_data.findings)
    %{agent: WriterAgent, content: content}
  end
end
```

### Send To & Receive From

Comunicación 1-a-1 (dirigida).

```elixir
# Coordinator
defmodule CoordinatorAgent do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> assign_tasks()
      |> wait_for_results()
      |> done()
    end
  end

  def assign_tasks(ctx) do
    [task1, task2 | _] = ctx.tasks

    # Envía a WorkerAgent1 específicamente
    send_to(WorkerAgent1, :task_assigned) do
      %{
        task: task1,
        deadline: DateTime.add(DateTime.utc_now(), 60, :second)
      }
    end

    # Envía a WorkerAgent2 específicamente
    send_to(WorkerAgent2, :task_assigned) do
      %{task: task2}
    end

    %{assigned_count: 2}
  end

  def wait_for_results(ctx, %{assign_tasks: _assigned}) do
    result1 = receive_from(WorkerAgent1, :task_complete) do
      timeout 90_000
      on_timeout -> %{error: :timeout}
    end

    result2 = receive_from(WorkerAgent2, :task_complete) do
      timeout 90_000
    end

    %{worker1: result1, worker2: result2}
  end
end

# Worker
defmodule WorkerAgent1 do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> wait_for_task()
      |> execute_task()
      |> send_result_back()
      |> done()
    end
  end

  def wait_for_task(ctx) do
    receive_from(CoordinatorAgent, :task_assigned) do
      timeout 30_000
      on_timeout -> error(:no_task)
    end
  end

  def execute_task(ctx, %{wait_for_task: task_data}) do
    result = TaskProcessor.process(task_data.task)
    %{result: result}
  end

  def send_result_back(ctx, %{execute_task: execution}) do
    send_to(CoordinatorAgent, :task_complete) do
      %{result: execution.result, completed_at: DateTime.utc_now()}
    end

    %{completed: true}
  end
end
```

### Helpers de Comunicación

```elixir
# Broadcast a todos
broadcast(:message_type) do
  %{data: ...}
end

# Await broadcast
await(AgentModule, :message_type) do
  timeout ms
  on_timeout -> default_value
  on_receive fn data -> transform(data) end
end

# Send a específico
send_to(AgentModule, :message_type) do
  %{data: ...}
end

# Receive de específico
receive_from(AgentModule, :message_type) do
  timeout ms
  on_timeout -> default_value
end
```

---

## External Signals

### Sintaxis

```elixir
def step_name(ctx, deps) do
  receive_signal() do
    {:signal_type, data} -> result
    {:other_signal, data} -> other_result
  after timeout ->
    {:timeout, %{}}
  end
end
```

### Ejemplo: Human Approval

```elixir
workflow() do
  timeline() do
    start()
    |> submit_request()
    |> wait_for_approval()
    |> process_approved()
    |> done()
  end

  diverge(wait_for_approval) do
    :approval_rejected -> notify_applicant() |> failed()
    :approval_timeout -> escalate_to_manager()
    :request_cancelled -> cancelled()
  end
end

def submit_request(ctx) do
  ApprovalSystem.notify(ctx.approver_email, ctx.request)
  %{submitted_at: DateTime.utc_now()}
end

def wait_for_approval(ctx, %{submit_request: submission}) do
  receive_signal() do
    {:approval_decision, %{approved: true, approver: approver}} ->
      %{
        approved: true,
        approver: approver,
        approved_at: DateTime.utc_now()
      }

    {:approval_decision, %{approved: false, reason: reason}} ->
      error(:approval_rejected)

    {:cancel_request, _data} ->
      error(:request_cancelled)

  after 3_600_000 ->  # 1 hora
    error(:approval_timeout)
  end
end

def process_approved(ctx, %{wait_for_approval: approval}) do
  %{status: :approved, approver: approval.approver}
end
```

### Enviar Señales desde Fuera

```elixir
# Desde código Elixir
Cerebelum.send_signal(
  "exec-uuid-123",           # execution_id
  :approval_decision,        # signal name
  %{approved: true, approver: "john@example.com"}
)

# Desde HTTP API
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

### Sintaxis

```elixir
def step_name(ctx, deps) do
  subworkflow(SubWorkflowModule) do
    %{data: ...}
  end
end
```

### Ejemplo

```elixir
# Main Workflow
workflow() do
  timeline() do
    start()
    |> validate_application()
    |> verify_documents()
    |> process_application()
    |> done()
  end
end

def verify_documents(ctx, %{validate_application: data}) do
  subworkflow(DocumentVerification) do
    %{
      documents: data.documents,
      required_types: [:id, :proof_of_income]
    }
  end
end

# Subworkflow
defmodule DocumentVerification do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> extract_data()
      |> validate_format()
      |> verify_authenticity()
      |> done()
    end
  end

  def extract_data(ctx) do
    Enum.map(ctx.documents, &OCR.extract/1)
  end

  def validate_format(ctx, %{extract_data: extracted}) do
    %{all_valid: Enum.all?(extracted, &valid_format?/1)}
  end

  def verify_authenticity(ctx, %{validate_format: validated}) do
    %{authenticated: Enum.all?(validated, &authentic?/1)}
  end
end
```

---

## Ejemplos Completos

### Ejemplo 1: Payment Processing

```elixir
defmodule PaymentWorkflow do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> validate_payment()
      |> check_fraud()
      |> process_payment()
      |> send_receipt()
      |> done()
    end

    diverge(validate_payment) do
      :timeout -> retry(3, delay: 2000) |> validate_payment()
      :invalid_card -> notify_customer() |> failed()
    end

    diverge(process_payment) do
      :insufficient_funds -> notify_customer() |> failed()
      :gateway_error ->
        retry() do
          attempts 5
          delay fn attempt -> attempt * 2000 end
          max_delay 30_000
        end
        |> process_payment()
    end

    branch(check_fraud) do
      fraud_score > 0.8 -> cancel_payment() |> failed()
      fraud_score > 0.5 -> request_verification()
      fraud_score <= 0.5 -> process_payment()
    end
  end

  def validate_payment(ctx) do
    case PaymentAPI.validate(ctx.card) do
      {:ok, validated} -> validated
      {:error, :timeout} -> error(:timeout)
      {:error, :invalid} -> error(:invalid_card)
    end
  end

  def check_fraud(ctx, %{validate_payment: payment}) do
    score = FraudDetector.score(payment)
    %{fraud_score: score, validated_payment: payment}
  end

  def process_payment(ctx, %{check_fraud: check}) do
    case PaymentGateway.charge(check.validated_payment) do
      {:ok, transaction} -> transaction
      {:error, :insufficient_funds} -> error(:insufficient_funds)
      {:error, :gateway_error} -> error(:gateway_error)
    end
  end

  def send_receipt(ctx, %{process_payment: transaction}) do
    Email.send_receipt(ctx.customer_email, transaction)
    %{receipt_sent: true}
  end

  def notify_customer(ctx, _deps) do
    Email.send(ctx.customer_email, "Payment failed")
    %{notified: true}
  end
end
```

### Ejemplo 2: Multi-Agent Loan Application

```elixir
defmodule LoanApplication do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> validate_application()
      |> verify_documents()
      |> parallel_risk_analysis()
      |> consensus_decision()
      |> human_review()
      |> generate_report()
      |> done()
    end

    diverge(validate_application) do
      :api_timeout ->
        retry() do
          attempts 5
          delay fn attempt -> attempt * 3000 end
          max_delay 30_000
        end
        |> log_retry()
        |> validate_application()

      :invalid_data -> notify_applicant() |> failed()
    end

    branch(consensus_decision) do
      risk_level == :critical -> cancelled()
      risk_level == :high and amount > 100_000 -> escalate_to_committee()
      risk_level == :high -> human_review()
      risk_level == :low -> generate_report()
    end
  end

  def validate_application(ctx) do
    case ApplicationAPI.validate(ctx.application_id) do
      {:ok, data} -> data
      {:error, :timeout} -> error(:api_timeout)
      {:error, :invalid} -> error(:invalid_data)
    end
  end

  def verify_documents(ctx, %{validate_application: data}) do
    subworkflow(DocumentVerification) do
      %{
        documents: data.documents,
        required_types: [:id, :proof_of_income]
      }
    end
  end

  def parallel_risk_analysis(ctx, deps) do
    parallel() do
      agents [
        {CreditScoreAgent, %{applicant_id: deps.validate_application.applicant.id}},
        {FinancialAnalysisAgent, %{documents: deps.verify_documents}},
        {FraudDetectionAgent, %{applicant: deps.validate_application.applicant}}
      ]
      timeout 120_000
      on_failure :continue
      min_successes 2
    end
  end

  def consensus_decision(ctx, %{parallel_risk_analysis: results}) do
    scores = Enum.map(results, & &1.risk_score)
    avg_score = Enum.sum(scores) / length(scores)

    %{
      risk_level: calculate_risk_level(avg_score),
      amount: ctx.loan_amount,
      scores: results
    }
  end

  def human_review(ctx, %{consensus_decision: decision}) do
    ReviewSystem.notify_reviewer(ctx.execution_id, decision)

    receive_signal() do
      {:review_complete, %{approved: true, reviewer: reviewer}} ->
        %{approved: true, reviewer: reviewer, reviewed_at: DateTime.utc_now()}

      {:review_complete, %{approved: false, reason: reason}} ->
        error(:review_rejected)

    after 7_200_000 ->  # 2 horas
      error(:review_timeout)
    end
  end

  def generate_report(ctx, deps) do
    Report.generate(%{
      application_id: ctx.application_id,
      decision: deps.consensus_decision,
      review: deps[:human_review],
      timestamp: DateTime.utc_now()
    })
  end
end
```

---

## Sintaxis Reference

### Estructura Principal

```elixir
workflow() do
  timeline() do...end
  diverge(step) do...end
  branch(step) do...end
end
```

### Timeline

```elixir
timeline() do
  start()
  |> step1()
  |> step2()
  |> done()
end
```

### Diverge (Error Handling)

```elixir
# Simple
diverge(step) do
  :error_type -> retry(N, delay: MS) |> step()
  :error_type -> step1() |> step2() |> failed()
end

# Complejo
diverge(step) do
  :error_type ->
    retry() do
      attempts N
      delay fn attempt -> MS end
      max_delay MS
      backoff :exponential
      jitter 0.2
    end
    |> step()
end
```

### Branch (Condicional)

```elixir
branch(step) do
  condition1 -> destination1()
  condition2 -> destination2()
end
```

### Funciones de Steps

```elixir
def step_name(ctx) do
  result  # Auto-wrapped en {:ok, result}
end

def step_name(ctx, deps) do
  result
end
```

### Parallel

```elixir
parallel() do
  agents [
    {Agent1, %{...}},
    {Agent2, %{...}}
  ]
  timeout MS
  on_failure :stop | :continue
  min_successes N
end
```

### Comunicación

```elixir
broadcast(:message_type) do
  %{data: ...}
end

await(AgentModule, :message_type) do
  timeout MS
  on_timeout -> default
end

send_to(AgentModule, :message_type) do
  %{data: ...}
end

receive_from(AgentModule, :message_type) do
  timeout MS
end
```

### Signals

```elixir
receive_signal() do
  {:signal_type, data} -> result
after timeout -> default
end
```

### Subworkflows

```elixir
subworkflow(ModuleName) do
  %{data: ...}
end
```

### Helpers

```elixir
start()           # Inicio del timeline
done()            # Fin exitoso
failed()          # Fin con fallo
cancelled()       # Fin cancelado
error(:type)      # Emitir error (activa diverge)
timeout(data)     # Emitir timeout
```

### Reglas de Naming

- **Steps (sin `:`)** - `validate_payment`, `CreditScoreAgent`
- **Error types (con `:`)** - `:timeout`, `:invalid_card`
- **Valores (con `:`)** - `:high`, `:low`, `:approved`
- **Campos (sin `:`)** - `risk_level`, `amount`, `status`
- **Keywords (con `:`)** - `timeout:`, `delay:`, `attempts:`

---

**Ver también:**
- [Final Syntax Examples](final-syntax.md) - Todos los casos de uso completos
- [Subworkflows Design](subworkflows-design.md) - Arquitectura de subworkflows
- [Execution Engine](execution-engine-state-machine.md) - Cómo funciona el engine

---

**End of Document**

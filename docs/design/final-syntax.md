# Cerebelum Workflow Syntax - Final

**Status:** Final
**Last Updated:** 2025-11-11
**Style:** Compose-like (funciones componibles)

---

## Filosofía de Diseño

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

---

## Palabras Clave (Funciones Componibles)

### Estructura
- `workflow() do...end` - Container principal
- `timeline() do...end` - Secuencia de pasos
- `diverge(step) do...end` - Manejo de errores
- `branch(step) do...end` - Ramificación condicional

### Retry
- `retry() do...end` - Configuración de retry (estilo Ktor)
- `retry(attempts, opts)` - Retry simple inline

### Ejecución
- `parallel() do...end` - Ejecución paralela de agentes
- `subworkflow(Module) do...end` - Ejecutar subworkflow

### Comunicación
- `broadcast(:type) do...end` - Broadcast a todos los peers
- `await(Agent, :type) do...end` - Esperar broadcast
- `send_to(Agent, :type) do...end` - Enviar a agente específico
- `receive_from(Agent, :type) do...end` - Recibir de agente específico
- `receive_signal() do...end` - Recibir señal externa

### Helpers
- `start()` - Inicio del timeline
- `done()` - Fin exitoso
- `failed()` - Fin con fallo
- `cancelled()` - Fin cancelado
- `error(:type)` - Emitir error (activa diverge)

---

## Caso 1: Timeline Simple

```elixir
defmodule OrderProcessing do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> validate_order()
      |> calculate_total()
      |> charge_payment()
      |> send_confirmation()
      |> done()
    end
  end

  def validate_order(ctx) do
    %{
      items: ctx.items,
      customer: ctx.customer,
      valid: true
    }
  end

  def calculate_total(ctx, %{validate_order: order}) do
    total = Enum.sum(Enum.map(order.items, & &1.price))
    %{total: total, order: order}
  end

  def charge_payment(ctx, %{calculate_total: calc}) do
    PaymentGateway.charge(ctx.card, calc.total)
  end

  def send_confirmation(ctx, %{charge_payment: payment}) do
    Email.send(ctx.customer.email, payment)
    %{sent: true}
  end
end
```

---

## Caso 2: Error Handling con Retry Simple

```elixir
defmodule PaymentProcessing do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> validate_card()
      |> charge_payment()
      |> done()
    end

    diverge(validate_card) do
      :timeout -> retry(3, delay: 2000) |> validate_card()
      :invalid_card -> notify_customer() |> failed()
      :fraud_detected -> failed()
    end

    diverge(charge_payment) do
      :gateway_error -> retry(5, delay: 5000) |> charge_payment()
      :insufficient_funds -> notify_customer() |> failed()
    end
  end

  def validate_card(ctx) do
    case CardValidator.validate(ctx.card_number) do
      {:ok, card} -> card
      {:error, :timeout} -> error(:timeout)
      {:error, :invalid} -> error(:invalid_card)
      {:error, :fraud} -> error(:fraud_detected)
    end
  end

  def charge_payment(ctx, %{validate_card: card}) do
    case PaymentGateway.charge(card, ctx.amount) do
      {:ok, transaction} -> transaction
      {:error, :gateway_error} -> error(:gateway_error)
      {:error, :insufficient_funds} -> error(:insufficient_funds)
    end
  end

  def notify_customer(ctx, _deps) do
    Email.send(ctx.customer_email, "Payment failed")
    %{notified: true}
  end
end
```

---

## Caso 3: Retry con Bloque Complejo (Ktor-style)

```elixir
defmodule DataFetcher do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> fetch_from_api()
      |> process_data()
      |> save_results()
      |> done()
    end

    diverge(fetch_from_api) do
      # Linear backoff - 3s, 6s, 9s, 12s, 15s
      :api_timeout ->
        retry() do
          attempts 5
          delay fn attempt -> attempt * 3000 end
        end
        |> fetch_from_api()

      # Exponential backoff - 1s, 2s, 4s, 8s, 16s (max 30s)
      :rate_limited ->
        retry() do
          attempts 10
          delay fn attempt -> round(:math.pow(2, attempt) * 1000) end
          max_delay 30_000
          backoff :exponential
        end
        |> log_rate_limit()
        |> fetch_from_api()

      # Con jitter - evita thundering herd
      :service_busy ->
        retry() do
          attempts 5
          delay 5000
          jitter 0.2  # ±20%
        end
        |> fetch_from_api()

      :not_found -> failed()
    end
  end

  def fetch_from_api(ctx) do
    case ExternalAPI.fetch(ctx.resource_id) do
      {:ok, data} -> data
      {:error, :timeout} -> error(:api_timeout)
      {:error, :rate_limit} -> error(:rate_limited)
      {:error, :busy} -> error(:service_busy)
      {:error, :not_found} -> error(:not_found)
    end
  end

  def log_rate_limit(ctx, _deps) do
    Logger.warning("Rate limited, retrying with backoff")
    %{logged: true}
  end

  def process_data(ctx, %{fetch_from_api: data}) do
    Processor.transform(data)
  end

  def save_results(ctx, %{process_data: processed}) do
    DB.save(processed)
  end
end
```

---

## Caso 4: Branch Condicional

```elixir
defmodule LoanApproval do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> validate_application()
      |> calculate_risk_score()
      |> decide_approval()
      |> done()
    end

    branch(calculate_risk_score) do
      risk_score > 0.8 -> reject_application()
      risk_score > 0.5 and amount > 100_000 -> escalate_to_manager()
      risk_score > 0.5 -> request_additional_documents()
      risk_score <= 0.5 and amount < 50_000 -> auto_approve()
      risk_score <= 0.5 -> standard_approval()
    end
  end

  def validate_application(ctx) do
    %{
      applicant: ctx.applicant,
      amount: ctx.loan_amount,
      documents: ctx.documents
    }
  end

  def calculate_risk_score(ctx, %{validate_application: app}) do
    score = RiskEngine.calculate(app.applicant, app.amount)
    %{
      risk_score: score,
      amount: app.amount,
      applicant: app.applicant
    }
  end

  def reject_application(ctx, %{calculate_risk_score: risk}) do
    Notification.send(ctx.email, "Application rejected")
    %{status: :rejected, reason: "High risk score"}
  end

  def escalate_to_manager(ctx, %{calculate_risk_score: risk}) do
    ManagerQueue.add(ctx.application_id, risk)
    %{status: :escalated}
  end

  def auto_approve(ctx, %{calculate_risk_score: risk}) do
    %{status: :approved, risk_score: risk.risk_score}
  end

  def decide_approval(ctx, deps) do
    deps
  end
end
```

---

## Caso 5: Parallel Execution

```elixir
defmodule RiskAnalysis do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> validate_application()
      |> parallel_risk_analysis()
      |> consolidate_results()
      |> generate_report()
      |> done()
    end
  end

  def validate_application(ctx) do
    %{
      applicant_id: ctx.applicant_id,
      loan_amount: ctx.amount
    }
  end

  def parallel_risk_analysis(ctx, %{validate_application: data}) do
    # Ejecuta 3 agentes en paralelo
    parallel() do
      agents [
        {CreditScoreAgent, %{applicant_id: data.applicant_id}},
        {FinancialAnalysisAgent, %{amount: data.loan_amount}},
        {FraudDetectionAgent, %{applicant_id: data.applicant_id}}
      ]
      timeout 120_000
      on_failure :continue
      min_successes 2
    end
  end

  def consolidate_results(ctx, %{parallel_risk_analysis: results}) do
    # results es una lista con los resultados de cada agente:
    # [
    #   %{agent: CreditScoreAgent, risk_score: 0.3},
    #   %{agent: FinancialAnalysisAgent, risk_score: 0.5},
    #   %{agent: FraudDetectionAgent, risk_score: 0.2}
    # ]

    scores = Enum.map(results, & &1.risk_score)
    avg_score = Enum.sum(scores) / length(scores)

    %{
      average_risk: avg_score,
      individual_scores: scores
    }
  end

  def generate_report(ctx, %{consolidate_results: consolidated}) do
    Report.create(%{
      average_risk: consolidated.average_risk,
      timestamp: DateTime.utc_now()
    })
  end
end

# ========================================
# Agentes
# ========================================
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

    # Esto es lo que se retorna al parallel
    %{
      agent: CreditScoreAgent,
      risk_score: score
    }
  end
end

defmodule FinancialAnalysisAgent do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> analyze_finances()
      |> done()
    end
  end

  def analyze_finances(ctx) do
    score = FinancialRiskModel.calculate(ctx.amount)

    %{
      agent: FinancialAnalysisAgent,
      risk_score: score
    }
  end
end

defmodule FraudDetectionAgent do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> detect_fraud()
      |> done()
    end
  end

  def detect_fraud(ctx) do
    score = FraudDetector.check(ctx.applicant_id)

    %{
      agent: FraudDetectionAgent,
      risk_score: score
    }
  end
end
```

---

## Caso 6: Agent Communication (Broadcast & Await)

```elixir
defmodule CollaborativeAnalysis do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> prepare_data()
      |> parallel_agents()
      |> consolidate()
      |> done()
    end
  end

  def prepare_data(ctx) do
    %{topic: ctx.topic}
  end

  def parallel_agents(ctx, %{prepare_data: data}) do
    parallel() do
      agents [
        {ResearchAgent, %{topic: data.topic}},
        {WriterAgent, %{topic: data.topic}},
        {ReviewerAgent, %{topic: data.topic}}
      ]
      timeout 300_000
    end
  end

  def consolidate(ctx, %{parallel_agents: results}) do
    %{
      research: Enum.find(results, & &1.agent == ResearchAgent),
      content: Enum.find(results, & &1.agent == WriterAgent),
      review: Enum.find(results, & &1.agent == ReviewerAgent)
    }
  end
end

# ========================================
# Agente 1: Research (Producer)
# ========================================
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
    %{findings: findings, topic: ctx.topic}
  end

  def broadcast_findings(ctx, %{conduct_research: research}) do
    # Broadcast a TODOS los peers
    broadcast(:research_complete) do
      %{
        from: ResearchAgent,
        findings: research.findings,
        topic: research.topic,
        timestamp: DateTime.utc_now()
      }
    end

    %{agent: ResearchAgent, findings: research.findings}
  end
end

# ========================================
# Agente 2: Writer (Consumer)
# ========================================
defmodule WriterAgent do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> wait_for_research()
      |> write_content()
      |> broadcast_draft()
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
    %{content: content}
  end

  def broadcast_draft(ctx, %{write_content: draft}) do
    broadcast(:draft_ready) do
      %{
        from: WriterAgent,
        content: draft.content,
        timestamp: DateTime.utc_now()
      }
    end

    %{agent: WriterAgent, content: draft.content}
  end
end

# ========================================
# Agente 3: Reviewer (Consumer)
# ========================================
defmodule ReviewerAgent do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> wait_for_draft()
      |> review_content()
      |> done()
    end
  end

  def wait_for_draft(ctx) do
    # Espera broadcast de WriterAgent
    await(WriterAgent, :draft_ready) do
      timeout 120_000
      on_timeout -> error(:no_draft)
    end
  end

  def review_content(ctx, %{wait_for_draft: draft_data}) do
    feedback = Reviewer.analyze(draft_data.content)

    %{
      agent: ReviewerAgent,
      approved: feedback.score > 0.8,
      feedback: feedback
    }
  end
end
```

**Flujo de mensajes:**
```
t0: ResearchAgent → broadcast(:research_complete)
    └─> WriterAgent recibe

t1: WriterAgent → write_content()

t2: WriterAgent → broadcast(:draft_ready)
    └─> ReviewerAgent recibe

t3: ReviewerAgent → review_content()
```

---

## Caso 7: Send/Receive Dirigido

```elixir
defmodule TaskCoordination do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> setup_tasks()
      |> parallel_coordination()
      |> verify_completion()
      |> done()
    end
  end

  def setup_tasks(ctx) do
    %{tasks: ctx.tasks}
  end

  def parallel_coordination(ctx, %{setup_tasks: data}) do
    parallel() do
      agents [
        {CoordinatorAgent, %{tasks: data.tasks}},
        {WorkerAgent1, %{worker_id: 1}},
        {WorkerAgent2, %{worker_id: 2}}
      ]
      timeout 180_000
    end
  end

  def verify_completion(ctx, %{parallel_coordination: results}) do
    %{all_completed: Enum.all?(results, & &1.completed)}
  end
end

# ========================================
# Coordinator (Asigna tareas 1-a-1)
# ========================================
defmodule CoordinatorAgent do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> assign_tasks()
      |> wait_for_results()
      |> verify_all_done()
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
      %{
        task: task2,
        deadline: DateTime.add(DateTime.utc_now(), 60, :second)
      }
    end

    %{assigned_count: 2}
  end

  def wait_for_results(ctx, %{assign_tasks: _assigned}) do
    # Recibe de WorkerAgent1
    result1 = receive_from(WorkerAgent1, :task_complete) do
      timeout 90_000
      on_timeout -> %{error: :timeout}
    end

    # Recibe de WorkerAgent2
    result2 = receive_from(WorkerAgent2, :task_complete) do
      timeout 90_000
      on_timeout -> %{error: :timeout}
    end

    %{
      worker1_result: result1,
      worker2_result: result2
    }
  end

  def verify_all_done(ctx, %{wait_for_results: results}) do
    %{
      completed: true,
      results: [results.worker1_result, results.worker2_result]
    }
  end
end

# ========================================
# Worker 1
# ========================================
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

    %{
      task: task_data.task,
      result: result,
      worker_id: ctx.worker_id
    }
  end

  def send_result_back(ctx, %{execute_task: execution}) do
    send_to(CoordinatorAgent, :task_complete) do
      %{
        worker_id: execution.worker_id,
        result: execution.result,
        completed_at: DateTime.utc_now()
      }
    end

    %{completed: true}
  end
end

defmodule WorkerAgent2 do
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
    end
  end

  def execute_task(ctx, %{wait_for_task: task_data}) do
    result = TaskProcessor.process(task_data.task)
    %{result: result, worker_id: ctx.worker_id}
  end

  def send_result_back(ctx, %{execute_task: execution}) do
    send_to(CoordinatorAgent, :task_complete) do
      %{
        worker_id: execution.worker_id,
        result: execution.result
      }
    end

    %{completed: true}
  end
end
```

**Flujo de mensajes dirigidos:**
```
t0: CoordinatorAgent → send_to(WorkerAgent1, :task_assigned)
t1: CoordinatorAgent → send_to(WorkerAgent2, :task_assigned)

t2: WorkerAgent1 → receive_from(CoordinatorAgent) ✓
t3: WorkerAgent2 → receive_from(CoordinatorAgent) ✓

t4: WorkerAgent1 → execute_task()
t5: WorkerAgent2 → execute_task()

t6: WorkerAgent1 → send_to(CoordinatorAgent, :task_complete)
t7: WorkerAgent2 → send_to(CoordinatorAgent, :task_complete)

t8: CoordinatorAgent → receive_from(WorkerAgent1) ✓
t9: CoordinatorAgent → receive_from(WorkerAgent2) ✓
```

---

## Caso 8: External Signals

```elixir
defmodule ApprovalWorkflow do
  use Cerebelum.Workflow

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
    %{
      status: :approved,
      approver: approval.approver
    }
  end
end

# Enviar señal desde sistema externo:
# Cerebelum.send_signal("exec-123", :approval_decision, %{approved: true, approver: "john@example.com"})
```

---

## Caso 9: Subworkflows

```elixir
defmodule MainWorkflow do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start()
      |> validate_application()
      |> verify_documents()
      |> process_application()
      |> done()
    end
  end

  def validate_application(ctx) do
    %{
      applicant: ctx.applicant,
      documents: ctx.documents
    }
  end

  def verify_documents(ctx, %{validate_application: data}) do
    # Ejecuta subworkflow
    subworkflow(DocumentVerification) do
      %{
        documents: data.documents,
        required_types: [:id, :proof_of_income]
      }
    end
  end

  def process_application(ctx, %{verify_documents: verified}) do
    %{processed: true, verified: verified}
  end
end

# ========================================
# Subworkflow
# ========================================
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
    Enum.all?(extracted, &valid_format?/1)
  end

  def verify_authenticity(ctx, %{validate_format: validated}) do
    %{all_valid: Enum.all?(validated, &authentic?/1)}
  end
end
```

---

## Sintaxis Reference

### Estructura
```elixir
workflow() do...end
timeline() do...end
diverge(step) do...end
branch(step) do...end
```

### Retry
```elixir
# Simple
retry(3, delay: 2000) |> step()

# Complejo
retry() do
  attempts N
  delay fn attempt -> MS end
  max_delay MS
  backoff :exponential
  jitter 0.2
end
```

### Parallel
```elixir
parallel() do
  agents [(Agent1, %{}), (Agent2, %{})]
  timeout MS
  on_failure :stop | :continue
  min_successes N
end
```

### Comunicación
```elixir
broadcast(:type) do
  %{data: ...}
end

await(Agent, :type) do
  timeout MS
  on_timeout -> default
  on_receive fn data -> transform(data) end
end

send_to(Agent, :type) do
  %{data: ...}
end

receive_from(Agent, :type) do
  timeout MS
  on_timeout -> default
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
subworkflow(Module) do
  %{data: ...}
end
```

---

## Reglas de Naming

- **Steps (sin `:`)** - `validate_payment`, `CreditScoreAgent`
- **Error types (con `:`)** - `:timeout`, `:invalid_card`
- **Values (con `:`)** - `:high`, `:low`, `:approved`
- **Fields (sin `:`)** - `risk_level`, `amount`, `status`
- **Keywords (con `:`)** - `timeout:`, `delay:`, `attempts:`

---

**End of Document**

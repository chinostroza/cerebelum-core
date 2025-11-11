# Complete Example: Financial Risk Assessment System

**Scenario:** Multi-agent system that analyzes loan applications using:
- Parallel agents that communicate
- Subworkflows for specialized tasks
- Error handling with retries
- Conditional branching
- LLM integration (Cortex)

---

## Architecture

```
LoanApplication Workflow (Main)
├─ validate_application (step)
├─ parallel_risk_analysis (parallel + communication)
│  ├─ CreditScoreAgent
│  ├─ FinancialAnalysisAgent (uses subworkflow)
│  └─ FraudDetectionAgent (uses subworkflow)
├─ consensus_decision (waits for agent messages)
├─ final_review (conditional branch)
└─ generate_report

Subworkflows:
- DocumentVerification (used by FinancialAnalysisAgent)
- FraudCheck (used by FraudDetectionAgent)
```

---

## Implementation with Improved DSL

### Main Workflow

```elixir
defmodule LoanApplication do
  use Cerebelum.Workflow

  @doc """
  Main loan application workflow with parallel risk assessment.

  Features demonstrated:
  - Parallel agents with communication
  - Subworkflows
  - Error handling with retries
  - Conditional branching
  - LLM integration
  """

  # Timeline - main flow
  flow :start,
       :validate_application,
       :parallel_risk_analysis,
       :consensus_decision,
       :final_review,
       :generate_report,
       :done

  # Error handling for external API calls
  on_error :validate_application do
    :api_timeout, retry: 3, delay: 2000 -> :validate_application
    :invalid_data -> cancel("Invalid application data") |> :failed
  end

  on_error :parallel_risk_analysis do
    :agent_timeout -> use_partial_results() |> :consensus_decision
    :all_agents_failed -> :failed
  end

  # Branching based on risk level
  when_match :consensus_decision do
    risk_level == :high and amount > 100_000 ->
      escalate_to_committee() |> :generate_report

    risk_level == :high ->
      manual_review() |> :final_review

    risk_level == :medium ->
      automated_review() |> :final_review

    # Low risk - skip review
    risk_level == :low ->
      :generate_report
  end

  when_match :final_review do
    approved? -> :generate_report
    needs_more_info? -> request_documents() |> :validate_application
    else -> :failed
  end

  # ============================================================================
  # Steps
  # ============================================================================

  step validate_application(ctx) do
    # Fetch application data
    application = Repo.get!(Application, ctx.application_id)

    # Validate required fields
    case validate_required_fields(application) do
      :ok ->
        ok(%{
          application: application,
          applicant: application.applicant,
          loan_amount: application.amount,
          loan_type: application.type
        })

      {:error, reason} ->
        error(reason)
    end
  end

  step parallel_risk_analysis(%{validate_application: data}) do
    # Run 3 agents in parallel - they will communicate via messages
    parallel [
      {CreditScoreAgent, %{
        applicant_id: data.applicant.id,
        loan_amount: data.loan_amount
      }},
      {FinancialAnalysisAgent, %{
        applicant_id: data.applicant.id,
        documents: data.application.documents
      }},
      {FraudDetectionAgent, %{
        applicant: data.applicant,
        application: data.application
      }}
    ],
      timeout: 120_000,
      on_failure: :continue,
      min_successes: 2
  end

  step consensus_decision(%{parallel_risk_analysis: agents}) do
    # Extract results from each agent
    credit_result = agents[CreditScoreAgent]
    financial_result = agents[FinancialAnalysisAgent]
    fraud_result = agents[FraudDetectionAgent]

    # Calculate consensus risk level
    risk_scores = [
      credit_result.risk_score,
      financial_result.risk_score,
      fraud_result.risk_score
    ]

    average_risk = Enum.sum(risk_scores) / length(risk_scores)

    risk_level = cond do
      average_risk >= 0.7 -> :high
      average_risk >= 0.4 -> :medium
      true -> :low
    end

    ok(%{
      risk_level: risk_level,
      risk_score: average_risk,
      details: %{
        credit: credit_result,
        financial: financial_result,
        fraud: fraud_result
      }
    })
  end

  step final_review(ctx, %{consensus_decision: decision}) do
    # Use LLM (Cortex) for final review
    prompt = """
    Review this loan application:

    Applicant: #{ctx.applicant_name}
    Loan Amount: $#{ctx.loan_amount}
    Risk Level: #{decision.risk_level}
    Risk Score: #{decision.risk_score}

    Credit Score: #{decision.details.credit.score}
    Financial Status: #{decision.details.financial.status}
    Fraud Risk: #{decision.details.fraud.risk}

    Should this loan be approved? Provide reasoning.
    """

    case Cortex.chat([
      %{role: "system", content: "You are a loan officer reviewing applications."},
      %{role: "user", content: prompt}
    ], model: "gpt-4") do
      {:ok, response} ->
        decision = extract_decision(response.content)
        ok(%{
          approved: decision.approved,
          reasoning: decision.reasoning,
          conditions: decision.conditions
        })

      {:error, reason} ->
        error(reason)
    end
  end

  step generate_report(%{consensus_decision: decision, final_review: review}) do
    report = %Report{
      application_id: context.application_id,
      risk_level: decision.risk_level,
      risk_score: decision.risk_score,
      approved: review.approved,
      reasoning: review.reasoning,
      conditions: review.conditions,
      generated_at: DateTime.utc_now()
    }

    Repo.insert!(report)
    ok(report)
  end

  # Helper functions
  defp validate_required_fields(app) do
    required = [:applicant_name, :amount, :type, :income]
    missing = Enum.filter(required, fn field -> is_nil(Map.get(app, field)) end)

    if Enum.empty?(missing), do: :ok, else: {:error, {:missing_fields, missing}}
  end

  defp extract_decision(llm_response) do
    # Parse LLM response to extract approval decision
    # Implementation details...
  end
end
```

---

## Agent 1: Credit Score Agent (Simple)

```elixir
defmodule CreditScoreAgent do
  use Cerebelum.Workflow

  @doc """
  Analyzes credit score and broadcasts to other agents.
  Listens for flags from FraudDetectionAgent.
  """

  flow :start,
       :fetch_credit_score,
       :analyze_credit,
       :broadcast_results,
       :listen_for_flags,
       :finalize,
       :done

  step fetch_credit_score(ctx) do
    # Call external credit bureau API
    case CreditBureau.get_score(ctx.applicant_id) do
      {:ok, score} ->
        ok(%{
          score: score,
          history: score.payment_history,
          utilization: score.credit_utilization
        })

      {:error, :not_found} ->
        ok(%{score: nil, history: [], utilization: 0})
    end
  end

  step analyze_credit(%{fetch_credit_score: credit}) do
    risk_score = calculate_credit_risk(credit)

    analysis = %{
      score: credit.score,
      risk_score: risk_score,
      factors: analyze_risk_factors(credit),
      recommendation: get_recommendation(risk_score)
    }

    ok(analysis)
  end

  step broadcast_results(%{analyze_credit: analysis}) do
    # Broadcast to other agents in parallel group
    broadcast :credit_analysis_complete, %{
      agent: CreditScoreAgent,
      risk_score: analysis.risk_score,
      score: analysis.score,
      recommendation: analysis.recommendation
    }

    ok(analysis)
  end

  step listen_for_flags(%{analyze_credit: analysis}) do
    # Wait for fraud agent (optional - timeout is OK)
    case await FraudDetectionAgent, :fraud_alert, timeout: 10_000 do
      {:ok, %{fraud_detected: true}} ->
        # Adjust risk if fraud detected
        adjusted = %{analysis |
          risk_score: 1.0,
          recommendation: :reject,
          fraud_flagged: true
        }
        ok(adjusted)

      {:ok, %{fraud_detected: false}} ->
        ok(Map.put(analysis, :fraud_flagged, false))

      {:timeout, _} ->
        # No fraud alert = proceed normally
        ok(Map.put(analysis, :fraud_flagged, false))
    end
  end

  step finalize(%{listen_for_flags: final_analysis}) do
    # Final result for parent workflow
    ok(final_analysis)
  end

  # Helper functions
  defp calculate_credit_risk(%{score: nil}), do: 0.9  # High risk
  defp calculate_credit_risk(%{score: score}) when score >= 750, do: 0.1
  defp calculate_credit_risk(%{score: score}) when score >= 650, do: 0.4
  defp calculate_credit_risk(%{score: _}), do: 0.8

  defp get_recommendation(risk) when risk < 0.3, do: :approve
  defp get_recommendation(risk) when risk < 0.6, do: :review
  defp get_recommendation(_), do: :reject
end
```

---

## Agent 2: Financial Analysis Agent (with Subworkflow)

```elixir
defmodule FinancialAnalysisAgent do
  use Cerebelum.Workflow

  @doc """
  Analyzes financial documents and income.
  Uses DocumentVerification subworkflow.
  Waits for credit analysis from CreditScoreAgent.
  """

  flow :start,
       :verify_documents,
       :analyze_income,
       :wait_for_credit,
       :calculate_dti,
       :broadcast_results,
       :done

  on_error :verify_documents do
    :verification_failed, retry: 2 -> :verify_documents
    :documents_invalid -> early_reject() |> :done
  end

  step verify_documents(ctx) do
    # Execute subworkflow for document verification
    execute_subworkflow(DocumentVerification, %{
      documents: ctx.documents,
      applicant_id: ctx.applicant_id
    })
  end

  step analyze_income(ctx, %{verify_documents: verified_docs}) do
    # Analyze income from verified documents
    income_analysis = %{
      monthly_income: verified_docs.income,
      employment_status: verified_docs.employment_status,
      income_stability: calculate_stability(verified_docs.income_history),
      verified: true
    }

    ok(income_analysis)
  end

  step wait_for_credit(%{analyze_income: income}) do
    # Wait for credit analysis from CreditScoreAgent
    case await CreditScoreAgent, :credit_analysis_complete, timeout: 30_000 do
      {:ok, credit_data} ->
        ok(%{
          income: income,
          credit: credit_data
        })

      {:timeout, _} ->
        # Proceed without credit data
        ok(%{
          income: income,
          credit: nil
        })
    end
  end

  step calculate_dti(ctx, %{wait_for_credit: data}) do
    # Calculate Debt-to-Income ratio
    monthly_debt = ctx.loan_amount / 360  # 30-year loan
    monthly_income = data.income.monthly_income

    dti_ratio = monthly_debt / monthly_income

    risk_score = cond do
      dti_ratio < 0.28 -> 0.1  # Low risk
      dti_ratio < 0.36 -> 0.4  # Medium risk
      dti_ratio < 0.43 -> 0.7  # High risk
      true -> 0.95             # Very high risk
    end

    analysis = %{
      dti_ratio: dti_ratio,
      monthly_income: monthly_income,
      monthly_debt: monthly_debt,
      risk_score: risk_score,
      status: get_status(dti_ratio),
      credit_score: data.credit && data.credit.score
    }

    ok(analysis)
  end

  step broadcast_results(%{calculate_dti: analysis}) do
    # Broadcast to other agents
    broadcast :financial_analysis_complete, %{
      agent: FinancialAnalysisAgent,
      dti_ratio: analysis.dti_ratio,
      risk_score: analysis.risk_score,
      status: analysis.status
    }

    ok(analysis)
  end

  # Helpers
  defp calculate_stability(history) do
    # Calculate income stability from history
    # Returns: :stable | :unstable
  end

  defp get_status(dti) when dti < 0.36, do: :good
  defp get_status(dti) when dti < 0.43, do: :acceptable
  defp get_status(_), do: :poor

  defp early_reject do
    %{
      risk_score: 1.0,
      status: :rejected,
      reason: "Document verification failed"
    }
  end
end
```

---

## Agent 3: Fraud Detection Agent (with Subworkflow + Communication)

```elixir
defmodule FraudDetectionAgent do
  use Cerebelum.Workflow

  @doc """
  Detects fraud using ML model and rule-based checks.
  Uses FraudCheck subworkflow.
  Broadcasts alerts to other agents if fraud detected.
  """

  flow :start,
       :run_fraud_checks,
       :analyze_patterns,
       :check_with_peers,
       :make_decision,
       :broadcast_alert,
       :done

  step run_fraud_checks(ctx) do
    # Execute fraud check subworkflow
    execute_subworkflow(FraudCheck, %{
      applicant: ctx.applicant,
      application: ctx.application
    })
  end

  step analyze_patterns(%{run_fraud_checks: fraud_data}) do
    # Use ML model to detect fraud patterns
    patterns = MLModel.predict_fraud(%{
      identity_verification: fraud_data.identity_score,
      application_speed: fraud_data.application_speed,
      device_fingerprint: fraud_data.device_fingerprint,
      geo_location: fraud_data.geo_location
    })

    fraud_score = patterns.probability

    ok(%{
      fraud_score: fraud_score,
      patterns: patterns.detected_patterns,
      confidence: patterns.confidence,
      raw_data: fraud_data
    })
  end

  step check_with_peers(%{analyze_patterns: analysis}) do
    # Wait for other agents' opinions
    # Collect messages for 5 seconds (non-blocking)
    messages = receive_from_peers(timeout: 5_000)

    peer_opinions = case messages do
      {:ok, msgs} ->
        Enum.map(msgs, fn {agent, {:credit_analysis_complete, data}} ->
          %{agent: agent, risk: data.risk_score}
        end)

      :timeout ->
        []
    end

    # Adjust fraud score based on peer data
    adjusted_score = if Enum.any?(peer_opinions, fn p -> p.risk > 0.7 end) do
      min(analysis.fraud_score + 0.1, 1.0)
    else
      analysis.fraud_score
    end

    ok(%{analysis |
      fraud_score: adjusted_score,
      peer_opinions: peer_opinions
    })
  end

  step make_decision(%{check_with_peers: analysis}) do
    fraud_detected = analysis.fraud_score > 0.75

    decision = %{
      fraud_detected: fraud_detected,
      fraud_score: analysis.fraud_score,
      risk_score: if(fraud_detected, do: 1.0, else: analysis.fraud_score),
      patterns: analysis.patterns,
      confidence: analysis.confidence,
      recommendation: if(fraud_detected, do: :reject, else: :proceed)
    }

    ok(decision)
  end

  step broadcast_alert(%{make_decision: decision}) do
    # Alert ALL agents if fraud detected
    if decision.fraud_detected do
      broadcast :fraud_alert, %{
        fraud_detected: true,
        fraud_score: decision.fraud_score,
        patterns: decision.patterns,
        agent: FraudDetectionAgent
      }

      # Also send directly to CreditScoreAgent
      send_to CreditScoreAgent, :fraud_alert, %{
        fraud_detected: true,
        fraud_score: decision.fraud_score
      }
    else
      broadcast :fraud_alert, %{fraud_detected: false}
    end

    ok(decision)
  end
end
```

---

## Subworkflow 1: Document Verification

```elixir
defmodule DocumentVerification do
  use Cerebelum.Workflow

  @doc """
  Subworkflow that verifies uploaded documents.
  Used by FinancialAnalysisAgent.
  """

  flow :start,
       :validate_formats,
       :ocr_extraction,
       :verify_authenticity,
       :extract_data,
       :done

  on_error :ocr_extraction do
    :ocr_failed, retry: 2, delay: 3000 -> :ocr_extraction
    :ocr_failed -> use_manual_review() |> :extract_data
  end

  step validate_formats(ctx) do
    # Check document formats
    valid_docs = Enum.filter(ctx.documents, fn doc ->
      doc.format in [:pdf, :jpg, :png] and doc.size < 10_000_000
    end)

    if Enum.empty?(valid_docs) do
      error(:no_valid_documents)
    else
      ok(%{documents: valid_docs})
    end
  end

  step ocr_extraction(%{validate_formats: data}) do
    # Extract text from documents using OCR
    extracted = Enum.map(data.documents, fn doc ->
      case OCRService.extract(doc) do
        {:ok, text} -> %{doc_id: doc.id, text: text, status: :success}
        {:error, _} -> %{doc_id: doc.id, text: nil, status: :failed}
      end
    end)

    ok(%{extracted: extracted})
  end

  step verify_authenticity(%{ocr_extraction: data}) do
    # Verify documents are authentic (not tampered)
    verifications = Enum.map(data.extracted, fn doc ->
      authenticity_score = AuthenticityChecker.verify(doc)
      %{doc | authenticity: authenticity_score}
    end)

    ok(%{verified: verifications})
  end

  step extract_data(%{verify_authenticity: data}) do
    # Extract structured data (income, employment, etc)
    income = extract_income(data.verified)
    employment = extract_employment(data.verified)
    income_history = extract_income_history(data.verified)

    ok(%{
      income: income,
      employment_status: employment,
      income_history: income_history,
      documents_verified: true
    })
  end

  # Helpers
  defp extract_income(docs), do: # Implementation
  defp extract_employment(docs), do: # Implementation
  defp extract_income_history(docs), do: # Implementation

  defp use_manual_review do
    %{
      income: nil,
      employment_status: :unknown,
      income_history: [],
      documents_verified: false,
      manual_review_required: true
    }
  end
end
```

---

## Subworkflow 2: Fraud Check

```elixir
defmodule FraudCheck do
  use Cerebelum.Workflow

  @doc """
  Subworkflow that performs fraud detection checks.
  Used by FraudDetectionAgent.
  """

  flow :start,
       :identity_check,
       :device_fingerprint,
       :velocity_check,
       :aggregate_signals,
       :done

  step identity_check(ctx) do
    # Verify identity against government databases
    identity_score = IdentityVerification.verify(%{
      name: ctx.applicant.name,
      ssn: ctx.applicant.ssn,
      dob: ctx.applicant.date_of_birth
    })

    ok(%{
      identity_score: identity_score.match_score,
      identity_verified: identity_score.verified,
      flags: identity_score.flags
    })
  end

  step device_fingerprint(ctx) do
    # Analyze device/browser fingerprint
    fingerprint = DeviceAnalyzer.analyze(%{
      ip_address: ctx.application.ip_address,
      user_agent: ctx.application.user_agent,
      browser_data: ctx.application.browser_data
    })

    ok(%{
      device_fingerprint: fingerprint.hash,
      device_risk: fingerprint.risk_score,
      is_proxy: fingerprint.is_proxy,
      is_bot: fingerprint.is_bot
    })
  end

  step velocity_check(ctx) do
    # Check application velocity (how fast they filled it)
    time_taken = ctx.application.completion_time_seconds

    velocity_risk = cond do
      time_taken < 60 -> 0.9      # Too fast - likely fraud
      time_taken < 180 -> 0.5     # Fast but possible
      time_taken < 600 -> 0.1     # Normal
      time_taken > 3600 -> 0.3    # Abandoned and resumed
      true -> 0.2
    end

    ok(%{
      application_speed: time_taken,
      velocity_risk: velocity_risk
    })
  end

  step aggregate_signals(%{
    identity_check: identity,
    device_fingerprint: device,
    velocity_check: velocity
  }) do
    # Combine all fraud signals
    ok(%{
      identity_score: identity.identity_score,
      device_fingerprint: device.device_fingerprint,
      application_speed: velocity.application_speed,
      geo_location: device.is_proxy,
      overall_flags: identity.flags ++
                     (if device.is_bot, do: [:bot_detected], else: []) ++
                     (if velocity.velocity_risk > 0.7, do: [:velocity_high], else: [])
    })
  end
end
```

---

## Message Flow Diagram

```
Time →

t0:  Main starts
     └─> parallel_risk_analysis starts 3 agents

t1:  CreditScoreAgent: fetch_credit_score
     FinancialAnalysisAgent: verify_documents (subworkflow starts)
     FraudDetectionAgent: run_fraud_checks (subworkflow starts)

t2:  CreditScoreAgent: analyze_credit
     FinancialAnalysisAgent: (waiting for DocumentVerification)
     FraudDetectionAgent: (waiting for FraudCheck)

t3:  CreditScoreAgent: broadcast_results
     ├──> broadcast(:credit_analysis_complete)
     │    └─> FinancialAnalysisAgent receives
     └─> listen_for_flags (waiting)

t4:  FinancialAnalysisAgent: wait_for_credit
     └─> receives message from CreditScoreAgent

t5:  FinancialAnalysisAgent: calculate_dti
     └─> broadcast_results
         └─> FraudDetectionAgent receives

t6:  FraudDetectionAgent: analyze_patterns
     └─> check_with_peers
         └─> receives messages from other agents

t7:  FraudDetectionAgent: make_decision
     └─> broadcast_alert
         └─> broadcast(:fraud_alert)
             └─> CreditScoreAgent receives

t8:  CreditScoreAgent: listen_for_flags
     └─> receives fraud_alert, adjusts risk

t9:  All agents complete
     Main: consensus_decision (aggregates results)

t10: Main: final_review (LLM call with Cortex)

t11: Main: generate_report
     Done!
```

---

## Event Sourcing - What gets persisted

All these events are saved to EventStore:

```elixir
# Workflow events
%StepCompletedEvent{step: :validate_application, result: {...}}
%StepCompletedEvent{step: :parallel_risk_analysis, result: {...}}

# Message events
%MessageSentEvent{
  from: CreditScoreAgent,
  to: :all_peers,
  type: :credit_analysis_complete,
  payload: %{risk_score: 0.3, ...}
}

%MessageReceivedEvent{
  to: FinancialAnalysisAgent,
  from: CreditScoreAgent,
  type: :credit_analysis_complete
}

%MessageProcessedEvent{
  agent: FinancialAnalysisAgent,
  message_id: "msg-123",
  result: {:ok, %{...}}
}

# Subworkflow events
%SubworkflowStartedEvent{
  parent: FinancialAnalysisAgent,
  child: DocumentVerification
}

%SubworkflowCompletedEvent{
  child: DocumentVerification,
  result: {:ok, %{income: 5000, ...}}
}
```

**Debugging:**
```elixir
# See entire conversation
Cerebelum.Debug.message_trace(execution_id)
# Output:
# t3: CreditScoreAgent -> ALL: credit_analysis_complete
# t4: FinancialAnalysisAgent received from CreditScoreAgent
# t5: FinancialAnalysisAgent -> ALL: financial_analysis_complete
# t7: FraudDetectionAgent -> ALL: fraud_alert
# t8: CreditScoreAgent received fraud_alert from FraudDetectionAgent

# See conversation diagram
Cerebelum.Debug.message_diagram(execution_id)
# ASCII art showing message flow

# Time-travel to t5
Cerebelum.Debug.replay_until(execution_id, t5)
```

---

## Comparison: Before vs After

### Agent with communication (Before)

```elixir
defmodule CreditScoreAgent do
  use Cerebelum.Workflow

  workflow do
    timeline do
      start()
      |> fetch_credit_score()
      |> analyze_credit()
      |> broadcast_results()
      |> listen_for_flags()
      |> finalize()
      |> finish_success()
    end
  end

  def broadcast_results(context, %{analyze_credit: analysis}) do
    Cerebelum.Communication.broadcast_to_peers(
      :credit_analysis_complete,
      %{
        agent: CreditScoreAgent,
        risk_score: analysis.risk_score,
        score: analysis.score
      }
    )
    {:ok, analysis}
  end

  def listen_for_flags(context, %{analyze_credit: analysis}) do
    receive do
      {:msg_from_peer, FraudDetectionAgent, _msg_id, {:fraud_alert, data}} ->
        adjusted = %{analysis |
          risk_score: 1.0,
          fraud_flagged: true
        }
        {:ok, adjusted}
    after 10_000 ->
      {:ok, Map.put(analysis, :fraud_flagged, false)}
    end
  end
end
```

### Agent with communication (After - Improved DSL)

```elixir
defmodule CreditScoreAgent do
  use Cerebelum.Workflow

  flow :start, :fetch_credit_score, :analyze_credit,
       :broadcast_results, :listen_for_flags, :finalize, :done

  step broadcast_results(%{analyze_credit: analysis}) do
    broadcast :credit_analysis_complete, %{
      agent: CreditScoreAgent,
      risk_score: analysis.risk_score,
      score: analysis.score
    }
    ok(analysis)
  end

  step listen_for_flags(%{analyze_credit: analysis}) do
    case await FraudDetectionAgent, :fraud_alert, timeout: 10_000 do
      {:ok, %{fraud_detected: true}} ->
        ok(%{analysis | risk_score: 1.0, fraud_flagged: true})

      {:ok, %{fraud_detected: false}} ->
        ok(Map.put(analysis, :fraud_flagged, false))

      {:timeout, _} ->
        ok(Map.put(analysis, :fraud_flagged, false))
    end
  end
end
```

**Reduction: 60% less code, same functionality**

---

## Running the System

```elixir
# Start loan application workflow
{:ok, exec_id} = Cerebelum.execute_workflow(
  LoanApplication,
  %{
    application_id: "app-12345",
    applicant_name: "John Doe",
    loan_amount: 250_000
  }
)

# Monitor execution
Cerebelum.get_execution_status(exec_id)
# => %{
#   status: :running,
#   current_step: :parallel_risk_analysis,
#   agents_running: [CreditScoreAgent, FinancialAnalysisAgent, FraudDetectionAgent]
# }

# View message trace
Cerebelum.Debug.message_trace(exec_id)

# View workflow timeline
Cerebelum.Debug.workflow_timeline(exec_id)
```

---

## Key Features Demonstrated

1. ✅ **Parallel agents** - 3 agents running simultaneously
2. ✅ **Inter-agent messages** - Agents communicate via broadcast/await
3. ✅ **Subworkflows** - DocumentVerification, FraudCheck
4. ✅ **Error handling** - Retries with delays, fallbacks
5. ✅ **Conditional branching** - Risk-based routing
6. ✅ **LLM integration** - Cortex for final review
7. ✅ **Event sourcing** - All messages persisted for replay
8. ✅ **Concise syntax** - 60-70% less code with improved DSL

---

**End of Example**

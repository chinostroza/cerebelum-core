defmodule Cerebelum.Examples.BankReconciliationWorkflow do
  @moduledoc """
  Ejemplo avanzado: Reconciliación Bancaria.

  Este workflow demuestra un caso de uso real complejo:
  - Timeline con 8 steps interdependientes
  - Múltiples diverges para manejo de errores
  - Branch para decisiones basadas en diferencias
  - Manejo de timeouts y reintentos

  ## Flujo del Proceso

  1. `fetch_bank_statement/1` - Obtiene estado de cuenta del banco
     - Diverge: `:timeout` -> retry
  2. `fetch_internal_ledger/2` - Obtiene libro contable interno
     - Diverge: `:timeout` -> retry
  3. `parse_transactions/2` - Parsea transacciones de ambas fuentes
  4. `match_transactions/2` - Empareja transacciones
  5. `calculate_differences/2` - Calcula diferencias
     - Branch: differences > threshold -> :escalate, else -> :auto_resolve
  6. `generate_report/2` - Genera reporte de reconciliación
  7. `send_notifications/2` - Envía notificaciones
  8. `archive_results/2` - Archiva resultados

  ## Ejemplo de Uso

      inputs = %{
        account_id: "ACC-12345",
        period_start: ~D[2025-01-01],
        period_end: ~D[2025-01-31],
        threshold: 100.00
      }

      context = Context.new(BankReconciliationWorkflow, inputs)
  """

  use Cerebelum.Workflow

  workflow do
    timeline do
      fetch_bank_statement() |>
        fetch_internal_ledger() |>
        parse_transactions() |>
        match_transactions() |>
        calculate_differences() |>
        generate_report() |>
        send_notifications() |>
        archive_results()
    end

    # Retry en timeout para fetch bank statement
    diverge from: fetch_bank_statement() do
      :timeout -> :retry
      {:error, :bank_api_down} -> :failed
      {:error, _} -> :failed
    end

    # Retry en timeout para fetch internal ledger
    diverge from: fetch_internal_ledger() do
      :timeout -> :retry
      {:error, :database_error} -> :failed
      {:error, _} -> :failed
    end

    # Decisión basada en monto de diferencias
    branch after: calculate_differences(), on: result do
      result.total_diff > result.threshold -> :escalate
      true -> :auto_resolve
    end
  end

  @doc """
  Obtiene el estado de cuenta del banco vía API.

  ## Retorna

  - `{:ok, statement}` - Estado de cuenta obtenido
  - `:timeout` - Timeout en la llamada a la API
  - `{:error, :bank_api_down}` - API del banco no disponible
  """
  def fetch_bank_statement(context) do
    account_id = context.inputs[:account_id]
    period_start = context.inputs[:period_start]
    period_end = context.inputs[:period_end]

    # Simular llamada a API bancaria
    # En producción, esto sería una llamada HTTP real
    statement = %{
      account_id: account_id,
      period: %{start: period_start, end: period_end},
      transactions: [
        %{id: "BNK-001", date: ~D[2025-01-15], amount: -500.00, description: "Payment to Vendor A"},
        %{id: "BNK-002", date: ~D[2025-01-20], amount: 1000.00, description: "Deposit from Customer X"},
        %{id: "BNK-003", date: ~D[2025-01-25], amount: -250.00, description: "Fee"}
      ],
      balance: 250.00
    }

    {:ok, statement}
  end

  @doc """
  Obtiene el libro contable interno desde la base de datos.

  ## Retorna

  - `{:ok, ledger}` - Libro contable obtenido
  - `:timeout` - Timeout en query a BD
  - `{:error, :database_error}` - Error de base de datos
  """
  def fetch_internal_ledger(context, _bank_statement) do
    account_id = context.inputs[:account_id]
    period_start = context.inputs[:period_start]
    period_end = context.inputs[:period_end]

    # Simular query a base de datos
    ledger = %{
      account_id: account_id,
      period: %{start: period_start, end: period_end},
      entries: [
        %{id: "LED-001", date: ~D[2025-01-15], amount: -500.00, description: "Payment to Vendor A", ref: "BNK-001"},
        %{id: "LED-002", date: ~D[2025-01-20], amount: 1000.00, description: "Deposit from Customer X", ref: "BNK-002"},
        %{id: "LED-003", date: ~D[2025-01-22], amount: -100.00, description: "Internal Transfer", ref: nil}
      ],
      balance: 400.00
    }

    {:ok, ledger}
  end

  @doc """
  Parsea y normaliza transacciones de ambas fuentes.

  ## Retorna

  - `{:ok, parsed}` - Transacciones parseadas y normalizadas
  """
  def parse_transactions(_context, {:ok, bank_statement}, {:ok, ledger}) do
    bank_txns = normalize_bank_transactions(bank_statement.transactions)
    ledger_txns = normalize_ledger_entries(ledger.entries)

    {:ok, %{
      bank: bank_txns,
      ledger: ledger_txns,
      bank_balance: bank_statement.balance,
      ledger_balance: ledger.balance
    }}
  end

  @doc """
  Empareja transacciones entre banco y libro contable.

  ## Retorna

  - `{:ok, matches}` - Transacciones emparejadas y no emparejadas
  """
  def match_transactions(_context, _bank, _ledger, {:ok, parsed}) do
    bank_txns = parsed.bank
    ledger_txns = parsed.ledger

    # Emparejar por referencia o por monto + fecha
    matched = find_matches(bank_txns, ledger_txns)
    unmatched_bank = bank_txns -- Enum.map(matched, & &1.bank)
    unmatched_ledger = ledger_txns -- Enum.map(matched, & &1.ledger)

    {:ok, %{
      matched: matched,
      unmatched_bank: unmatched_bank,
      unmatched_ledger: unmatched_ledger,
      matched_count: length(matched),
      unmatched_count: length(unmatched_bank) + length(unmatched_ledger)
    }}
  end

  @doc """
  Calcula diferencias y analiza discrepancias.

  ## Retorna

  - `{:ok, differences}` - Análisis de diferencias con recomendaciones
  """
  def calculate_differences(context, _bank, _ledger, _parsed, {:ok, matches}) do
    threshold = context.inputs[:threshold] || 100.00

    # Calcular diferencia total
    total_diff = calculate_total_difference(matches)

    {:ok, %{
      total_diff: abs(total_diff),
      threshold: threshold,
      matched_count: matches.matched_count,
      unmatched_count: matches.unmatched_count,
      unmatched_bank: matches.unmatched_bank,
      unmatched_ledger: matches.unmatched_ledger,
      requires_escalation: abs(total_diff) > threshold
    }}
  end

  @doc """
  Genera reporte de reconciliación.

  ## Retorna

  - `{:ok, report}` - Reporte generado con resumen y detalles
  """
  def generate_report(_context, _bank, _ledger, _parsed, _matches, {:ok, diffs}) do
    report = %{
      summary: %{
        total_matched: diffs.matched_count,
        total_unmatched: diffs.unmatched_count,
        total_difference: diffs.total_diff,
        status: if(diffs.requires_escalation, do: :needs_review, else: :approved)
      },
      details: %{
        unmatched_bank_transactions: diffs.unmatched_bank,
        unmatched_ledger_entries: diffs.unmatched_ledger
      },
      generated_at: DateTime.utc_now()
    }

    {:ok, report}
  end

  @doc """
  Envía notificaciones según el resultado.

  ## Retorna

  - `{:ok, notifications}` - Notificaciones enviadas
  """
  def send_notifications(_context, _bank, _ledger, _parsed, _matches, diffs, {:ok, _report}) do
    notifications =
      if diffs.requires_escalation do
        [
          %{to: "finance_manager@company.com", subject: "Reconciliation Requires Review", status: :sent},
          %{to: "accounting_team@company.com", subject: "Large Discrepancy Detected", status: :sent}
        ]
      else
        [
          %{to: "accounting_team@company.com", subject: "Reconciliation Complete", status: :sent}
        ]
      end

    {:ok, %{
      notifications: notifications,
      count: length(notifications),
      report_attached: true
    }}
  end

  @doc """
  Archiva resultados para auditoría.

  ## Retorna

  - `{:ok, archive}` - Resultados archivados
  """
  def archive_results(_context, _bank, _ledger, _parsed, _matches, _diffs, report, _notifications) do
    {:ok, %{
      archived_at: DateTime.utc_now(),
      report_id: "RPT-#{:rand.uniform(999999)}",
      storage_path: "/archive/reconciliations/#{Date.utc_today()}",
      report_summary: report.summary
    }}
  end

  ## Helper Functions

  defp normalize_bank_transactions(transactions) do
    Enum.map(transactions, fn txn ->
      Map.put(txn, :type, :bank)
    end)
  end

  defp normalize_ledger_entries(entries) do
    Enum.map(entries, fn entry ->
      entry
      |> Map.put(:type, :ledger)
      |> Map.put(:id, entry[:id] || "LED-#{:rand.uniform(999)}")
    end)
  end

  defp find_matches(bank_txns, ledger_txns) do
    # Matching simple por amount y date
    for bank <- bank_txns,
        ledger <- ledger_txns,
        bank[:amount] == ledger[:amount] and bank[:date] == ledger[:date] do
      %{bank: bank, ledger: ledger}
    end
  end

  defp calculate_total_difference(matches) do
    unmatched_bank_total =
      Enum.reduce(matches.unmatched_bank, 0, fn txn, acc -> acc + txn[:amount] end)

    unmatched_ledger_total =
      Enum.reduce(matches.unmatched_ledger, 0, fn entry, acc -> acc + entry[:amount] end)

    unmatched_bank_total - unmatched_ledger_total
  end
end

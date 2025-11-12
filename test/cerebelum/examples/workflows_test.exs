defmodule Cerebelum.Examples.WorkflowsTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Examples.{CounterWorkflow, OrderWorkflow, BankReconciliationWorkflow}
  alias Cerebelum.Workflow.Metadata

  describe "CounterWorkflow" do
    test "workflow compiles without errors" do
      # Si el módulo existe, significa que compiló correctamente
      assert Code.ensure_loaded?(CounterWorkflow)
    end

    test "has correct timeline" do
      metadata = CounterWorkflow.__workflow_metadata__()

      assert metadata.timeline == [:initialize, :increment, :double, :finalize]
    end

    test "has no diverges or branches" do
      metadata = CounterWorkflow.__workflow_metadata__()

      assert metadata.diverges == %{}
      assert metadata.branches == %{}
    end

    test "metadata extraction works" do
      metadata = Metadata.extract(CounterWorkflow)

      assert metadata.module == CounterWorkflow
      assert length(metadata.timeline) == 4
      assert map_size(metadata.functions) == 4
    end

    test "all functions have correct arity" do
      metadata = Metadata.extract(CounterWorkflow)

      assert metadata.functions[:initialize].arity == 1
      assert metadata.functions[:increment].arity == 2
      assert metadata.functions[:double].arity == 3
      assert metadata.functions[:finalize].arity == 4
    end

    test "functions execute correctly" do
      # Test de integración básico
      init_result = CounterWorkflow.initialize(nil)
      assert init_result == {:ok, 0}

      inc_result = CounterWorkflow.increment(nil, init_result)
      assert inc_result == {:ok, 1}

      double_result = CounterWorkflow.double(nil, init_result, inc_result)
      assert double_result == {:ok, 2}

      final_result = CounterWorkflow.finalize(nil, init_result, inc_result, double_result)
      assert final_result == {:ok, 2}
    end
  end

  describe "OrderWorkflow" do
    test "workflow compiles without errors" do
      assert Code.ensure_loaded?(OrderWorkflow)
    end

    test "has correct timeline" do
      metadata = OrderWorkflow.__workflow_metadata__()

      assert metadata.timeline == [
               :validate_order,
               :check_inventory,
               :process_payment,
               :ship_order,
               :notify_customer
             ]
    end

    test "has diverges configured" do
      metadata = OrderWorkflow.__workflow_metadata__()

      assert Map.has_key?(metadata.diverges, :validate_order)
      assert Map.has_key?(metadata.diverges, :check_inventory)
    end

    test "has branch configured" do
      metadata = OrderWorkflow.__workflow_metadata__()

      assert Map.has_key?(metadata.branches, :process_payment)
    end

    test "metadata extraction works" do
      metadata = Metadata.extract(OrderWorkflow)

      assert metadata.module == OrderWorkflow
      assert length(metadata.timeline) == 5
      assert map_size(metadata.diverges) == 2
      assert map_size(metadata.branches) == 1
    end

    test "validates valid order" do
      context = %{
        inputs: %{
          order: %{
            id: "ORD-123",
            items: [%{sku: "ITEM-1", quantity: 2, price: 500}],
            customer: %{email: "test@example.com"},
            shipping_address: %{street: "123 Main St"}
          }
        }
      }

      result = OrderWorkflow.validate_order(context)
      assert {:ok, _order} = result
    end

    test "rejects invalid order" do
      context = %{inputs: %{order: nil}}

      result = OrderWorkflow.validate_order(context)
      assert {:error, :invalid_order} = result
    end

    test "checks inventory successfully" do
      context = %{inputs: %{}}
      order = {:ok, %{items: [%{quantity: 1}]}}

      result = OrderWorkflow.check_inventory(context, order)
      assert {:ok, %{available: true}} = result
    end

    test "processes payment and calculates amount" do
      context = %{inputs: %{}}
      order = {:ok, %{items: [%{price: 100, quantity: 2}, %{price: 50, quantity: 1}]}}
      inventory = {:ok, %{available: true}}

      result = OrderWorkflow.process_payment(context, order, inventory)

      assert {:ok, payment} = result
      assert payment.amount == 250
      assert payment.status == :paid
    end
  end

  describe "BankReconciliationWorkflow" do
    test "workflow compiles without errors" do
      assert Code.ensure_loaded?(BankReconciliationWorkflow)
    end

    test "has correct timeline" do
      metadata = BankReconciliationWorkflow.__workflow_metadata__()

      assert metadata.timeline == [
               :fetch_bank_statement,
               :fetch_internal_ledger,
               :parse_transactions,
               :match_transactions,
               :calculate_differences,
               :generate_report,
               :send_notifications,
               :archive_results
             ]
    end

    test "has diverges for retry logic" do
      metadata = BankReconciliationWorkflow.__workflow_metadata__()

      assert Map.has_key?(metadata.diverges, :fetch_bank_statement)
      assert Map.has_key?(metadata.diverges, :fetch_internal_ledger)
    end

    test "has branch for escalation logic" do
      metadata = BankReconciliationWorkflow.__workflow_metadata__()

      assert Map.has_key?(metadata.branches, :calculate_differences)
    end

    test "metadata extraction works" do
      metadata = Metadata.extract(BankReconciliationWorkflow)

      assert metadata.module == BankReconciliationWorkflow
      assert length(metadata.timeline) == 8
      assert map_size(metadata.diverges) == 2
      assert map_size(metadata.branches) == 1
    end

    test "fetches bank statement" do
      context = %{
        inputs: %{
          account_id: "ACC-123",
          period_start: ~D[2025-01-01],
          period_end: ~D[2025-01-31]
        }
      }

      result = BankReconciliationWorkflow.fetch_bank_statement(context)

      assert {:ok, statement} = result
      assert statement.account_id == "ACC-123"
      assert is_list(statement.transactions)
    end

    test "fetches internal ledger" do
      context = %{
        inputs: %{
          account_id: "ACC-123",
          period_start: ~D[2025-01-01],
          period_end: ~D[2025-01-31]
        }
      }

      bank_statement = {:ok, %{}}

      result = BankReconciliationWorkflow.fetch_internal_ledger(context, bank_statement)

      assert {:ok, ledger} = result
      assert ledger.account_id == "ACC-123"
      assert is_list(ledger.entries)
    end

    test "parses transactions from both sources" do
      context = %{inputs: %{}}

      bank_statement =
        {:ok, %{transactions: [%{id: "B1", amount: 100}], balance: 100}}

      ledger = {:ok, %{entries: [%{id: "L1", amount: 100}], balance: 100}}

      result = BankReconciliationWorkflow.parse_transactions(context, bank_statement, ledger)

      assert {:ok, parsed} = result
      assert is_list(parsed.bank)
      assert is_list(parsed.ledger)
    end

    test "calculates differences correctly" do
      context = %{inputs: %{threshold: 50.00}}

      matches =
        {:ok, %{
          matched: [],
          unmatched_bank: [%{amount: 100}],
          unmatched_ledger: [%{amount: 80}],
          matched_count: 0,
          unmatched_count: 2
        }}

      result =
        BankReconciliationWorkflow.calculate_differences(
          context,
          nil,
          nil,
          nil,
          matches
        )

      assert {:ok, diffs} = result
      assert diffs.total_diff >= 0
      assert diffs.threshold == 50.00
    end
  end

  describe "all example workflows" do
    test "all workflows have valid metadata" do
      workflows = [CounterWorkflow, OrderWorkflow, BankReconciliationWorkflow]

      for workflow <- workflows do
        metadata = workflow.__workflow_metadata__()

        assert is_list(metadata.timeline)
        assert is_map(metadata.diverges)
        assert is_map(metadata.branches)
        assert is_binary(metadata.version)
      end
    end

    test "all workflows pass validation" do
      # Si los workflows compilan, significa que pasaron validación en compile-time
      assert Code.ensure_loaded?(CounterWorkflow)
      assert Code.ensure_loaded?(OrderWorkflow)
      assert Code.ensure_loaded?(BankReconciliationWorkflow)
    end

    test "all workflows can be registered" do
      alias Cerebelum.Workflow.Registry

      {:ok, _pid} = Registry.start_link(name: :test_examples_registry)

      workflows = [CounterWorkflow, OrderWorkflow, BankReconciliationWorkflow]

      for workflow <- workflows do
        assert {:ok, _metadata} = Registry.register(workflow, registry: :test_examples_registry)
      end

      # Verificar que todos están registrados
      all_workflows = Registry.list_all(registry: :test_examples_registry)
      assert length(all_workflows) == 3

      # Cleanup
      GenServer.stop(:test_examples_registry)
    end
  end
end

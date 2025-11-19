defmodule Cerebelum.Infrastructure.DLQTest do
  use Cerebelum.DataCase, async: false

  alias Cerebelum.Infrastructure.DLQ
  alias Cerebelum.Infrastructure.Schemas.DLQItem
  alias Cerebelum.Repo

  setup do
    # Clean up DLQ table before each test
    Repo.delete_all(DLQItem)
    :ok
  end

  describe "add_to_dlq/2" do
    test "successfully adds a task to DLQ" do
      task_info = %{
        task_id: "task_123",
        execution_id: "exec_456",
        workflow_module: :test_workflow,
        step_name: "failing_step",
        inputs: %{"key" => "value"},
        context: %{"attempt" => 3},
        retry_count: 3
      }

      error = %{
        kind: "timeout",
        message: "Task timed out after 3 retries",
        stacktrace: "line 1\nline 2"
      }

      assert {:ok, dlq_id} = DLQ.add_to_dlq(task_info, error)
      assert is_binary(dlq_id)

      # Verify item was persisted
      dlq_item = Repo.get(DLQItem, dlq_id)
      assert dlq_item != nil
      assert dlq_item.task_id == "task_123"
      assert dlq_item.execution_id == "exec_456"
      assert dlq_item.workflow_module == "test_workflow"
      assert dlq_item.step_name == "failing_step"
      assert dlq_item.error_kind == "timeout"
      assert dlq_item.error_message == "Task timed out after 3 retries"
      assert dlq_item.retry_count == 3
      assert dlq_item.task_inputs == %{"key" => "value"}
      assert dlq_item.status == "pending"
    end

    test "adds multiple tasks to DLQ" do
      for i <- 1..5 do
        task_info = %{
          task_id: "task_#{i}",
          execution_id: "exec_#{i}",
          workflow_module: :test_workflow,
          step_name: "step_#{i}",
          inputs: %{},
          context: %{},
          retry_count: 3
        }

        error = %{kind: "failed", message: "Failed", stacktrace: ""}

        assert {:ok, _dlq_id} = DLQ.add_to_dlq(task_info, error)
      end

      items = Repo.all(DLQItem)
      assert length(items) == 5
    end
  end

  describe "list_items/1" do
    setup do
      # Create test items
      for i <- 1..10 do
        task_info = %{
          task_id: "task_#{i}",
          execution_id: if(rem(i, 2) == 0, do: "exec_even", else: "exec_odd"),
          workflow_module: if(rem(i, 3) == 0, do: :workflow_a, else: :workflow_b),
          step_name: "step_#{i}",
          inputs: %{},
          context: %{},
          retry_count: 3
        }

        error = %{kind: "failed", message: "Failed", stacktrace: ""}

        {:ok, dlq_id} = DLQ.add_to_dlq(task_info, error)

        # Mark some as retried/resolved
        if rem(i, 4) == 0 do
          dlq_item = Repo.get(DLQItem, dlq_id)
          Repo.update!(Ecto.Changeset.change(dlq_item, %{status: "retried"}))
        end

        if rem(i, 5) == 0 do
          dlq_item = Repo.get(DLQItem, dlq_id)
          Repo.update!(Ecto.Changeset.change(dlq_item, %{status: "resolved"}))
        end
      end

      :ok
    end

    test "lists all items without filters" do
      assert {:ok, items} = DLQ.list_items()
      assert length(items) == 10
    end

    test "filters by status" do
      assert {:ok, pending_items} = DLQ.list_items(status: "pending")
      # Items 1, 2, 3, 6, 7, 9 should be pending (not multiples of 4 or 5)
      assert length(pending_items) == 6

      assert {:ok, retried_items} = DLQ.list_items(status: "retried")
      # Items 4, 8 (multiples of 4 but not 5)
      assert length(retried_items) == 2

      assert {:ok, resolved_items} = DLQ.list_items(status: "resolved")
      # Items 5, 10 (multiples of 5)
      assert length(resolved_items) == 2
    end

    test "filters by execution_id" do
      assert {:ok, even_items} = DLQ.list_items(execution_id: "exec_even")
      assert length(even_items) == 5

      assert {:ok, odd_items} = DLQ.list_items(execution_id: "exec_odd")
      assert length(odd_items) == 5
    end

    test "filters by workflow_module" do
      assert {:ok, workflow_a_items} = DLQ.list_items(workflow_module: "workflow_a")
      # Items 3, 6, 9 (multiples of 3)
      assert length(workflow_a_items) == 3

      assert {:ok, workflow_b_items} = DLQ.list_items(workflow_module: "workflow_b")
      assert length(workflow_b_items) == 7
    end

    test "supports pagination with limit and offset" do
      assert {:ok, first_page} = DLQ.list_items(limit: 3, offset: 0)
      assert length(first_page) == 3

      assert {:ok, second_page} = DLQ.list_items(limit: 3, offset: 3)
      assert length(second_page) == 3

      assert {:ok, third_page} = DLQ.list_items(limit: 3, offset: 6)
      assert length(third_page) == 3

      assert {:ok, fourth_page} = DLQ.list_items(limit: 3, offset: 9)
      assert length(fourth_page) == 1
    end

    test "combines multiple filters" do
      assert {:ok, filtered_items} = DLQ.list_items(
        status: "pending",
        execution_id: "exec_even"
      )

      # Even items that are pending: 2, 6 (4 is retried, 10 is resolved)
      assert length(filtered_items) == 2
    end
  end

  describe "get_item/1" do
    test "successfully retrieves an existing item" do
      task_info = %{
        task_id: "task_123",
        execution_id: "exec_456",
        workflow_module: :test_workflow,
        step_name: "failing_step",
        inputs: %{},
        context: %{},
        retry_count: 3
      }

      error = %{kind: "timeout", message: "Failed", stacktrace: ""}

      {:ok, dlq_id} = DLQ.add_to_dlq(task_info, error)

      assert {:ok, dlq_item} = DLQ.get_item(dlq_id)
      assert dlq_item.id == dlq_id
      assert dlq_item.task_id == "task_123"
    end

    test "returns error for non-existent item" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :not_found} = DLQ.get_item(fake_id)
    end
  end

  describe "retry_item/2" do
    test "successfully retries a pending item" do
      task_info = %{
        task_id: "task_123",
        execution_id: "exec_456",
        workflow_module: :test_workflow,
        step_name: "failing_step",
        inputs: %{"test" => "data"},
        context: %{"ctx" => "value"},
        retry_count: 3
      }

      error = %{kind: "timeout", message: "Failed", stacktrace: ""}

      {:ok, dlq_id} = DLQ.add_to_dlq(task_info, error)

      # Start TaskRouter for requeuing
      assert {:ok, new_task_id} = DLQ.retry_item(dlq_id, "admin")

      # Verify item status updated
      dlq_item = Repo.get(DLQItem, dlq_id)
      assert dlq_item.status == "retried"
      assert dlq_item.resolved_by == "admin"
      assert dlq_item.resolved_at != nil

      # Verify new task ID returned
      assert is_binary(new_task_id)
    end

    test "returns error when retrying non-existent item" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :not_found} = DLQ.retry_item(fake_id, "admin")
    end

    test "returns error when retrying already processed item" do
      task_info = %{
        task_id: "task_123",
        execution_id: "exec_456",
        workflow_module: :test_workflow,
        step_name: "failing_step",
        inputs: %{},
        context: %{},
        retry_count: 3
      }

      error = %{kind: "timeout", message: "Failed", stacktrace: ""}

      {:ok, dlq_id} = DLQ.add_to_dlq(task_info, error)

      # Retry once
      assert {:ok, _task_id} = DLQ.retry_item(dlq_id, "admin")

      # Try to retry again
      assert {:error, :already_processed} = DLQ.retry_item(dlq_id, "admin")
    end
  end

  describe "resolve_item/3" do
    test "successfully resolves a pending item" do
      task_info = %{
        task_id: "task_123",
        execution_id: "exec_456",
        workflow_module: :test_workflow,
        step_name: "failing_step",
        inputs: %{},
        context: %{},
        retry_count: 3
      }

      error = %{kind: "timeout", message: "Failed", stacktrace: ""}

      {:ok, dlq_id} = DLQ.add_to_dlq(task_info, error)

      assert {:ok, resolved_item} = DLQ.resolve_item(dlq_id, "admin", "Fixed manually")

      assert resolved_item.status == "resolved"
      assert resolved_item.resolved_by == "admin"
      assert resolved_item.resolved_at != nil
    end

    test "returns error when resolving non-existent item" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :not_found} = DLQ.resolve_item(fake_id, "admin", nil)
    end

    test "returns error when resolving already processed item" do
      task_info = %{
        task_id: "task_123",
        execution_id: "exec_456",
        workflow_module: :test_workflow,
        step_name: "failing_step",
        inputs: %{},
        context: %{},
        retry_count: 3
      }

      error = %{kind: "timeout", message: "Failed", stacktrace: ""}

      {:ok, dlq_id} = DLQ.add_to_dlq(task_info, error)

      # Resolve once
      assert {:ok, _item} = DLQ.resolve_item(dlq_id, "admin", nil)

      # Try to resolve again
      assert {:error, :already_processed} = DLQ.resolve_item(dlq_id, "admin", nil)
    end
  end

  describe "get_stats/0" do
    test "returns correct stats for empty DLQ" do
      assert {:ok, stats} = DLQ.get_stats()
      assert stats["total"] == 0
    end

    test "returns correct stats with items in various states" do
      # Add 5 pending, 3 retried, 2 resolved
      for i <- 1..10 do
        task_info = %{
          task_id: "task_#{i}",
          execution_id: "exec_#{i}",
          workflow_module: :test_workflow,
          step_name: "step",
          inputs: %{},
          context: %{},
          retry_count: 3
        }

        error = %{kind: "failed", message: "Failed", stacktrace: ""}

        {:ok, dlq_id} = DLQ.add_to_dlq(task_info, error)

        cond do
          i <= 5 ->
            # Leave as pending
            :ok

          i <= 8 ->
            # Mark as retried
            dlq_item = Repo.get(DLQItem, dlq_id)
            Repo.update!(Ecto.Changeset.change(dlq_item, %{status: "retried"}))

          true ->
            # Mark as resolved
            dlq_item = Repo.get(DLQItem, dlq_id)
            Repo.update!(Ecto.Changeset.change(dlq_item, %{status: "resolved"}))
        end
      end

      assert {:ok, stats} = DLQ.get_stats()
      assert stats["total"] == 10
      assert stats["pending"] == 5
      assert stats["retried"] == 3
      assert stats["resolved"] == 2
    end
  end
end

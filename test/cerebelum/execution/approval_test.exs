defmodule Cerebelum.Execution.ApprovalTest do
  use ExUnit.Case, async: false

  alias Cerebelum.Execution.Engine
  alias Cerebelum.Execution.Approval
  alias Cerebelum.EventStore
  alias Cerebelum.Repo

  setup do
    # Checkout sandbox connection for test isolation
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Allow EventStore GenServer to use the sandbox connection
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), Process.whereis(Cerebelum.EventStore))

    # Clean up events table before each test
    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE TABLE events CASCADE", [])

    :ok
  end

  defmodule SimpleApprovalWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        start() |> wait_for_approval() |> finish()
      end
    end

    def start(_ctx) do
      {:ok, %{started: true}}
    end

    def wait_for_approval(_ctx, {:ok, _start}) do
      {:wait_for_approval,
       [type: :manual],
       %{message: "Please review this workflow"}}
    end

    def finish(_ctx, {:ok, _start}, _approval) do
      {:ok, %{finished: true}}
    end
  end

  defmodule ApprovalWithTimeoutWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        start() |> wait_with_timeout() |> finish()
      end
    end

    def start(_ctx), do: {:ok, :started}

    def wait_with_timeout(_ctx, {:ok, _}) do
      # 1 second timeout
      {:wait_for_approval,
       [type: :manual, timeout_seconds: 1],
       %{needs_review: true}}
    end

    def finish(_ctx, {:ok, _}, _approval), do: {:ok, :done}
  end

  defmodule MultipleApprovalsWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        step1() |> approval1() |> step2() |> approval2() |> step3()
      end
    end

    def step1(_ctx), do: {:ok, 1}

    def approval1(_ctx, {:ok, _}) do
      {:wait_for_approval,
       [type: :review],
       %{stage: "first_approval"}}
    end

    def step2(_ctx, {:ok, _}, _approval), do: {:ok, 2}

    def approval2(_ctx, {:ok, _}, _approval, {:ok, _}) do
      {:wait_for_approval,
       [type: :review],
       %{stage: "second_approval"}}
    end

    def step3(_ctx, {:ok, _}, _approval1, {:ok, _}, _approval2), do: {:ok, 3}
  end

  describe "approval workflow" do
    test "workflow waits for approval and continues when approved" do
      # Start workflow
      {:ok, pid} = Engine.start_link(workflow_module: SimpleApprovalWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for workflow to reach approval state
      Process.sleep(100)

      # Should be waiting for approval
      status = Engine.get_status(pid)
      assert status.state == :waiting_for_approval
      assert status.approval_type == :manual
      assert status.approval_data == %{message: "Please review this workflow"}
      assert status.approval_step_name == :wait_for_approval

      # Approve the workflow
      {:ok, :approved} = Approval.approve(pid, %{approved_by: "Alice"})

      # Wait for completion
      Process.sleep(100)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Should be completed
      status = Engine.get_status(pid)
      assert status.state == :completed

      # Verify results
      assert Map.has_key?(status.results, :finish)
      {:ok, finish_result} = status.results.finish
      assert finish_result.finished == true

      # Check events
      {:ok, events} = EventStore.get_events(execution_id)

      approval_requested =
        Enum.find(events, fn e -> e.event_type == "ApprovalRequestedEvent" end)

      assert approval_requested != nil
      assert approval_requested.event_data["approval_type"] == "manual"
      assert approval_requested.event_data["step_name"] == "wait_for_approval"

      approval_received = Enum.find(events, fn e -> e.event_type == "ApprovalReceivedEvent" end)
      assert approval_received != nil
      assert approval_received.event_data["step_name"] == "wait_for_approval"
      assert approval_received.event_data["approval_response"]["approved_by"] == "Alice"
      assert approval_received.event_data["elapsed_ms"] > 0
    end

    test "workflow fails when approval is rejected" do
      # Start workflow
      {:ok, pid} = Engine.start_link(workflow_module: SimpleApprovalWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for workflow to reach approval state
      Process.sleep(100)

      # Should be waiting for approval
      status = Engine.get_status(pid)
      assert status.state == :waiting_for_approval

      # Reject the workflow
      {:ok, :rejected} = Approval.reject(pid, "Does not meet requirements")

      # Wait a bit
      Process.sleep(100)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Should be failed
      status = Engine.get_status(pid)
      assert status.state == :failed
      assert status.error.kind == :approval_rejected
      assert status.error.reason == "Does not meet requirements"

      # Check events
      {:ok, events} = EventStore.get_events(execution_id)

      approval_rejected = Enum.find(events, fn e -> e.event_type == "ApprovalRejectedEvent" end)
      assert approval_rejected != nil
      assert approval_rejected.event_data["step_name"] == "wait_for_approval"
      assert approval_rejected.event_data["rejection_reason"] == "Does not meet requirements"
      assert approval_rejected.event_data["elapsed_ms"] > 0
    end

    test "workflow fails when approval times out" do
      # Start workflow
      {:ok, pid} =
        Engine.start_link(workflow_module: ApprovalWithTimeoutWorkflow, inputs: %{})

      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for workflow to reach approval state
      Process.sleep(100)

      # Should be waiting for approval
      status = Engine.get_status(pid)
      assert status.state == :waiting_for_approval
      assert status.approval_timeout_ms == 1000

      # Wait for timeout (1 second + overhead)
      Process.sleep(1200)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Should be failed
      status = Engine.get_status(pid)
      assert status.state == :failed
      assert status.error.kind == :approval_timeout

      # Check events
      {:ok, events} = EventStore.get_events(execution_id)

      approval_timeout = Enum.find(events, fn e -> e.event_type == "ApprovalTimeoutEvent" end)
      assert approval_timeout != nil
      assert approval_timeout.event_data["step_name"] == "wait_with_timeout"
      assert approval_timeout.event_data["timeout_ms"] == 1000
    end

    test "workflow can be approved before timeout" do
      # Start workflow
      {:ok, pid} =
        Engine.start_link(workflow_module: ApprovalWithTimeoutWorkflow, inputs: %{})

      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for workflow to reach approval state
      Process.sleep(100)

      # Should be waiting for approval
      status = Engine.get_status(pid)
      assert status.state == :waiting_for_approval

      # Approve before timeout (timeout is 1 second)
      {:ok, :approved} = Approval.approve(pid)

      # Wait for completion
      Process.sleep(100)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Should be completed (not timed out)
      status = Engine.get_status(pid)
      assert status.state == :completed

      # Check events - should have approval received, not timeout
      {:ok, events} = EventStore.get_events(execution_id)

      approval_received = Enum.find(events, fn e -> e.event_type == "ApprovalReceivedEvent" end)
      assert approval_received != nil

      approval_timeout = Enum.find(events, fn e -> e.event_type == "ApprovalTimeoutEvent" end)
      assert approval_timeout == nil
    end

    test "multiple approvals in sequence" do
      # Start workflow
      {:ok, pid} =
        Engine.start_link(workflow_module: MultipleApprovalsWorkflow, inputs: %{})

      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for first approval
      Process.sleep(100)
      status = Engine.get_status(pid)
      assert status.state == :waiting_for_approval
      assert status.approval_data == %{stage: "first_approval"}

      # Approve first
      {:ok, :approved} = Approval.approve(pid, %{stage: 1})

      # Wait for second approval
      Process.sleep(100)
      status = Engine.get_status(pid)
      assert status.state == :waiting_for_approval
      assert status.approval_data == %{stage: "second_approval"}

      # Approve second
      {:ok, :approved} = Approval.approve(pid, %{stage: 2})

      # Wait for completion
      Process.sleep(100)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Should be completed
      status = Engine.get_status(pid)
      assert status.state == :completed

      # Check all steps completed
      assert Map.has_key?(status.results, :step1)
      assert Map.has_key?(status.results, :approval1)
      assert Map.has_key?(status.results, :step2)
      assert Map.has_key?(status.results, :approval2)
      assert Map.has_key?(status.results, :step3)

      # Check events - should have 2 approval requested and 2 approval received
      {:ok, events} = EventStore.get_events(execution_id)

      approval_requested_events =
        Enum.filter(events, fn e -> e.event_type == "ApprovalRequestedEvent" end)

      approval_received_events =
        Enum.filter(events, fn e -> e.event_type == "ApprovalReceivedEvent" end)

      assert length(approval_requested_events) == 2
      assert length(approval_received_events) == 2
    end

    test "status during approval shows approval information" do
      # Start workflow
      {:ok, pid} = Engine.start_link(workflow_module: SimpleApprovalWorkflow, inputs: %{})

      # Wait for approval state
      Process.sleep(100)

      # Get status while waiting for approval
      status = Engine.get_status(pid)

      if status.state == :waiting_for_approval do
        # Should have approval information
        assert Map.has_key?(status, :approval_type)
        assert Map.has_key?(status, :approval_data)
        assert Map.has_key?(status, :approval_step_name)
        assert Map.has_key?(status, :approval_elapsed_ms)

        assert status.approval_type == :manual
        assert status.approval_data == %{message: "Please review this workflow"}
        assert status.approval_step_name == :wait_for_approval
        assert status.approval_elapsed_ms > 0
      end

      # Approve and complete
      Approval.approve(pid)
      Process.sleep(100)
      EventStore.flush()
      Process.sleep(50)

      # Should be completed
      status = Engine.get_status(pid)
      assert status.state == :completed
    end

    test "Approval.waiting_for_approval?/1 detects approval state" do
      # Start workflow
      {:ok, pid} = Engine.start_link(workflow_module: SimpleApprovalWorkflow, inputs: %{})

      # Wait for approval state
      Process.sleep(100)

      # Should be waiting for approval
      assert Approval.waiting_for_approval?(pid) == true

      # Approve
      Approval.approve(pid)

      # Wait for completion
      Process.sleep(100)
      EventStore.flush()
      Process.sleep(50)

      # Should no longer be waiting for approval
      assert Approval.waiting_for_approval?(pid) == false
    end

    test "Approval.get_info/1 returns approval details" do
      # Start workflow
      {:ok, pid} = Engine.start_link(workflow_module: SimpleApprovalWorkflow, inputs: %{})

      # Wait for approval state
      Process.sleep(100)

      # Get approval info
      {:ok, info} = Approval.get_info(pid)

      assert info.approval_type == :manual
      assert info.approval_data == %{message: "Please review this workflow"}
      assert info.approval_step_name == :wait_for_approval
      assert info.approval_elapsed_ms > 0
      assert info.approval_timeout_ms == nil
      assert info.approval_remaining_ms == nil

      # Approve and complete
      Approval.approve(pid)
      Process.sleep(100)
      EventStore.flush()
      Process.sleep(50)

      # Should return error when not waiting for approval
      assert Approval.get_info(pid) == {:error, :not_waiting_for_approval}
    end
  end
end

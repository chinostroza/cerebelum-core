defmodule Cerebelum.Execution.Approval do
  @moduledoc """
  Public API for interacting with workflow approval requests.

  This module provides functions to approve or reject approval requests
  from workflows that are in the :waiting_for_approval state.

  ## Usage

      # In a workflow step
      def review_document(_ctx, {:ok, document}) do
        {:wait_for_approval,
         [type: :manual, timeout_minutes: 60],
         %{document_id: document.id, user: "manager"}}
      end

      # In your application code
      {:ok, pid} = Engine.start_link(workflow_module: MyWorkflow, inputs: %{})

      # Wait for approval state
      Process.sleep(100)
      status = Engine.get_status(pid)
      # => %{state: :waiting_for_approval, ...}

      # Approve the request
      Approval.approve(pid, %{approved_by: "Alice", notes: "Looks good"})
      # => {:ok, :approved}

      # Or reject it
      Approval.reject(pid, "Document incomplete")
      # => {:ok, :rejected}
  """

  alias Cerebelum.Execution.Engine

  @doc """
  Approves a pending approval request.

  ## Parameters

  - `pid` - The execution engine process ID
  - `approval_response` - Optional approval data/metadata (default: %{})

  ## Returns

  - `{:ok, :approved}` - Approval was successful
  - `{:error, reason}` - If the execution is not waiting for approval

  ## Examples

      Approval.approve(pid)
      #=> {:ok, :approved}

      Approval.approve(pid, %{approved_by: "Alice", timestamp: DateTime.utc_now()})
      #=> {:ok, :approved}
  """
  @spec approve(pid(), map()) :: {:ok, :approved} | {:error, term()}
  def approve(pid, approval_response \\ %{}) do
    :gen_statem.call(pid, {:approve, approval_response})
  end

  @doc """
  Rejects a pending approval request.

  ## Parameters

  - `pid` - The execution engine process ID
  - `rejection_reason` - Reason for rejection (string or any term)

  ## Returns

  - `{:ok, :rejected}` - Rejection was successful
  - `{:error, reason}` - If the execution is not waiting for approval

  ## Examples

      Approval.reject(pid, "Document is incomplete")
      #=> {:ok, :rejected}

      Approval.reject(pid, %{reason: "Missing signatures", rejected_by: "Bob"})
      #=> {:ok, :rejected}
  """
  @spec reject(pid(), term()) :: {:ok, :rejected} | {:error, term()}
  def reject(pid, rejection_reason) do
    :gen_statem.call(pid, {:reject, rejection_reason})
  end

  @doc """
  Checks if an execution is currently waiting for approval.

  ## Parameters

  - `pid` - The execution engine process ID

  ## Returns

  - `true` - If the execution is in :waiting_for_approval state
  - `false` - Otherwise

  ## Examples

      Approval.waiting_for_approval?(pid)
      #=> true
  """
  @spec waiting_for_approval?(pid()) :: boolean()
  def waiting_for_approval?(pid) do
    status = Engine.get_status(pid)
    status.state == :waiting_for_approval
  end

  @doc """
  Gets information about the pending approval request.

  ## Parameters

  - `pid` - The execution engine process ID

  ## Returns

  - `{:ok, approval_info}` - Map with approval details
  - `{:error, :not_waiting_for_approval}` - If not in approval state

  ## Examples

      Approval.get_info(pid)
      #=> {:ok, %{
      #     approval_type: :manual,
      #     approval_data: %{document_id: 123},
      #     approval_step_name: :review_document,
      #     approval_elapsed_ms: 5432
      #   }}
  """
  @spec get_info(pid()) :: {:ok, map()} | {:error, :not_waiting_for_approval}
  def get_info(pid) do
    status = Engine.get_status(pid)

    if status.state == :waiting_for_approval do
      {:ok,
       %{
         approval_type: status.approval_type,
         approval_data: status.approval_data,
         approval_step_name: status.approval_step_name,
         approval_timeout_ms: status.approval_timeout_ms,
         approval_elapsed_ms: status.approval_elapsed_ms,
         approval_remaining_ms: status.approval_remaining_ms
       }}
    else
      {:error, :not_waiting_for_approval}
    end
  end
end

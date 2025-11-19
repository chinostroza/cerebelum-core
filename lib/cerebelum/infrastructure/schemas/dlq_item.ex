defmodule Cerebelum.Infrastructure.Schemas.DLQItem do
  @moduledoc """
  Ecto schema for Dead Letter Queue items.

  Represents tasks that have failed after maximum retry attempts.
  These items require manual intervention for retry or resolution.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "dlq_items" do
    field :task_id, :string
    field :execution_id, :string
    field :workflow_module, :string
    field :step_name, :string
    field :error_kind, :string
    field :error_message, :string
    field :error_stacktrace, :string
    field :retry_count, :integer
    field :task_inputs, :map
    field :task_context, :map
    field :status, :string, default: "pending"
    field :resolved_at, :utc_datetime
    field :resolved_by, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating DLQ items.
  """
  def changeset(dlq_item, attrs) do
    dlq_item
    |> cast(attrs, [
      :task_id,
      :execution_id,
      :workflow_module,
      :step_name,
      :error_kind,
      :error_message,
      :error_stacktrace,
      :retry_count,
      :task_inputs,
      :task_context,
      :status,
      :resolved_at,
      :resolved_by
    ])
    |> validate_required([:task_id, :execution_id, :workflow_module, :step_name, :retry_count])
    |> validate_inclusion(:status, ["pending", "retried", "resolved", "failed"])
  end
end

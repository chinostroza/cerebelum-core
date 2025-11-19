defmodule Cerebelum.Repo.Migrations.CreateDlqItemsTable do
  use Ecto.Migration

  def change do
    create table(:dlq_items, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :task_id, :string, null: false
      add :execution_id, :string, null: false
      add :workflow_module, :string, null: false
      add :step_name, :string, null: false
      add :error_kind, :string
      add :error_message, :text
      add :error_stacktrace, :text
      add :retry_count, :integer, null: false
      add :task_inputs, :map
      add :task_context, :map
      add :status, :string, default: "pending", null: false
      add :resolved_at, :utc_datetime
      add :resolved_by, :string

      timestamps(type: :utc_datetime)
    end

    create index(:dlq_items, [:execution_id])
    create index(:dlq_items, [:workflow_module])
    create index(:dlq_items, [:status])
    create index(:dlq_items, [:inserted_at])
  end
end

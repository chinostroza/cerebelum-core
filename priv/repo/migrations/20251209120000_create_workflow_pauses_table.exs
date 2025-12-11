defmodule Cerebelum.Repo.Migrations.CreateWorkflowPausesTable do
  use Ecto.Migration

  @moduledoc """
  Creates the workflow_pauses table for tracking hibernated workflows.

  This table enables Phase 2 of workflow resurrection by storing metadata
  about paused workflows that have been hibernated (process terminated)
  to save memory during long sleeps or approval waits.

  ## Purpose

  - Track workflows that are sleeping or waiting for approval
  - Enable resurrection via external scheduler (WorkflowScheduler)
  - Optimize memory usage for long-running workflows
  - Provide fast lookup for workflows ready to resume

  ## Performance

  - Partial index on resume_at for fast scheduler queries (<5ms)
  - Unique index on execution_id to prevent duplicates
  - Optimized for 10K+ paused workflows
  """

  def up do
    # Create workflow_pauses table
    create table(:workflow_pauses, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :execution_id, :text, null: false
      add :workflow_module, :text, null: false
      add :pause_type, :text, null: false  # 'sleep' | 'approval'
      add :resume_at, :utc_datetime, null: false
      add :hibernated, :boolean, default: false, null: false

      # State reconstruction metadata
      add :event_version, :integer, null: false
      add :current_step_index, :integer, null: false
      add :current_step_name, :text, null: false

      # Sleep-specific fields
      add :sleep_duration_ms, :integer
      add :sleep_started_at, :utc_datetime

      # Approval-specific fields
      add :approval_type, :text
      add :approval_timeout_ms, :integer

      # Resurrection tracking
      add :resurrection_attempts, :integer, default: 0, null: false
      add :last_resurrection_error, :text

      timestamps()
    end

    # CRITICAL: Partial index for scheduler queries
    # Only indexes non-hibernated workflows that are ready to resume
    # This makes the scheduler query extremely fast even with 10K+ paused workflows
    execute """
    CREATE INDEX workflow_pauses_resume_at_idx
    ON workflow_pauses (resume_at)
    WHERE hibernated = false
    """

    # Unique index to prevent duplicate pause records
    create unique_index(:workflow_pauses, [:execution_id])

    # Index for finding workflows by type (useful for monitoring)
    create index(:workflow_pauses, [:pause_type])

    # Index for finding hibernated workflows (useful for metrics)
    create index(:workflow_pauses, [:hibernated])
  end

  def down do
    drop table(:workflow_pauses)
  end
end

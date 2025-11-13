defmodule Cerebelum.Repo.Migrations.CreateEventsTable do
  use Ecto.Migration

  @moduledoc """
  Creates the events table with 64 hash partitions.

  This migration implements Req 20.49-20.52 from the requirements:
  - 64-partition event store for horizontal scaling
  - Hash partitioning by execution_id for automatic routing
  - Independent indexes per partition for optimal query performance

  ## Partitioning Strategy

  PostgreSQL hash partitioning automatically routes queries to the correct
  partition based on execution_id. This provides:

  - Even distribution of events across partitions
  - No hot partitions (balanced load)
  - Single-partition queries for p95 <5ms latency (Req 20.55)
  - Parallel writes to different partitions

  ## Performance Characteristics

  - Single execution query: p95 <5ms (single partition scan)
  - Batch insert: 640K events/sec target (Req 20.16)
  - Independent partition maintenance (VACUUM, ANALYZE)
  - Partition-specific statistics for optimal query plans
  """

  def up do
    # Req 20.49: Create partitioned parent table
    # Hash partitioning by execution_id ensures automatic routing
    # Note: PRIMARY KEY must include partition key (execution_id)
    execute """
    CREATE TABLE events (
      id UUID DEFAULT gen_random_uuid(),
      execution_id TEXT NOT NULL,
      event_type TEXT NOT NULL,
      event_data JSONB NOT NULL,
      version INTEGER NOT NULL,
      inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
      PRIMARY KEY (execution_id, id)
    ) PARTITION BY HASH (execution_id)
    """

    # Req 20.49, 20.52: Create 64 partitions with independent indexes
    # Each partition is a separate table for optimal performance
    for partition <- 0..63 do
      # Create partition table
      execute """
      CREATE TABLE events_#{partition}
      PARTITION OF events
      FOR VALUES WITH (MODULUS 64, REMAINDER #{partition})
      """

      # Req 20.52: Independent index on execution_id per partition
      # This enables fast single-execution queries
      execute """
      CREATE INDEX events_#{partition}_execution_id_idx
      ON events_#{partition}(execution_id)
      """

      # Req 20.52: Unique constraint on (execution_id, version)
      # Ensures event ordering and prevents duplicate versions
      execute """
      CREATE UNIQUE INDEX events_#{partition}_execution_id_version_idx
      ON events_#{partition}(execution_id, version)
      """

      # Req 20.55: Index on timestamp for time-range queries
      # Used for debugging and analytics
      execute """
      CREATE INDEX events_#{partition}_inserted_at_idx
      ON events_#{partition}(inserted_at DESC)
      """

      # Index on event_type for filtering by event type
      execute """
      CREATE INDEX events_#{partition}_event_type_idx
      ON events_#{partition}(event_type)
      """
    end

    # Add comments for documentation
    execute """
    COMMENT ON TABLE events IS
    '64-partition event store for workflow execution events.
    Hash partitioned by execution_id for automatic routing and load balancing.'
    """

    execute """
    COMMENT ON COLUMN events.execution_id IS
    'Workflow execution ID - partition key for automatic routing'
    """

    execute """
    COMMENT ON COLUMN events.version IS
    'Event version number for ordering and optimistic concurrency control'
    """
  end

  def down do
    # Drop all partition tables (this also drops their indexes)
    for partition <- 0..63 do
      execute "DROP TABLE IF EXISTS events_#{partition}"
    end

    # Drop parent table
    execute "DROP TABLE IF EXISTS events"
  end
end

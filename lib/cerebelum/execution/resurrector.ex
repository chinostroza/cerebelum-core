defmodule Cerebelum.Execution.Resurrector do
  @moduledoc """
  Automatic resurrection of paused workflows on system boot.

  This GenServer scans for workflows that were paused (sleeping or waiting
  for approval) when the system was last shut down, and automatically
  resumes them.

  ## Features

  - Boot-time resurrection of paused workflows
  - Parallel resurrection (max 10 concurrent)
  - Manual trigger via resurrect_all/0
  - Telemetry events for monitoring
  - Automatic deduplication (via Registry)

  ## How It Works

  1. On init, waits 1 second for system stabilization
  2. Queries events table for SleepStartedEvent/ApprovalRequestedEvent
  3. Filters out completed/failed executions
  4. Reconstructs state and resumes each execution
  5. Emits telemetry with success/failure counts

  ## SQL Query

  The resurrector finds paused executions using this logic:

  ```sql
  SELECT DISTINCT execution_id
  FROM events
  WHERE event_type IN ('SleepStartedEvent', 'ApprovalRequestedEvent')
    AND execution_id NOT IN (
      SELECT execution_id
      FROM events
      WHERE event_type IN ('SleepCompletedEvent', 'ApprovalReceivedEvent',
                           'ExecutionCompletedEvent', 'ExecutionFailedEvent')
    )
  ORDER BY inserted_at DESC
  LIMIT 1000
  ```

  ## Usage

      # Automatic resurrection on boot
      # (happens automatically when started in supervision tree)

      # Manual trigger
      Resurrector.resurrect_all()

      # Get stats
      Resurrector.get_stats()
  """

  use GenServer
  require Logger

  alias Cerebelum.Execution.Supervisor, as: ExecutionSupervisor
  alias Cerebelum.Repo

  @resurrection_delay_ms 1_000  # Wait 1s after boot before resurrecting
  @max_concurrent_resurrections 10  # Parallel resurrection limit

  defmodule State do
    @moduledoc false
    defstruct [
      :last_resurrection_at,
      resurrection_count: 0,
      success_count: 0,
      failure_count: 0
    ]
  end

  ## Public API

  @doc """
  Starts the Resurrector GenServer.

  This is called automatically by the supervision tree.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually triggers resurrection of all paused workflows.

  Useful for debugging or manual recovery.

  ## Examples

      {:ok, stats} = Resurrector.resurrect_all()
      #=> {:ok, %{total: 10, success: 9, failure: 1, duration_ms: 1234}}
  """
  @spec resurrect_all() :: {:ok, map()}
  def resurrect_all do
    GenServer.call(__MODULE__, :resurrect_all, :infinity)
  end

  @doc """
  Gets resurrection statistics.

  ## Examples

      Resurrector.get_stats()
      #=> %{
      #     last_resurrection_at: ~U[2024-12-09 10:30:00Z],
      #     resurrection_count: 5,
      #     success_count: 4,
      #     failure_count: 1
      #   }
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    # Don't start resurrector in test environment
    if Mix.env() == :test do
      Logger.debug("Resurrector disabled in test environment")
      :ignore
    else
      Logger.info("Resurrector started, will scan for paused workflows in #{@resurrection_delay_ms}ms")

      # Schedule initial resurrection after delay
      Process.send_after(self(), :resurrect, @resurrection_delay_ms)

      {:ok, %State{}}
    end
  end

  @impl true
  def handle_info(:resurrect, state) do
    Logger.info("Starting automatic workflow resurrection...")

    start_time = System.monotonic_time(:millisecond)
    {success_count, failure_count, total} = perform_resurrection()
    duration_ms = System.monotonic_time(:millisecond) - start_time

    Logger.info(
      "Resurrection completed: #{success_count}/#{total} succeeded, #{failure_count} failed (#{duration_ms}ms)"
    )

    # Emit telemetry
    :telemetry.execute(
      [:cerebelum, :resurrector, :scan_completed],
      %{duration_ms: duration_ms, total: total, success: success_count, failure: failure_count},
      %{}
    )

    new_state = %{state |
      last_resurrection_at: DateTime.utc_now(),
      resurrection_count: state.resurrection_count + 1,
      success_count: state.success_count + success_count,
      failure_count: state.failure_count + failure_count
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:resurrect_all, _from, state) do
    start_time = System.monotonic_time(:millisecond)
    {success_count, failure_count, total} = perform_resurrection()
    duration_ms = System.monotonic_time(:millisecond) - start_time

    stats = %{
      total: total,
      success: success_count,
      failure: failure_count,
      duration_ms: duration_ms
    }

    new_state = %{state |
      last_resurrection_at: DateTime.utc_now(),
      resurrection_count: state.resurrection_count + 1,
      success_count: state.success_count + success_count,
      failure_count: state.failure_count + failure_count
    }

    {:reply, {:ok, stats}, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      last_resurrection_at: state.last_resurrection_at,
      resurrection_count: state.resurrection_count,
      success_count: state.success_count,
      failure_count: state.failure_count
    }

    {:reply, stats, state}
  end

  ## Private Functions

  # Performs the resurrection process
  defp perform_resurrection do
    # Find resumable executions
    resumable_executions = find_resumable_executions()
    total = length(resumable_executions)

    if total == 0 do
      Logger.info("No paused workflows found to resurrect")
      {0, 0, 0}
    else
      Logger.info("Found #{total} paused workflows to resurrect")

      # Resurrect in parallel with max concurrency
      results =
        Task.async_stream(
          resumable_executions,
          &attempt_resurrect/1,
          max_concurrency: @max_concurrent_resurrections,
          timeout: 30_000  # 30s timeout per resurrection
        )
        |> Enum.to_list()

      # Count successes and failures
      {success_count, failure_count} = count_results(results)

      {success_count, failure_count, total}
    end
  end

  # Finds executions that need resurrection
  defp find_resumable_executions do
    query = """
    SELECT DISTINCT execution_id
    FROM events
    WHERE event_type IN ('SleepStartedEvent', 'ApprovalRequestedEvent')
      AND execution_id NOT IN (
        SELECT DISTINCT execution_id
        FROM events
        WHERE event_type IN (
          'SleepCompletedEvent',
          'ApprovalReceivedEvent',
          'ApprovalRejectedEvent',
          'ApprovalTimeoutEvent',
          'ExecutionCompletedEvent',
          'ExecutionFailedEvent'
        )
      )
    LIMIT 1000
    """

    case Repo.query(query, []) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [execution_id] -> execution_id end)

      {:error, reason} ->
        Logger.error("Failed to query resumable executions: #{inspect(reason)}")
        []
    end
  end

  # Attempts to resurrect a single execution
  defp attempt_resurrect(execution_id) do
    Logger.debug("Attempting to resurrect execution: #{execution_id}")

    case ExecutionSupervisor.resume_execution(execution_id) do
      {:ok, _pid} ->
        Logger.info("Successfully resurrected execution: #{execution_id}")

        :telemetry.execute(
          [:cerebelum, :resurrector, :resurrection_success],
          %{count: 1},
          %{execution_id: execution_id}
        )

        {:ok, execution_id}

      {:error, :already_running} ->
        # Already running - this is fine, just skip
        Logger.debug("Execution #{execution_id} already running, skipping")
        {:ok, execution_id}

      {:error, :not_resumable} ->
        # Not resumable (completed/failed) - expected, skip
        Logger.debug("Execution #{execution_id} not resumable, skipping")
        {:ok, execution_id}

      {:error, reason} ->
        Logger.warning("Failed to resurrect execution #{execution_id}: #{inspect(reason)}")

        :telemetry.execute(
          [:cerebelum, :resurrector, :resurrection_failure],
          %{count: 1},
          %{execution_id: execution_id, reason: inspect(reason)}
        )

        {:error, {execution_id, reason}}
    end
  end

  # Counts success and failure results
  defp count_results(results) do
    Enum.reduce(results, {0, 0}, fn
      {:ok, {:ok, _execution_id}}, {success, failure} ->
        {success + 1, failure}

      {:ok, {:error, _}}, {success, failure} ->
        {success, failure + 1}

      {:exit, _reason}, {success, failure} ->
        {success, failure + 1}

      _, {success, failure} ->
        {success, failure + 1}
    end)
  end
end

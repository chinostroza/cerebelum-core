defmodule Cerebelum.Infrastructure.WorkflowScheduler do
  @moduledoc """
  External scheduler for resurrecting hibernated workflows.

  This GenServer periodically scans the workflow_pauses table for workflows
  that are ready to resume (resume_at <= NOW) and resurrects them using the
  Execution.Supervisor.resume_execution/1 API.

  ## Features

  - Periodic scanning (default: every 30 seconds)
  - Parallel resurrection (max 10 concurrent)
  - Automatic retry with max attempts
  - DLQ integration for failed resurrections
  - Telemetry events for monitoring
  - Manual trigger via force_scan/0

  ## Performance

  - Query time: <5ms (partial index on resume_at)
  - Batch size: 100 workflows per scan
  - Scan interval: 30s (configurable)
  - Expected throughput: 200 resurrections/minute

  ## Configuration

      # config/config.exs
      config :cerebelum_core,
        resurrection_scan_interval_ms: 30_000,
        enable_workflow_resurrection: true,
        max_resurrection_attempts: 3

  ## Usage

      # Automatic scanning (on boot)
      # (happens automatically when started in supervision tree)

      # Manual trigger
      WorkflowScheduler.force_scan()

      # Get metrics
      WorkflowScheduler.get_metrics()
  """

  use GenServer
  require Logger

  alias Cerebelum.Execution.Supervisor, as: ExecutionSupervisor
  alias Cerebelum.Persistence.WorkflowPause
  alias Cerebelum.Infrastructure.DLQ

  @max_concurrent_resurrections 10
  @default_scan_interval_ms 30_000

  defmodule State do
    @moduledoc false
    defstruct [
      :scan_timer_ref,
      :scan_interval_ms,
      resurrection_count: 0,
      last_scan_at: nil,
      last_scan_duration_ms: 0,
      total_success: 0,
      total_failures: 0
    ]
  end

  ## Public API

  @doc """
  Starts the WorkflowScheduler GenServer.

  This is called automatically by the supervision tree.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually triggers a scan for paused workflows.

  Useful for testing or manual recovery.

  ## Examples

      {:ok, stats} = WorkflowScheduler.force_scan()
      #=> {:ok, %{scanned: 10, resurrected: 9, failed: 1, duration_ms: 1234}}
  """
  @spec force_scan() :: {:ok, map()}
  def force_scan do
    GenServer.call(__MODULE__, :force_scan, :infinity)
  end

  @doc """
  Gets scheduler metrics.

  ## Examples

      WorkflowScheduler.get_metrics()
      #=> %{
      #     resurrection_count: 5,
      #     last_scan_at: ~U[2024-12-09 10:30:00Z],
      #     last_scan_duration_ms: 45,
      #     total_success: 100,
      #     total_failures: 5
      #   }
  """
  @spec get_metrics() :: map()
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    # Don't start scheduler in test environment
    if Mix.env() == :test do
      Logger.debug("WorkflowScheduler disabled in test environment")
      :ignore
    else
      # Check if resurrection is enabled
      if resurrection_enabled?() do
        scan_interval_ms = get_scan_interval_ms()

        Logger.info(
          "WorkflowScheduler started, will scan every #{scan_interval_ms}ms"
        )

        # Schedule first scan
        timer_ref = schedule_next_scan(scan_interval_ms)

        {:ok,
         %State{
           scan_timer_ref: timer_ref,
           scan_interval_ms: scan_interval_ms
         }}
      else
        Logger.info("WorkflowScheduler disabled (resurrection not enabled)")
        :ignore
      end
    end
  end

  @impl true
  def handle_info(:scan_paused_workflows, state) do
    Logger.debug("Starting periodic scan for paused workflows...")

    start_time = System.monotonic_time(:millisecond)
    stats = scan_and_resurrect()
    duration_ms = System.monotonic_time(:millisecond) - start_time

    if stats.scanned > 0 do
      Logger.info(
        "Scan completed: #{stats.resurrected}/#{stats.scanned} succeeded, " <>
          "#{stats.failed} failed (#{duration_ms}ms)"
      )
    end

    # Emit telemetry
    :telemetry.execute(
      [:cerebelum, :scheduler, :scan_completed],
      %{
        duration_ms: duration_ms,
        paused_count: stats.scanned,
        resurrected: stats.resurrected,
        failed: stats.failed
      },
      %{}
    )

    # Schedule next scan
    timer_ref = schedule_next_scan(state.scan_interval_ms)

    new_state = %{
      state
      | scan_timer_ref: timer_ref,
        last_scan_at: DateTime.utc_now(),
        last_scan_duration_ms: duration_ms,
        resurrection_count: state.resurrection_count + 1,
        total_success: state.total_success + stats.resurrected,
        total_failures: state.total_failures + stats.failed
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:force_scan, _from, state) do
    Logger.info("Manual scan triggered...")

    start_time = System.monotonic_time(:millisecond)
    stats = scan_and_resurrect()
    duration_ms = System.monotonic_time(:millisecond) - start_time

    result = %{
      scanned: stats.scanned,
      resurrected: stats.resurrected,
      failed: stats.failed,
      duration_ms: duration_ms
    }

    new_state = %{
      state
      | last_scan_at: DateTime.utc_now(),
        last_scan_duration_ms: duration_ms,
        resurrection_count: state.resurrection_count + 1,
        total_success: state.total_success + stats.resurrected,
        total_failures: state.total_failures + stats.failed
    }

    {:reply, {:ok, result}, new_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = %{
      resurrection_count: state.resurrection_count,
      last_scan_at: state.last_scan_at,
      last_scan_duration_ms: state.last_scan_duration_ms,
      total_success: state.total_success,
      total_failures: state.total_failures
    }

    {:reply, metrics, state}
  end

  ## Private Functions

  # Schedules the next scan using Process.send_after
  defp schedule_next_scan(interval_ms) do
    Process.send_after(self(), :scan_paused_workflows, interval_ms)
  end

  # Performs the scan and resurrection process
  defp scan_and_resurrect do
    # Query paused workflows ready for resurrection
    paused_workflows = WorkflowPause.list_ready_for_resurrection(100)
    scanned = length(paused_workflows)

    if scanned == 0 do
      %{scanned: 0, resurrected: 0, failed: 0}
    else
      Logger.debug("Found #{scanned} paused workflows to resurrect")

      # Resurrect in parallel with max concurrency
      results =
        Task.async_stream(
          paused_workflows,
          &resurrect_workflow/1,
          max_concurrency: @max_concurrent_resurrections,
          timeout: 30_000  # 30s timeout per resurrection
        )
        |> Enum.to_list()

      # Count successes and failures
      {resurrected, failed} = count_results(results)

      %{scanned: scanned, resurrected: resurrected, failed: failed}
    end
  end

  # Attempts to resurrect a single workflow
  defp resurrect_workflow(pause_record) do
    Logger.debug("Attempting to resurrect #{pause_record.execution_id}")

    case ExecutionSupervisor.resume_execution(pause_record.execution_id) do
      {:ok, _pid} ->
        # Success - delete pause record
        Logger.info("Successfully resurrected #{pause_record.execution_id}")

        WorkflowPause.delete(pause_record.id)

        :telemetry.execute(
          [:cerebelum, :scheduler, :resurrection_success],
          %{count: 1},
          %{
            execution_id: pause_record.execution_id,
            pause_type: pause_record.pause_type,
            pause_duration_ms: calculate_pause_duration(pause_record)
          }
        )

        {:ok, pause_record.execution_id}

      {:error, :already_running} ->
        # Already running - delete pause record (stale)
        Logger.debug("#{pause_record.execution_id} already running, cleaning up")
        WorkflowPause.delete(pause_record.id)
        {:ok, pause_record.execution_id}

      {:error, :not_resumable} ->
        # Not resumable (completed/failed) - delete pause record
        Logger.debug("#{pause_record.execution_id} not resumable, cleaning up")
        WorkflowPause.delete(pause_record.id)
        {:ok, pause_record.execution_id}

      {:error, reason} ->
        # Resurrection failed - handle retry or DLQ
        handle_resurrection_failure(pause_record, reason)
    end
  end

  # Handles resurrection failure with retry logic
  defp handle_resurrection_failure(pause_record, reason) do
    max_attempts = Application.get_env(:cerebelum_core, :max_resurrection_attempts, 3)
    error_message = inspect(reason)

    Logger.warning(
      "Failed to resurrect #{pause_record.execution_id} (attempt #{pause_record.resurrection_attempts + 1}/#{max_attempts}): #{error_message}"
    )

    # Increment attempts
    WorkflowPause.increment_resurrection_attempts(pause_record.id, error_message)

    if pause_record.resurrection_attempts + 1 >= max_attempts do
      # Max attempts reached - move to DLQ
      Logger.error(
        "Max resurrection attempts reached for #{pause_record.execution_id}, moving to DLQ"
      )

      DLQ.add_to_dlq(
        %{
          type: "resurrection_failure",
          execution_id: pause_record.execution_id,
          workflow_module: pause_record.workflow_module,
          pause_type: pause_record.pause_type,
          attempts: pause_record.resurrection_attempts + 1,
          pause_record: Map.from_struct(pause_record)
        },
        error_message
      )

      # Delete pause record after moving to DLQ
      WorkflowPause.delete(pause_record.id)
    end

    :telemetry.execute(
      [:cerebelum, :scheduler, :resurrection_failure],
      %{count: 1},
      %{execution_id: pause_record.execution_id, reason: error_message}
    )

    {:error, {pause_record.execution_id, reason}}
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

  # Calculates how long the workflow was paused
  defp calculate_pause_duration(pause_record) do
    if pause_record.sleep_started_at do
      DateTime.diff(DateTime.utc_now(), pause_record.sleep_started_at, :millisecond)
    else
      DateTime.diff(DateTime.utc_now(), pause_record.inserted_at, :millisecond)
    end
  end

  # Checks if resurrection is enabled
  defp resurrection_enabled? do
    Application.get_env(:cerebelum_core, :enable_workflow_resurrection, true)
  end

  # Gets scan interval from config
  defp get_scan_interval_ms do
    Application.get_env(:cerebelum_core, :resurrection_scan_interval_ms, @default_scan_interval_ms)
  end
end

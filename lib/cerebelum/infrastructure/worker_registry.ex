defmodule Cerebelum.Infrastructure.WorkerRegistry do
  @moduledoc """
  Manages the pool of registered SDK workers with health monitoring.
  
  Responsibilities:
  - Track registered workers with metadata (language, capabilities, status)
  - Monitor worker health via heartbeats
  - Detect and deregister dead workers (3 missed heartbeats = 30s)
  - Provide worker pool status and queries
  - Support graceful worker shutdown (draining)
  
  Workers are stored in an ETS table for fast concurrent lookups.
  """

  use GenServer
  require Logger

  @heartbeat_timeout_ms 30_000  # 30 seconds = 3 missed heartbeats @ 10s interval
  @health_check_interval_ms 10_000  # Check every 10 seconds
  @table_name :worker_registry

  # Client API

  @doc """
  Starts the WorkerRegistry GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new worker with metadata.
  
  ## Parameters
  - worker_id: Unique identifier for the worker
  - metadata: Map containing:
    - language: "kotlin", "typescript", "python"
    - capabilities: List of workflow modules this worker can execute
    - version: SDK version
    - custom metadata
  
  ## Returns
  - {:ok, worker} on success
  - {:error, reason} if worker already registered
  """
  def register_worker(worker_id, metadata) do
    GenServer.call(__MODULE__, {:register, worker_id, metadata})
  end

  @doc """
  Record heartbeat from a worker to update liveness.
  
  ## Parameters
  - worker_id: Worker identifier
  - status: Worker status (:idle, :busy, :draining)
  """
  def heartbeat(worker_id, status \\ :idle) do
    GenServer.cast(__MODULE__, {:heartbeat, worker_id, status})
  end

  @doc """
  Unregister a worker from the pool.
  
  ## Parameters
  - worker_id: Worker to remove
  - reason: Reason for unregistration (e.g., "shutdown", "error")
  """
  def unregister_worker(worker_id, reason \\ "unknown") do
    GenServer.call(__MODULE__, {:unregister, worker_id, reason})
  end

  @doc """
  Get all workers with specified status.
  
  ## Parameters
  - status: :idle, :busy, :draining, or :all (default)
  
  ## Returns
  List of workers matching the status
  """
  def get_workers(status \\ :all) do
    GenServer.call(__MODULE__, {:get_workers, status})
  end

  @doc """
  Get worker by ID.
  
  ## Returns
  - {:ok, worker} if found
  - {:error, :not_found} if worker doesn't exist
  """
  def get_worker(worker_id) do
    case :ets.lookup(@table_name, worker_id) do
      [{^worker_id, worker}] -> {:ok, worker}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Get idle workers that can accept tasks.
  """
  def get_idle_workers do
    GenServer.call(__MODULE__, {:get_workers, :idle})
  end

  @doc """
  Get pool statistics.
  
  ## Returns
  Map with:
  - total: Total registered workers
  - idle: Workers available for tasks
  - busy: Workers currently executing tasks
  - draining: Workers in graceful shutdown
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for fast concurrent reads
    table = :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
    
    # Schedule periodic health checks
    schedule_health_check()
    
    Logger.info("WorkerRegistry started")
    
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:register, worker_id, metadata}, _from, state) do
    case :ets.lookup(@table_name, worker_id) do
      [] ->
        worker = build_worker(worker_id, metadata)
        :ets.insert(@table_name, {worker_id, worker})
        
        Logger.info("Worker registered: #{worker_id} (#{worker.language})")
        {:reply, {:ok, worker}, state}
        
      [{^worker_id, _existing}] ->
        Logger.warning("Worker already registered: #{worker_id}")
        {:reply, {:error, :already_registered}, state}
    end
  end

  @impl true
  def handle_call({:unregister, worker_id, reason}, _from, state) do
    case :ets.lookup(@table_name, worker_id) do
      [{^worker_id, _worker}] ->
        :ets.delete(@table_name, worker_id)
        Logger.info("Worker unregistered: #{worker_id}, reason: #{reason}")
        {:reply, :ok, state}
        
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_workers, status}, _from, state) do
    workers = 
      @table_name
      |> :ets.tab2list()
      |> Enum.map(fn {_id, worker} -> worker end)
      |> filter_by_status(status)
    
    {:reply, workers, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    workers = :ets.tab2list(@table_name) |> Enum.map(fn {_id, w} -> w end)
    
    stats = %{
      total: length(workers),
      idle: count_by_status(workers, :idle),
      busy: count_by_status(workers, :busy),
      draining: count_by_status(workers, :draining)
    }
    
    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:heartbeat, worker_id, status}, state) do
    case :ets.lookup(@table_name, worker_id) do
      [{^worker_id, worker}] ->
        updated_worker = %{worker | 
          last_heartbeat: now(),
          status: status
        }
        :ets.insert(@table_name, {worker_id, updated_worker})
        Logger.debug("Heartbeat received from worker: #{worker_id}")
        
      [] ->
        Logger.warning("Heartbeat from unregistered worker: #{worker_id}")
    end
    
    {:noreply, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    check_worker_health()
    schedule_health_check()
    {:noreply, state}
  end

  # Private Functions

  defp build_worker(worker_id, metadata) do
    %{
      worker_id: worker_id,
      language: Map.get(metadata, :language, "unknown"),
      capabilities: Map.get(metadata, :capabilities, []),
      version: Map.get(metadata, :version, "0.0.0"),
      metadata: Map.get(metadata, :metadata, %{}),
      status: :idle,
      registered_at: now(),
      last_heartbeat: now()
    }
  end

  defp check_worker_health do
    current_time = now()
    timeout_threshold = current_time - div(@heartbeat_timeout_ms, 1000)
    
    dead_workers = 
      @table_name
      |> :ets.tab2list()
      |> Enum.filter(fn {_id, worker} ->
        worker.last_heartbeat < timeout_threshold
      end)
    
    Enum.each(dead_workers, fn {worker_id, worker} ->
      Logger.warning("Worker #{worker_id} is dead (last heartbeat: #{current_time - worker.last_heartbeat}s ago), deregistering")
      :ets.delete(@table_name, worker_id)
      
      # TODO: Trigger task reassignment in P8.3
      # reassign_tasks(worker_id)
    end)
    
    if length(dead_workers) > 0 do
      Logger.info("Deregistered #{length(dead_workers)} dead worker(s)")
    end
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval_ms)
  end

  defp filter_by_status(workers, :all), do: workers
  defp filter_by_status(workers, status) do
    Enum.filter(workers, fn worker -> worker.status == status end)
  end

  defp count_by_status(workers, status) do
    Enum.count(workers, fn worker -> worker.status == status end)
  end

  defp now do
    System.system_time(:second)
  end
end

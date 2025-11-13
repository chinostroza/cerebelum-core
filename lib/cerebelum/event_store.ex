defmodule Cerebelum.EventStore do
  @moduledoc """
  Event Store with batching for high-throughput event persistence.

  This module implements Req 20.14-20.16 from the requirements:
  - Append-only event store with version numbers
  - Batch inserts with <100ms window for performance
  - Target: 640K events/sec throughput

  ## Batching Strategy

  Events are accumulated in memory and flushed in batches every 100ms.
  This provides:
  - High throughput via batch inserts
  - Low latency (<100ms event visibility)
  - Reduced database round-trips
  - Optimal INSERT performance

  ## Partition Routing

  PostgreSQL automatically routes events to the correct partition based
  on execution_id hash. All events for an execution are in the same
  partition, enabling single-partition queries with p95 <5ms latency.

  ## Concurrency Control

  Version numbers provide optimistic concurrency control:
  - Unique constraint on (execution_id, version)
  - Database enforces version ordering
  - Prevents duplicate events and races

  ## Usage

      # Async append (batched)
      EventStore.append(execution_id, event, version)

      # Sync append (immediate)
      EventStore.append_sync(execution_id, event, version)

      # Query events
      {:ok, events} = EventStore.get_events(execution_id)
      {:ok, events} = EventStore.get_events_from_version(execution_id, 5)
  """

  use GenServer
  require Logger
  import Ecto.Query
  alias Cerebelum.Repo
  alias Cerebelum.Persistence.Event

  @batch_flush_interval 100
  @max_batch_size 1000

  defstruct batch: [], timer_ref: nil

  # Client API

  @doc """
  Starts the EventStore GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  @doc """
  Appends an event asynchronously (batched).

  Events are accumulated and flushed every #{@batch_flush_interval}ms.
  Use this for non-critical events where slight delay is acceptable.

  ## Examples

      iex> event = %ExecutionStartedEvent{...}
      iex> EventStore.append("exec-123", event, 0)
      :ok
  """
  @spec append(String.t(), struct(), non_neg_integer()) :: :ok
  def append(execution_id, event, version) do
    GenServer.cast(__MODULE__, {:append, execution_id, event, version})
  end

  @doc """
  Appends an event synchronously (immediate flush).

  Use this for critical events that must be persisted immediately,
  such as ExecutionStartedEvent or ExecutionFailedEvent.

  ## Examples

      iex> event = %ExecutionStartedEvent{...}
      iex> EventStore.append_sync("exec-123", event, 0)
      {:ok, %Event{}}
  """
  @spec append_sync(String.t(), struct(), non_neg_integer()) ::
          {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def append_sync(execution_id, event, version) do
    GenServer.call(__MODULE__, {:append_sync, execution_id, event, version})
  end

  @doc """
  Retrieves all events for an execution, ordered by version.

  PostgreSQL automatically routes query to the correct partition
  based on execution_id hash.

  ## Examples

      iex> EventStore.get_events("exec-123")
      {:ok, [%Event{version: 0}, %Event{version: 1}, ...]}
  """
  @spec get_events(String.t()) :: {:ok, [Event.t()]} | {:error, term()}
  def get_events(execution_id) do
    GenServer.call(__MODULE__, {:get_events, execution_id})
  end

  @doc """
  Retrieves events from a specific version onwards.

  Useful for incremental state reconstruction or tailing events.

  ## Examples

      iex> EventStore.get_events_from_version("exec-123", 5)
      {:ok, [%Event{version: 5}, %Event{version: 6}, ...]}
  """
  @spec get_events_from_version(String.t(), non_neg_integer()) ::
          {:ok, [Event.t()]} | {:error, term()}
  def get_events_from_version(execution_id, from_version) do
    GenServer.call(__MODULE__, {:get_events_from_version, execution_id, from_version})
  end

  @doc """
  Forces immediate flush of pending batch.

  Used for testing or graceful shutdown.
  """
  @spec flush() :: :ok
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  # Server Callbacks

  @impl true
  def init(:ok) do
    {:ok, %__MODULE__{batch: [], timer_ref: nil}}
  end

  @impl true
  def handle_cast({:append, execution_id, event, version}, state) do
    # Add to batch
    event_record = create_event_record(execution_id, event, version)
    new_batch = [event_record | state.batch]

    # Cancel existing timer
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    # Check if batch is full
    if length(new_batch) >= @max_batch_size do
      flush_batch(new_batch)
      {:noreply, %{state | batch: [], timer_ref: nil}}
    else
      # Schedule flush
      timer_ref = Process.send_after(self(), :flush_batch, @batch_flush_interval)
      {:noreply, %{state | batch: new_batch, timer_ref: timer_ref}}
    end
  end

  @impl true
  def handle_call({:append_sync, execution_id, event, version}, _from, state) do
    event_record = create_event_record(execution_id, event, version)

    case insert_event(event_record) do
      {:ok, inserted} -> {:reply, {:ok, inserted}, state}
      {:error, changeset} -> {:reply, {:error, changeset}, state}
    end
  end

  @impl true
  def handle_call({:get_events, execution_id}, _from, state) do
    result =
      Event
      |> where([e], e.execution_id == ^execution_id)
      |> order_by([e], asc: e.version)
      |> Repo.all()

    {:reply, {:ok, result}, state}
  rescue
    e -> {:reply, {:error, e}, state}
  end

  @impl true
  def handle_call({:get_events_from_version, execution_id, from_version}, _from, state) do
    result =
      Event
      |> where([e], e.execution_id == ^execution_id and e.version >= ^from_version)
      |> order_by([e], asc: e.version)
      |> Repo.all()

    {:reply, {:ok, result}, state}
  rescue
    e -> {:reply, {:error, e}, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    if state.batch != [] do
      flush_batch(state.batch)
    end

    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    {:reply, :ok, %{state | batch: [], timer_ref: nil}}
  end

  @impl true
  def handle_info(:flush_batch, state) do
    if state.batch != [] do
      flush_batch(state.batch)
    end

    {:noreply, %{state | batch: [], timer_ref: nil}}
  end

  # Private Helpers

  defp create_event_record(execution_id, event, version) do
    %{
      execution_id: execution_id,
      event_type: event_type(event),
      event_data: serialize(event),
      version: version
    }
  end

  defp event_type(%module{}), do: module |> to_string() |> String.split(".") |> List.last()

  defp serialize(event) do
    event
    |> Map.from_struct()
    |> Map.new(fn {k, v} -> {to_string(k), serialize_value(v)} end)
  end

  defp serialize_value(value) when is_atom(value) and not is_nil(value) do
    to_string(value)
  end

  defp serialize_value(value) when is_tuple(value) do
    # Convert tuples to lists for JSON serialization
    value
    |> Tuple.to_list()
    |> Enum.map(&serialize_value/1)
  end

  defp serialize_value(value) when is_list(value) do
    Enum.map(value, &serialize_value/1)
  end

  defp serialize_value(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {k, v} -> {to_string(k), serialize_value(v)} end)
  end

  defp serialize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp serialize_value(%module{} = struct_value) when is_exception(struct_value) do
    # Convert exceptions to a serializable map
    %{
      "__exception__" => to_string(module),
      "message" => Exception.message(struct_value)
    }
  end

  defp serialize_value(%module{} = struct_value) do
    # For other structs, convert to map with type annotation
    struct_value
    |> Map.from_struct()
    |> Map.put("__struct__", to_string(module))
    |> Map.new(fn {k, v} -> {to_string(k), serialize_value(v)} end)
  end

  defp serialize_value(value), do: value

  defp flush_batch(batch) do
    # Reverse because we prepend to batch
    events = Enum.reverse(batch)

    {count, _} = Repo.insert_all(Event, events, returning: false)
    Logger.debug("Flushed #{count} events to event store")
    :ok
  rescue
    e ->
      Logger.error("Exception flushing batch: #{inspect(e)}")
      :error
  end

  defp insert_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end
end

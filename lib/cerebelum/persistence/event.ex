defmodule Cerebelum.Persistence.Event do
  @moduledoc """
  Ecto schema for event storage in PostgreSQL.

  Events are stored in a 64-partition table for horizontal scaling.
  PostgreSQL automatically routes queries to the correct partition
  based on the execution_id hash.

  ## Schema

  - `id` - UUID primary key
  - `execution_id` - Workflow execution ID (partition key)
  - `event_type` - Event type name (ExecutionStartedEvent, etc)
  - `event_data` - JSONB event payload
  - `version` - Event version number (for ordering)
  - `inserted_at` - Timestamp when event was stored

  ## Partitioning

  The table is hash-partitioned by execution_id across 64 partitions.
  This means:
  - All events for an execution are in the same partition
  - Queries by execution_id hit only one partition
  - Writes distribute evenly across partitions
  - No hot partitions or bottlenecks

  ## Indexes

  Each partition has independent indexes for:
  - execution_id (fast lookup)
  - (execution_id, version) unique (ordering + deduplication)
  - inserted_at (time-range queries)
  - event_type (filtering by type)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          execution_id: String.t() | nil,
          event_type: String.t() | nil,
          event_data: map() | nil,
          version: non_neg_integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "events" do
    field :execution_id, :string
    field :event_type, :string
    field :event_data, :map
    field :version, :integer

    timestamps(updated_at: false)
  end

  @doc """
  Creates a changeset for an event.

  ## Required Fields

  - `:execution_id` - Workflow execution ID
  - `:event_type` - Event type name
  - `:event_data` - Event payload as map
  - `:version` - Event version number

  ## Examples

      iex> changeset = Event.changeset(%Event{}, %{
      ...>   execution_id: "exec-123",
      ...>   event_type: "ExecutionStartedEvent",
      ...>   event_data: %{workflow_module: "MyWorkflow"},
      ...>   version: 0
      ...> })
      iex> changeset.valid?
      true
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    changeset =
      event
      |> cast(attrs, [:execution_id, :event_type, :event_data, :version])
      |> validate_required([:execution_id, :event_type, :event_data, :version])
      |> validate_number(:version, greater_than_or_equal_to: 0)
      |> validate_length(:execution_id, min: 1, max: 255)
      |> validate_length(:event_type, min: 1, max: 255)

    # Add unique constraints for all 64 partitions
    Enum.reduce(0..63, changeset, fn partition, cs ->
      unique_constraint(cs, [:execution_id, :version],
        name: :"events_#{partition}_execution_id_version_idx"
      )
    end)
  end

  @doc """
  Creates a new event struct from domain event.

  ## Examples

      iex> domain_event = %Cerebelum.Events.ExecutionStartedEvent{
      ...>   event_id: "evt-123",
      ...>   execution_id: "exec-123",
      ...>   workflow_module: MyWorkflow,
      ...>   version: 0
      ...> }
      iex> event = Event.from_domain_event(domain_event)
      iex> event.execution_id
      "exec-123"
  """
  @spec from_domain_event(struct()) :: t()
  def from_domain_event(domain_event) do
    %__MODULE__{
      execution_id: domain_event.execution_id,
      event_type: event_type(domain_event),
      event_data: serialize(domain_event),
      version: domain_event.version
    }
  end

  @doc """
  Converts stored event back to domain event struct.

  ## Examples

      iex> stored = %Event{
      ...>   execution_id: "exec-123",
      ...>   event_type: "ExecutionStartedEvent",
      ...>   event_data: %{"workflow_module" => "MyWorkflow"},
      ...>   version: 0
      ...> }
      iex> domain_event = Event.to_domain_event(stored)
      iex> domain_event.__struct__
      Cerebelum.Events.ExecutionStartedEvent
  """
  @spec to_domain_event(t()) :: struct()
  def to_domain_event(event) do
    Cerebelum.Events.deserialize(event.event_type, event.event_data)
  end

  # Private helpers

  defp event_type(%module{}), do: module |> to_string() |> String.split(".") |> List.last()

  defp serialize(event) do
    event
    |> Map.from_struct()
    |> Map.new(fn {k, v} -> {to_string(k), serialize_value(v)} end)
  end

  # Serialize atoms, modules, and other special types
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
end

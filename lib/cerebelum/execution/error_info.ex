defmodule Cerebelum.Execution.ErrorInfo do
  @moduledoc """
  Structured error information for workflow execution failures.

  Provides consistent error representation and formatting across the execution engine.
  """

  @type error_kind :: :exception | :exit | :throw | :timeout
  @type t :: %__MODULE__{
          kind: error_kind(),
          step_name: atom(),
          reason: term(),
          stacktrace: Exception.stacktrace() | nil,
          execution_id: String.t(),
          timestamp: DateTime.t()
        }

  @enforce_keys [:kind, :step_name, :reason, :execution_id]
  defstruct [
    :kind,
    :step_name,
    :reason,
    :stacktrace,
    :execution_id,
    timestamp: nil
  ]

  @doc """
  Creates a new ErrorInfo struct from an exception.

  ## Examples

      iex> error = ErrorInfo.from_exception(:my_step, %RuntimeError{message: "oops"}, [], "exec-123")
      iex> error.kind
      :exception
      iex> error.step_name
      :my_step
  """
  @spec from_exception(atom(), Exception.t(), Exception.stacktrace(), String.t()) :: t()
  def from_exception(step_name, exception, stacktrace, execution_id) do
    %__MODULE__{
      kind: :exception,
      step_name: step_name,
      reason: exception,
      stacktrace: stacktrace,
      execution_id: execution_id,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates a new ErrorInfo struct from an exit signal.

  ## Examples

      iex> error = ErrorInfo.from_exit(:my_step, :normal, "exec-123")
      iex> error.kind
      :exit
  """
  @spec from_exit(atom(), term(), String.t()) :: t()
  def from_exit(step_name, reason, execution_id) do
    %__MODULE__{
      kind: :exit,
      step_name: step_name,
      reason: reason,
      stacktrace: nil,
      execution_id: execution_id,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates a new ErrorInfo struct from a throw.

  ## Examples

      iex> error = ErrorInfo.from_throw(:my_step, {:error, "bad input"}, "exec-123")
      iex> error.kind
      :throw
  """
  @spec from_throw(atom(), term(), String.t()) :: t()
  def from_throw(step_name, reason, execution_id) do
    %__MODULE__{
      kind: :throw,
      step_name: step_name,
      reason: reason,
      stacktrace: nil,
      execution_id: execution_id,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates a new ErrorInfo struct from a timeout.

  ## Examples

      iex> error = ErrorInfo.from_timeout(:slow_step, "exec-123")
      iex> error.kind
      :timeout
  """
  @spec from_timeout(atom(), String.t()) :: t()
  def from_timeout(step_name, execution_id) do
    %__MODULE__{
      kind: :timeout,
      step_name: step_name,
      reason: :timeout,
      stacktrace: nil,
      execution_id: execution_id,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Formats the error as a human-readable string.

  ## Examples

      iex> error = ErrorInfo.from_exception(:step1, %RuntimeError{message: "boom"}, [], "exec-123")
      iex> ErrorInfo.format(error)
      "Exception in step :step1 - RuntimeError: boom"
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = error) do
    case error.kind do
      :exception ->
        exception_message = Exception.message(error.reason)
        exception_type = format_module_name(error.reason.__struct__)
        "Exception in step :#{error.step_name} - #{exception_type}: #{exception_message}"

      :exit ->
        "Exit in step :#{error.step_name} - reason: #{inspect(error.reason)}"

      :throw ->
        "Throw in step :#{error.step_name} - value: #{inspect(error.reason)}"

      :timeout ->
        "Timeout in step :#{error.step_name} - step exceeded maximum execution time"
    end
  end

  @doc """
  Converts error info to a map for serialization.

  ## Examples

      iex> error = ErrorInfo.from_exit(:step1, :killed, "exec-123")
      iex> map = ErrorInfo.to_map(error)
      iex> map.kind
      :exit
      iex> map.step_name
      :step1
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = error) do
    %{
      kind: error.kind,
      step_name: error.step_name,
      reason: serialize_reason(error.reason),
      stacktrace: error.stacktrace,
      execution_id: error.execution_id,
      timestamp: error.timestamp,
      message: format(error)
    }
  end

  # Private helpers

  defp serialize_reason(%{__struct__: _} = exception) do
    %{
      type: exception.__struct__,
      message: Exception.message(exception)
    }
  end

  defp serialize_reason(reason), do: reason

  defp format_module_name(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
  end
end

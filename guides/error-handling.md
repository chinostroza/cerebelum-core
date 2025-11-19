# Error Handling in Cerebelum

## Overview

Cerebelum provides comprehensive error handling for workflow execution failures. All errors are captured, structured, and formatted in a consistent way using the `ErrorInfo` struct.

## Error Types

Cerebelum handles four types of errors:

### 1. Exceptions (`:exception`)

Raised exceptions from workflow step functions.

```elixir
def my_step(_context) do
  raise "Something went wrong"  # Caught as :exception
end
```

**Captured information:**
- Exception struct with message
- Full stacktrace
- Step name where it occurred

### 2. Exit Signals (`:exit`)

Process exits triggered by `exit/1`.

```elixir
def my_step(_context) do
  exit(:shutdown)  # Caught as :exit
end
```

**Captured information:**
- Exit reason
- Step name

### 3. Throws (`:throw`)

Values thrown with `throw/1`.

```elixir
def my_step(_context) do
  throw({:error, :invalid_data})  # Caught as :throw
end
```

**Captured information:**
- Thrown value
- Step name

### 4. Timeouts (`:timeout`)

Step execution exceeding the maximum time limit (5 minutes by default).

**Captured information:**
- Step name
- Timeout duration

## ErrorInfo Struct

All errors are represented as `Cerebelum.Execution.ErrorInfo` structs:

```elixir
%ErrorInfo{
  kind: :exception | :exit | :throw | :timeout,
  step_name: atom(),
  reason: term(),
  stacktrace: list() | nil,
  execution_id: String.t(),
  timestamp: DateTime.t()
}
```

## Getting Error Information

When a workflow fails, you can get detailed error information through the execution status:

```elixir
{:ok, execution} = Cerebelum.execute_workflow(MyWorkflow, %{})

:timer.sleep(100)  # Wait for execution

{:ok, status} = Cerebelum.get_execution_status(execution.id)

if status.state == :failed do
  # Human-readable error message
  IO.puts(status.error_message)
  #=> "Exception in step :process_payment - RuntimeError: Payment gateway timeout"

  # Structured error data
  IO.inspect(status.error)
  #=> %{
  #     kind: :exception,
  #     step_name: :process_payment,
  #     reason: %{type: RuntimeError, message: "Payment gateway timeout"},
  #     stacktrace: [...],
  #     execution_id: "abc-123",
  #     timestamp: ~U[2025-01-15 10:30:00Z],
  #     message: "Exception in step :process_payment - RuntimeError: Payment gateway timeout"
  #   }
end
```

## Error Messages

`ErrorInfo.format/1` generates user-friendly error messages:

```elixir
# Exception
"Exception in step :my_step - RuntimeError: Something went wrong"

# Exit
"Exit in step :my_step - reason: :killed"

# Throw
"Throw in step :my_step - value: {:error, :invalid_data}"

# Timeout
"Timeout in step :my_step - step exceeded maximum execution time"
```

## Best Practices

### 1. Use Descriptive Error Messages

```elixir
# Good
def process_payment(_context, order) do
  if invalid_payment?(order) do
    raise "Payment validation failed: Invalid card number"
  end
end

# Avoid
def process_payment(_context, order) do
  if invalid_payment?(order) do
    raise "Error"  # Too generic
  end
end
```

### 2. Return {:ok, result} or {:error, reason}

For expected errors, prefer returning error tuples:

```elixir
def validate_user(_context, user_data) do
  case validate(user_data) do
    :ok -> {:ok, user_data}
    {:error, reason} -> {:error, reason}  # Handled gracefully
  end
end
```

### 3. Let Unexpected Errors Crash

For truly exceptional situations, let the step fail:

```elixir
def connect_to_database(_context) do
  # If connection fails, let it raise - this is exceptional
  {:ok, conn} = Database.connect()
  {:ok, conn}
end
```

### 4. Check Status After Execution

Always check execution status to handle failures:

```elixir
{:ok, execution} = Cerebelum.execute_workflow(MyWorkflow, inputs)

:timer.sleep(200)  # Wait for completion

case Cerebelum.get_execution_status(execution.id) do
  {:ok, %{state: :completed}} ->
    {:ok, "Workflow completed successfully"}

  {:ok, %{state: :failed, error_message: message}} ->
    Logger.error("Workflow failed: #{message}")
    {:error, message}

  {:error, :not_found} ->
    {:error, "Execution not found"}
end
```

## Logging

Cerebelum logs errors at multiple levels:

- **ERROR** - When step fails with formatted message
- **DEBUG** - Full stacktrace for exceptions
- **ERROR** - When execution transitions to :failed state

Example log output:

```
15:00:00.123 [error] Step process_payment raised exception: Payment gateway timeout
15:00:00.124 [debug] Stacktrace: lib/my_workflow.ex:42: MyWorkflow.process_payment/2
15:00:00.125 [error] Step process_payment failed: Exception in step :process_payment - RuntimeError: Payment gateway timeout
15:00:00.126 [error] Execution abc-123 failed: %ErrorInfo{...}
```

## Error Recovery (Future)

In future phases, Cerebelum will support:

- **Automatic Retries** - Retry failed steps with backoff
- **Diverge Error Handling** - Pattern match on errors and route to recovery steps
- **Manual Intervention** - Pause and allow human intervention
- **Dead Letter Queue** - Store failed executions for later processing

Example (Phase 3+):

```elixir
workflow do
  timeline do
    fetch_data()
    |> process_data()
    |> diverge from: [:process_data] do
      {:error, :rate_limited} -> wait_and_retry()
      {:error, :invalid_data} -> log_and_skip()
      _ -> continue()
    end
  end
end
```

## Testing Error Handling

### Testing Exceptions

```elixir
defmodule FailingWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      failing_step()
    end
  end

  def failing_step(_context) do
    raise "Intentional test failure"
  end
end

test "handles exceptions" do
  {:ok, execution} = Cerebelum.execute_workflow(FailingWorkflow, %{})
  :timer.sleep(100)

  {:ok, status} = Cerebelum.get_execution_status(execution.id)

  assert status.state == :failed
  assert status.error.kind == :exception
  assert status.error.step_name == :failing_step
end
```

### Testing Exits

```elixir
def exiting_step(_context) do
  exit(:shutdown)
end

test "handles exits" do
  {:ok, execution} = Cerebelum.execute_workflow(ExitingWorkflow, %{})
  :timer.sleep(100)

  {:ok, status} = Cerebelum.get_execution_status(execution.id)

  assert status.error.kind == :exit
  assert status.error.reason == :shutdown
end
```

### Testing Timeouts

Timeouts are handled automatically after 5 minutes of step execution.

## API Reference

### ErrorInfo Module

- `from_exception/4` - Create ErrorInfo from exception
- `from_exit/3` - Create ErrorInfo from exit signal
- `from_throw/3` - Create ErrorInfo from throw
- `from_timeout/2` - Create ErrorInfo from timeout
- `format/1` - Format error as human-readable string
- `to_map/1` - Convert error to serializable map

### Status Fields

When calling `Cerebelum.get_execution_status/1` on a failed execution:

```elixir
%{
  state: :failed,
  error: %{...},           # Structured error data (map)
  error_message: "...",    # Human-readable message (string)
  execution_id: "...",
  workflow_module: ...,
  current_step: :step_name,
  results: %{...},         # Results up to failure
  ...
}
```

## Related Documentation

- [Workflow DSL](./dsl.md) - How to define workflows
- [Execution Engine](./execution.md) - How workflows are executed
- [Context](./context.md) - Execution context structure

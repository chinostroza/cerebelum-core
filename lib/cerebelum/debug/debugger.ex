defmodule Cerebelum.Debug.Debugger do
  @moduledoc """
  Interactive step-by-step debugger for workflow executions.

  Allows time-travel debugging by replaying events one at a time,
  inspecting state at each step, and setting breakpoints.

  ## Usage

      # Start debugging an execution
      Cerebelum.Debug.Debugger.start("execution-id-123")

  ## Commands

  - `n` or `next` - Advance to next event
  - `p` or `prev` - Go back to previous event
  - `c` or `continue` - Continue until next breakpoint or end
  - `s` or `show` - Show current state details
  - `b <step>` or `breakpoint <step>` - Set breakpoint on step
  - `bl` or `breakpoints` - List all breakpoints
  - `bc` or `clear` - Clear all breakpoints
  - `j <n>` or `jump <n>` - Jump to event number N
  - `h` or `help` - Show help
  - `q` or `quit` - Exit debugger

  ## Example Session

      > Cerebelum.Debug.Debugger.start("exec-123")

      === Cerebelum Time-Travel Debugger ===
      Execution: exec-123
      Total events: 10

      [1/10] ExecutionStartedEvent
      > show
      State:
        status: :running
        current_step: nil
        results: %{}

      > next
      [2/10] StepExecutedEvent - step1
      > show
      State:
        status: :running
        current_step: :step1
        results: %{step1: {:ok, 1}}

      > breakpoint :step3
      Breakpoint set on step3

      > continue
      [4/10] StepExecutedEvent - step3 [BREAKPOINT]
  """

  require Logger
  alias Cerebelum.EventStore
  alias Cerebelum.Execution.StateReconstructor
  alias Cerebelum.Persistence.Event

  @type debugger_state :: %{
          execution_id: String.t(),
          events: [Event.t()],
          current_index: non_neg_integer(),
          breakpoints: MapSet.t(atom()),
          reconstructed_state: map() | nil
        }

  @doc """
  Starts the interactive debugger for an execution.

  ## Parameters

  - `execution_id` - The execution ID to debug

  ## Returns

  - `:ok` when debugger exits
  - `{:error, reason}` if execution not found
  """
  @spec start(String.t()) :: :ok | {:error, term()}
  def start(execution_id) do
    case EventStore.get_events(execution_id) do
      {:ok, []} ->
        IO.puts("Error: No events found for execution #{execution_id}")
        {:error, :not_found}

      {:ok, events} ->
        print_header(execution_id, length(events))

        state = %{
          execution_id: execution_id,
          events: events,
          current_index: 0,
          breakpoints: MapSet.new(),
          reconstructed_state: nil
        }

        # Show first event
        state = reconstruct_state_at_index(state, 0)
        print_current_event(state)

        # Start REPL
        run_repl(state)

      {:error, reason} ->
        IO.puts("Error loading events: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private Functions

  defp run_repl(state) do
    input = IO.gets("\n> ") |> String.trim()

    case parse_command(input) do
      {:next, _} ->
        handle_next(state)

      {:prev, _} ->
        handle_prev(state)

      {:continue, _} ->
        handle_continue(state)

      {:show, _} ->
        handle_show(state)
        run_repl(state)

      {:breakpoint, step_name} ->
        handle_breakpoint(state, step_name)

      {:list_breakpoints, _} ->
        handle_list_breakpoints(state)
        run_repl(state)

      {:clear_breakpoints, _} ->
        handle_clear_breakpoints(state)

      {:jump, index} ->
        handle_jump(state, index)

      {:help, _} ->
        print_help()
        run_repl(state)

      {:quit, _} ->
        IO.puts("\nExiting debugger.")
        :ok

      {:unknown, cmd} ->
        IO.puts("Unknown command: #{cmd}. Type 'help' for available commands.")
        run_repl(state)

      {:error, msg} ->
        IO.puts("Error: #{msg}")
        run_repl(state)
    end
  end

  defp parse_command(""), do: {:unknown, ""}
  defp parse_command("n"), do: {:next, nil}
  defp parse_command("next"), do: {:next, nil}
  defp parse_command("p"), do: {:prev, nil}
  defp parse_command("prev"), do: {:prev, nil}
  defp parse_command("c"), do: {:continue, nil}
  defp parse_command("continue"), do: {:continue, nil}
  defp parse_command("s"), do: {:show, nil}
  defp parse_command("show"), do: {:show, nil}
  defp parse_command("bl"), do: {:list_breakpoints, nil}
  defp parse_command("breakpoints"), do: {:list_breakpoints, nil}
  defp parse_command("bc"), do: {:clear_breakpoints, nil}
  defp parse_command("clear"), do: {:clear_breakpoints, nil}
  defp parse_command("h"), do: {:help, nil}
  defp parse_command("help"), do: {:help, nil}
  defp parse_command("q"), do: {:quit, nil}
  defp parse_command("quit"), do: {:quit, nil}

  defp parse_command("b " <> step_str) do
    case String.trim(step_str) do
      "" -> {:error, "Please provide a step name"}
      step -> {:breakpoint, String.to_atom(step)}
    end
  end

  defp parse_command("breakpoint " <> step_str) do
    case String.trim(step_str) do
      "" -> {:error, "Please provide a step name"}
      step -> {:breakpoint, String.to_atom(step)}
    end
  end

  defp parse_command("j " <> index_str) do
    case Integer.parse(String.trim(index_str)) do
      {index, _} -> {:jump, index}
      :error -> {:error, "Invalid event number"}
    end
  end

  defp parse_command("jump " <> index_str) do
    case Integer.parse(String.trim(index_str)) do
      {index, _} -> {:jump, index}
      :error -> {:error, "Invalid event number"}
    end
  end

  defp parse_command(cmd), do: {:unknown, cmd}

  defp handle_next(state) do
    new_index = state.current_index + 1

    if new_index >= length(state.events) do
      IO.puts("Already at last event.")
      run_repl(state)
    else
      new_state = reconstruct_state_at_index(state, new_index)
      print_current_event(new_state)
      run_repl(new_state)
    end
  end

  defp handle_prev(state) do
    new_index = state.current_index - 1

    if new_index < 0 do
      IO.puts("Already at first event.")
      run_repl(state)
    else
      new_state = reconstruct_state_at_index(state, new_index)
      print_current_event(new_state)
      run_repl(new_state)
    end
  end

  defp handle_continue(state) do
    if MapSet.size(state.breakpoints) == 0 do
      # No breakpoints, go to end
      final_index = length(state.events) - 1
      new_state = reconstruct_state_at_index(state, final_index)
      print_current_event(new_state)
      IO.puts("\nReached end of execution.")
      run_repl(new_state)
    else
      # Find next breakpoint
      next_bp_index = find_next_breakpoint(state, state.current_index + 1)

      case next_bp_index do
        nil ->
          IO.puts("No more breakpoints. Continuing to end.")
          final_index = length(state.events) - 1
          new_state = reconstruct_state_at_index(state, final_index)
          print_current_event(new_state)
          run_repl(new_state)

        index ->
          new_state = reconstruct_state_at_index(state, index)
          print_current_event(new_state)
          IO.puts("\n⚠️  BREAKPOINT HIT")
          run_repl(new_state)
      end
    end
  end

  defp handle_show(state) do
    if state.reconstructed_state do
      print_detailed_state(state.reconstructed_state)
    else
      IO.puts("No state available. Use 'next' to advance.")
    end
  end

  defp handle_breakpoint(state, step_name) do
    new_breakpoints = MapSet.put(state.breakpoints, step_name)
    IO.puts("Breakpoint set on #{step_name}")

    new_state = %{state | breakpoints: new_breakpoints}
    run_repl(new_state)
  end

  defp handle_list_breakpoints(state) do
    if MapSet.size(state.breakpoints) == 0 do
      IO.puts("No breakpoints set.")
    else
      IO.puts("\nBreakpoints:")

      state.breakpoints
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.each(fn step -> IO.puts("  - #{step}") end)
    end
  end

  defp handle_clear_breakpoints(state) do
    IO.puts("All breakpoints cleared.")
    new_state = %{state | breakpoints: MapSet.new()}
    run_repl(new_state)
  end

  defp handle_jump(state, target_index) do
    # Convert to 0-based (user inputs 1-based)
    index = target_index - 1

    cond do
      index < 0 ->
        IO.puts("Event number must be >= 1")
        run_repl(state)

      index >= length(state.events) ->
        IO.puts("Event number too large (max: #{length(state.events)})")
        run_repl(state)

      true ->
        new_state = reconstruct_state_at_index(state, index)
        print_current_event(new_state)
        run_repl(new_state)
    end
  end

  defp reconstruct_state_at_index(state, index) do
    event = Enum.at(state.events, index)

    # Reconstruct state up to this version
    {:ok, reconstructed} =
      StateReconstructor.reconstruct_to_version(state.execution_id, event.version)

    %{state | current_index: index, reconstructed_state: reconstructed}
  end

  defp find_next_breakpoint(state, start_index) do
    state.events
    |> Enum.drop(start_index)
    |> Enum.with_index(start_index)
    |> Enum.find(fn {event, _index} ->
      domain_event = Event.to_domain_event(event)
      step_name = get_step_name_from_event(domain_event)
      # Convert string step_name to atom for comparison with breakpoints
      step_name && MapSet.member?(state.breakpoints, String.to_existing_atom(step_name))
    end)
    |> case do
      nil -> nil
      {_event, index} -> index
    end
  end

  defp get_step_name_from_event(%{step_name: step_name}) when is_binary(step_name), do: step_name
  defp get_step_name_from_event(_), do: nil

  # Print Functions

  defp print_header(execution_id, total_events) do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("Cerebelum Time-Travel Debugger")
    IO.puts(String.duplicate("=", 60))
    IO.puts("Execution: #{execution_id}")
    IO.puts("Total events: #{total_events}")
    IO.puts("\nType 'help' for available commands")
    IO.puts(String.duplicate("=", 60))
  end

  defp print_current_event(state) do
    event = Enum.at(state.events, state.current_index)
    domain_event = Event.to_domain_event(event)

    position = "[#{state.current_index + 1}/#{length(state.events)}]"
    event_type = event_type_short(domain_event)

    # Check if on breakpoint
    step_name = get_step_name_from_event(domain_event)

    breakpoint_marker =
      if step_name && MapSet.member?(state.breakpoints, step_name) do
        " [BREAKPOINT]"
      else
        ""
      end

    step_info =
      case step_name do
        nil -> ""
        name -> " - #{name}"
      end

    IO.puts("\n#{position} #{event_type}#{step_info}#{breakpoint_marker}")
  end

  defp print_detailed_state(state) do
    IO.puts("\n" <> String.duplicate("-", 60))
    IO.puts("State Details:")
    IO.puts(String.duplicate("-", 60))

    IO.puts("Status: #{state.status}")
    IO.puts("Current Step: #{inspect(state.current_step)}")
    IO.puts("Iteration: #{state.iteration}")
    IO.puts("Events Applied: #{state.events_applied}")

    IO.puts("\nResults:")

    if map_size(state.results) == 0 do
      IO.puts("  (empty)")
    else
      state.results
      |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
      |> Enum.each(fn {step, result} ->
        IO.puts("  #{step}: #{inspect(result, limit: 3, printable_limit: 50)}")
      end)
    end

    if state.error do
      IO.puts("\nError:")
      IO.puts("  Kind: #{state.error.kind}")
      IO.puts("  Step: #{state.error.step_name}")
      IO.puts("  Message: #{state.error.message}")
    end

    IO.puts(String.duplicate("-", 60))
  end

  defp print_help do
    IO.puts("""

    Available Commands:
    ───────────────────────────────────────────────────────────
    n, next              - Advance to next event
    p, prev              - Go back to previous event
    c, continue          - Continue until next breakpoint or end
    s, show              - Show detailed state information
    b <step>             - Set breakpoint on step
    bl, breakpoints      - List all breakpoints
    bc, clear            - Clear all breakpoints
    j <n>, jump <n>      - Jump to event number N (1-based)
    h, help              - Show this help
    q, quit              - Exit debugger
    ───────────────────────────────────────────────────────────
    """)
  end

  defp event_type_short(%{__struct__: module}) do
    module
    |> Module.split()
    |> List.last()
  end
end

defmodule Cerebelum.Infrastructure.ExecutionStateManager do
  @moduledoc """
  Manages execution state for distributed workflow executions.

  Tracks:
  - Which steps have been completed
  - Results of each step
  - Timeline and flow control rules
  - Current execution status

  Uses ETS for fast in-memory state management.
  """

  use GenServer
  require Logger

  @table_name :execution_states

  # Client API

  @doc """
  Start the ExecutionStateManager GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Create a new execution state.

  ## Parameters
  - execution_id: Unique execution identifier
  - blueprint: Workflow blueprint with timeline, diverge_rules, branch_rules
  - inputs: Initial workflow inputs

  ## Returns
  - {:ok, execution_state}
  """
  def create_execution(execution_id, blueprint, inputs) do
    GenServer.call(__MODULE__, {:create_execution, execution_id, blueprint, inputs})
  end

  @doc """
  Get execution state.

  ## Parameters
  - execution_id: Execution identifier

  ## Returns
  - {:ok, execution_state} if found
  - {:error, :not_found} if not found
  """
  def get_execution(execution_id) do
    case :ets.lookup(@table_name, execution_id) do
      [{^execution_id, state}] -> {:ok, state}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Mark a step as completed and store its result.

  ## Parameters
  - execution_id: Execution identifier
  - step_name: Name of completed step
  - result: Step result data

  ## Returns
  - {:ok, updated_state}
  - {:error, reason}
  """
  def complete_step(execution_id, step_name, result) do
    GenServer.call(__MODULE__, {:complete_step, execution_id, step_name, result})
  end

  @doc """
  Get the next steps that are ready to execute.

  Analyzes:
  - Timeline dependencies
  - Diverge rules (pattern matching on results)
  - Branch rules (conditional routing)

  ## Parameters
  - execution_id: Execution identifier

  ## Returns
  - {:ok, [step_names]} - List of steps ready to execute
  - {:ok, []} - No steps ready (execution may be complete)
  - {:error, reason}
  """
  def get_next_steps(execution_id) do
    GenServer.call(__MODULE__, {:get_next_steps, execution_id})
  end

  @doc """
  Mark execution as completed.
  """
  def complete_execution(execution_id) do
    GenServer.call(__MODULE__, {:complete_execution, execution_id})
  end

  @doc """
  Mark execution as failed.
  """
  def fail_execution(execution_id, error) do
    GenServer.call(__MODULE__, {:fail_execution, execution_id, error})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for execution state storage
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])

    Logger.info("ExecutionStateManager started")

    {:ok, %{}}
  end

  @impl true
  def handle_call({:create_execution, execution_id, blueprint, inputs}, _from, state) do
    # Extract timeline steps
    timeline = get_in(blueprint, [:definition, :timeline]) || []

    # Extract flow control rules
    diverge_rules = get_in(blueprint, [:definition, :diverge_rules]) || []
    branch_rules = get_in(blueprint, [:definition, :branch_rules]) || []

    execution_state = %{
      execution_id: execution_id,
      workflow_module: blueprint.workflow_module,
      timeline: timeline,
      diverge_rules: diverge_rules,
      branch_rules: branch_rules,
      inputs: inputs,
      completed_steps: %{},  # Map of step_name => result
      pending_steps: MapSet.new(Enum.map(timeline, &extract_step_name/1)),
      status: :running,
      started_at: System.system_time(:millisecond),
      completed_at: nil,
      error: nil
    }

    :ets.insert(@table_name, {execution_id, execution_state})

    Logger.info("Execution state created: #{execution_id}")

    {:reply, {:ok, execution_state}, state}
  end

  @impl true
  def handle_call({:complete_step, execution_id, step_name, result}, _from, state) do
    case :ets.lookup(@table_name, execution_id) do
      [{^execution_id, exec_state}] ->
        # Update execution state
        updated_state = exec_state
        |> Map.update!(:completed_steps, fn steps ->
          Map.put(steps, step_name, result)
        end)
        # NOTE: Don't remove from pending_steps here - that happens when queued

        # Store updated state
        :ets.insert(@table_name, {execution_id, updated_state})

        Logger.debug("Step completed: #{step_name} in execution #{execution_id}")

        {:reply, {:ok, updated_state}, state}

      [] ->
        {:reply, {:error, :execution_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_next_steps, execution_id}, _from, state) do
    case :ets.lookup(@table_name, execution_id) do
      [{^execution_id, exec_state}] ->
        next_steps = determine_next_steps(exec_state)

        # Remove steps from pending_steps since they will be queued
        updated_state = Enum.reduce(next_steps, exec_state, fn step_name, acc_state ->
          Map.update!(acc_state, :pending_steps, fn pending ->
            MapSet.delete(pending, step_name)
          end)
        end)

        # Store updated state
        :ets.insert(@table_name, {execution_id, updated_state})

        {:reply, {:ok, next_steps}, state}

      [] ->
        {:reply, {:error, :execution_not_found}, state}
    end
  end

  @impl true
  def handle_call({:complete_execution, execution_id}, _from, state) do
    case :ets.lookup(@table_name, execution_id) do
      [{^execution_id, exec_state}] ->
        updated_state = exec_state
        |> Map.put(:status, :completed)
        |> Map.put(:completed_at, System.system_time(:millisecond))

        :ets.insert(@table_name, {execution_id, updated_state})

        Logger.info("Execution completed: #{execution_id}")

        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :execution_not_found}, state}
    end
  end

  @impl true
  def handle_call({:fail_execution, execution_id, error}, _from, state) do
    case :ets.lookup(@table_name, execution_id) do
      [{^execution_id, exec_state}] ->
        updated_state = exec_state
        |> Map.put(:status, :failed)
        |> Map.put(:error, error)
        |> Map.put(:completed_at, System.system_time(:millisecond))

        :ets.insert(@table_name, {execution_id, updated_state})

        Logger.error("Execution failed: #{execution_id}, error: #{inspect(error)}")

        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :execution_not_found}, state}
    end
  end

  # Private Functions

  defp extract_step_name(%{name: name}), do: name
  defp extract_step_name(name) when is_binary(name), do: name
  defp extract_step_name(_), do: nil

  defp determine_next_steps(exec_state) do
    # 1. Check if execution is complete
    if MapSet.size(exec_state.pending_steps) == 0 do
      []
    else
      # 2. Check for diverge rules (pattern-based routing)
      case evaluate_diverge_rules(exec_state) do
        {:diverge, target_step} ->
          [target_step]

        :no_diverge ->
          # 3. Check for branch rules (conditional routing)
          case evaluate_branch_rules(exec_state) do
            {:branch, target_step} ->
              [target_step]

            :no_branch ->
              # 4. Default: get steps with satisfied dependencies
              get_steps_with_satisfied_dependencies(exec_state)
          end
      end
    end
  end

  defp evaluate_diverge_rules(%{diverge_rules: [], completed_steps: _}), do: :no_diverge
  defp evaluate_diverge_rules(%{diverge_rules: rules, completed_steps: completed}) do
    # Find the most recent diverge rule that matches
    Enum.find_value(rules, :no_diverge, fn rule ->
      from_step = get_in(rule, [:from_step])

      # Check if the from_step has been completed
      case Map.get(completed, from_step) do
        nil ->
          # Step not completed yet
          nil

        step_result ->
          # Evaluate patterns against result
          patterns = get_in(rule, [:patterns]) || []

          Enum.find_value(patterns, fn pattern ->
            pattern_match = get_in(pattern, [:pattern]) || %{}
            target = get_in(pattern, [:target])

            # Only return target if it matches AND hasn't been completed yet
            if matches_pattern?(step_result, pattern_match) && !Map.has_key?(completed, target) do
              {:diverge, target}
            end
          end)
      end
    end)
  end

  defp evaluate_branch_rules(%{branch_rules: [], completed_steps: _}), do: :no_branch
  defp evaluate_branch_rules(%{branch_rules: rules, completed_steps: completed}) do
    # Find the first branch rule that matches
    Enum.find_value(rules, :no_branch, fn rule ->
      from_step = get_in(rule, [:from_step])

      case Map.get(completed, from_step) do
        nil ->
          nil

        step_result ->
          branches = get_in(rule, [:branches]) || []

          Enum.find_value(branches, fn branch ->
            condition = get_in(branch, [:condition])
            target = get_in(branch, [:action, :target_step])

            # Only return target if condition matches AND target hasn't been completed yet
            if target && evaluate_condition?(condition, step_result) && !Map.has_key?(completed, target) do
              {:branch, target}
            end
          end)
      end
    end)
  end

  defp get_steps_with_satisfied_dependencies(exec_state) do
    timeline = exec_state.timeline
    completed = exec_state.completed_steps
    pending = exec_state.pending_steps

    # Get steps blocked by unevaluated diverge/branch rules
    blocked_steps = get_blocked_steps(exec_state)

    # Find steps where all dependencies are completed
    timeline
    |> Enum.map(fn step ->
      step_name = extract_step_name(step)
      depends_on = get_in(step, [:depends_on]) || []

      {step_name, depends_on}
    end)
    |> Enum.filter(fn {step_name, depends_on} ->
      # Step is still pending (not yet queued)
      MapSet.member?(pending, step_name) and
      # All dependencies are completed
      Enum.all?(depends_on, fn dep -> Map.has_key?(completed, dep) end) and
      # Step is not blocked by unevaluated diverge/branch rules
      not MapSet.member?(blocked_steps, step_name)
    end)
    |> Enum.map(fn {step_name, _} -> step_name end)
  end

  defp get_blocked_steps(exec_state) do
    completed = exec_state.completed_steps
    diverge_rules = exec_state.diverge_rules
    branch_rules = exec_state.branch_rules

    # Get targets of diverge rules that should be blocked
    diverge_blocked = diverge_rules
    |> Enum.flat_map(fn rule ->
      from_step = rule.from_step
      targets = Enum.map(rule.patterns, fn pattern -> pattern.target end)

      cond do
        # Case 1: from_step hasn't completed → block ALL targets
        not Map.has_key?(completed, from_step) ->
          targets

        # Case 2: from_step completed → only allow ONE target (the one that matches or already completed)
        true ->
          # Filter out targets that are already completed (they were chosen)
          # All other targets should remain blocked forever
          Enum.filter(targets, fn target ->
            not Map.has_key?(completed, target)
          end)
          # If none are completed yet, evaluate which one should be allowed
          |> case do
            [] ->
              # All targets already completed, nothing to block
              []

            remaining_targets ->
              # Check if the diverge rule matches and allows one target
              step_result = Map.get(completed, from_step)
              allowed_target = Enum.find_value(rule.patterns, fn pattern ->
                if matches_pattern?(step_result, pattern.pattern) do
                  pattern.target
                end
              end)

              # Block all targets EXCEPT the allowed one
              Enum.filter(remaining_targets, fn target ->
                target != allowed_target
              end)
          end
      end
    end)

    # Get targets of branch rules that should be blocked
    branch_blocked = branch_rules
    |> Enum.flat_map(fn rule ->
      from_step = rule.from_step
      targets = Enum.map(rule.branches, fn branch -> branch.action.target_step end)

      cond do
        # Case 1: from_step hasn't completed → block ALL targets
        not Map.has_key?(completed, from_step) ->
          targets

        # Case 2: from_step completed → only allow ONE target (the one that matches or already completed)
        true ->
          # Filter out targets that are already completed (they were chosen)
          # All other targets should remain blocked forever
          Enum.filter(targets, fn target ->
            not Map.has_key?(completed, target)
          end)
          # If none are completed yet, evaluate which one should be allowed
          |> case do
            [] ->
              # All targets already completed, nothing to block
              []

            remaining_targets ->
              # Check if a branch condition matches and allows one target
              step_result = Map.get(completed, from_step)
              allowed_target = Enum.find_value(rule.branches, fn branch ->
                if evaluate_condition?(branch.condition, step_result) do
                  branch.action.target_step
                end
              end)

              # Block all targets EXCEPT the allowed one
              Enum.filter(remaining_targets, fn target ->
                target != allowed_target
              end)
          end
      end
    end)

    # Combine and return as MapSet
    MapSet.new(diverge_blocked ++ branch_blocked)
  end

  defp matches_pattern?(result, pattern) when is_map(result) and is_map(pattern) do
    # Simple pattern matching: check if all pattern keys match result
    Enum.all?(pattern, fn {key, value} ->
      Map.get(result, key) == value or
      Map.get(result, String.to_atom(key)) == value or
      Map.get(result, to_string(key)) == value
    end)
  end
  defp matches_pattern?(_, _), do: false

  defp evaluate_condition?(condition, result) when is_binary(condition) do
    # Simple condition evaluation
    # For now, we'll support basic comparisons like "score > 70"
    # In a full implementation, this would use a proper expression evaluator

    # Try to extract value from result for comparison
    # This is a simplified version
    # NOTE: Check >= and <= BEFORE > and < because String.contains? would match both
    cond do
      String.contains?(condition, ">=") ->
        [field, value] = String.split(condition, ">=") |> Enum.map(&String.trim/1)
        result_value = get_result_value(result, field)
        compare_value = String.to_integer(value)
        result_value >= compare_value

      String.contains?(condition, "<=") ->
        [field, value] = String.split(condition, "<=") |> Enum.map(&String.trim/1)
        result_value = get_result_value(result, field)
        compare_value = String.to_integer(value)
        result_value <= compare_value

      String.contains?(condition, ">") ->
        [field, value] = String.split(condition, ">") |> Enum.map(&String.trim/1)
        result_value = get_result_value(result, field)
        compare_value = String.to_integer(value)
        result_value > compare_value

      String.contains?(condition, "<") ->
        [field, value] = String.split(condition, "<") |> Enum.map(&String.trim/1)
        result_value = get_result_value(result, field)
        compare_value = String.to_integer(value)
        result_value < compare_value

      String.contains?(condition, "==") ->
        [field, value] = String.split(condition, "==") |> Enum.map(&String.trim/1)
        result_value = get_result_value(result, field)
        to_string(result_value) == String.trim(value, "\"")

      true ->
        false
    end
  rescue
    _ -> false
  end
  defp evaluate_condition?(_, _), do: false

  defp get_result_value(result, field) when is_map(result) do
    Map.get(result, field) ||
    Map.get(result, String.to_atom(field)) ||
    Map.get(result, to_string(field))
  end
  defp get_result_value(_, _), do: nil
end

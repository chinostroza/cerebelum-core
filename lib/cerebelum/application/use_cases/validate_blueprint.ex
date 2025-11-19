defmodule Cerebelum.Application.UseCases.ValidateBlueprint do
  @moduledoc """
  Use case for validating workflow blueprints submitted by SDK workers.

  Validates:
  - Required fields presence
  - Timeline step references
  - Diverge rule references
  - Branch rule references
  - No cycles in back_to chains
  - Type consistency (future)

  Returns workflow hash for versioning.
  """

  require Logger

  @type blueprint :: %{
          workflow_module: String.t(),
          language: String.t(),
          definition: workflow_definition()
        }

  @type workflow_definition :: %{
          timeline: [step()],
          diverge_rules: [diverge_rule()],
          branch_rules: [branch_rule()],
          inputs: map()
        }

  @type step :: %{name: String.t(), depends_on: [String.t()]}
  @type diverge_rule :: %{from_step: String.t(), patterns: [pattern_match()]}
  @type branch_rule :: %{from_step: String.t(), branches: [condition_branch()]}
  @type pattern_match :: %{pattern: String.t(), target: String.t()}
  @type condition_branch :: %{condition: String.t(), action: branch_action()}
  @type branch_action :: %{type: String.t(), target_step: String.t()}

  @type validation_result ::
          {:ok, %{workflow_hash: String.t(), errors: [], warnings: [String.t()]}}
          | {:error, %{errors: [String.t()], warnings: [String.t()]}}

  @doc """
  Validates a blueprint and returns validation result.

  ## Parameters
  - blueprint: Blueprint structure from protobuf

  ## Returns
  - {:ok, result} if validation passes (may have warnings)
  - {:error, result} if validation fails (has errors)
  """
  @spec execute(blueprint()) :: validation_result()
  def execute(blueprint) do
    errors = []
    warnings = []

    # Validate structure
    {errors, warnings} = validate_structure(blueprint, errors, warnings)

    # Validate references
    {errors, warnings} = validate_references(blueprint, errors, warnings)

    # Validate cycles
    {errors, warnings} = validate_no_cycles(blueprint, errors, warnings)

    # Generate workflow hash
    workflow_hash = compute_workflow_hash(blueprint)

    # Return result
    if errors == [] do
      Logger.info("Blueprint validated successfully: #{Map.get(blueprint, :workflow_module, "unknown")}")
      {:ok, %{workflow_hash: workflow_hash, errors: [], warnings: warnings}}
    else
      Logger.warning("Blueprint validation failed: #{Map.get(blueprint, :workflow_module, "unknown")}, errors: #{length(errors)}")
      {:error, %{errors: errors, warnings: warnings}}
    end
  end

  # Validate required fields and structure
  defp validate_structure(blueprint, errors, warnings) do
    errors = check_required_field(blueprint, :workflow_module, errors)
    errors = check_required_field(blueprint, :language, errors)
    errors = check_required_field(blueprint, :definition, errors)

    errors =
      if Map.has_key?(blueprint, :definition) do
        definition = blueprint.definition
        errors = check_required_field(definition, :timeline, errors)

        # Timeline must not be empty
        errors =
          if Map.has_key?(definition, :timeline) and definition.timeline == [] do
            ["Timeline cannot be empty" | errors]
          else
            errors
          end

        # Check each step has a name
        if Map.has_key?(definition, :timeline) do
          definition.timeline
          |> Enum.with_index()
          |> Enum.reduce(errors, fn {step, idx}, acc ->
            if not Map.has_key?(step, :name) or step.name == "" do
              ["Step at index #{idx} missing name" | acc]
            else
              acc
            end
          end)
        else
          errors
        end
      else
        errors
      end

    {errors, warnings}
  end

  defp check_required_field(map, field, errors) do
    if Map.has_key?(map, field) and map[field] != nil and map[field] != "" do
      errors
    else
      ["Missing required field: #{field}" | errors]
    end
  end

  # Validate all step references exist in timeline
  defp validate_references(blueprint, errors, warnings) do
    if not Map.has_key?(blueprint, :definition) do
      {errors, warnings}
    else
      definition = blueprint.definition

      # Get all step names from timeline
      step_names =
        if Map.has_key?(definition, :timeline) do
          definition.timeline
          |> Enum.filter(&Map.has_key?(&1, :name))
          |> Enum.map(& &1.name)
          |> MapSet.new()
        else
          MapSet.new()
        end

      # Validate depends_on references
      errors =
        if Map.has_key?(definition, :timeline) do
          definition.timeline
          |> Enum.reduce(errors, fn step, acc ->
            if Map.has_key?(step, :depends_on) and Map.has_key?(step, :name) do
              step.depends_on
              |> Enum.reduce(acc, fn dep, err_acc ->
                if MapSet.member?(step_names, dep) do
                  err_acc
                else
                  ["Step '#{step.name}' depends on undefined step '#{dep}'" | err_acc]
                end
              end)
            else
              acc
            end
          end)
        else
          errors
        end

      # Validate diverge rule references
      errors =
        if Map.has_key?(definition, :diverge_rules) do
          definition.diverge_rules
          |> Enum.reduce(errors, fn rule, acc ->
            acc = validate_step_reference(step_names, rule.from_step, "Diverge rule", acc)

            # Validate pattern targets
            if Map.has_key?(rule, :patterns) do
              rule.patterns
              |> Enum.reduce(acc, fn pattern, err_acc ->
                validate_step_reference(step_names, pattern.target, "Diverge pattern", err_acc)
              end)
            else
              acc
            end
          end)
        else
          errors
        end

      # Validate branch rule references
      errors =
        if Map.has_key?(definition, :branch_rules) do
          definition.branch_rules
          |> Enum.reduce(errors, fn rule, acc ->
            acc = validate_step_reference(step_names, rule.from_step, "Branch rule", acc)

            # Validate branch targets
            if Map.has_key?(rule, :branches) do
              rule.branches
              |> Enum.reduce(acc, fn branch, err_acc ->
                if Map.has_key?(branch, :action) and Map.has_key?(branch.action, :target_step) do
                  validate_step_reference(
                    step_names,
                    branch.action.target_step,
                    "Branch action",
                    err_acc
                  )
                else
                  err_acc
                end
              end)
            else
              acc
            end
          end)
        else
          errors
        end

      {errors, warnings}
    end
  end

  defp validate_step_reference(step_names, step_name, context, errors) do
    if MapSet.member?(step_names, step_name) do
      errors
    else
      ["#{context} references undefined step '#{step_name}'" | errors]
    end
  end

  # Validate no cycles in back_to chains
  defp validate_no_cycles(blueprint, errors, warnings) do
    if not Map.has_key?(blueprint, :definition) do
      {errors, warnings}
    else
      definition = blueprint.definition

      # Build graph of back_to edges
      back_to_edges =
        if Map.has_key?(definition, :branch_rules) do
          definition.branch_rules
          |> Enum.flat_map(fn rule ->
            if Map.has_key?(rule, :branches) do
              rule.branches
              |> Enum.filter(fn branch ->
                Map.has_key?(branch, :action) and
                  Map.get(branch.action, :type) == "back_to"
              end)
              |> Enum.map(fn branch ->
                {rule.from_step, branch.action.target_step}
              end)
            else
              []
            end
          end)
        else
          []
        end

      # Detect cycles using DFS
      errors =
        back_to_edges
        |> Enum.reduce(errors, fn {from, to}, acc ->
          if has_cycle?(from, to, back_to_edges, MapSet.new([from])) do
            ["Cycle detected in back_to chain: #{from} -> #{to}" | acc]
          else
            acc
          end
        end)

      {errors, warnings}
    end
  end

  # DFS to detect cycles
  defp has_cycle?(current, target, edges, visited) do
    cond do
      current == target ->
        true

      MapSet.member?(visited, target) ->
        false

      true ->
        next_edges =
          edges
          |> Enum.filter(fn {from, _to} -> from == target end)
          |> Enum.map(fn {_from, to} -> to end)

        Enum.any?(next_edges, fn next ->
          has_cycle?(current, next, edges, MapSet.put(visited, target))
        end)
    end
  end

  # Compute workflow hash for versioning
  defp compute_workflow_hash(blueprint) do
    # Create a stable representation for hashing
    hash_input = %{
      workflow_module: Map.get(blueprint, :workflow_module, ""),
      language: Map.get(blueprint, :language, ""),
      definition: normalize_definition(Map.get(blueprint, :definition, %{}))
    }

    # Convert to JSON and hash
    json = Jason.encode!(hash_input, sort_maps: true)
    :crypto.hash(:sha256, json)
    |> Base.encode16(case: :lower)
  end

  defp normalize_definition(definition) do
    %{
      timeline: normalize_timeline(Map.get(definition, :timeline, [])),
      diverge_rules: normalize_diverge_rules(Map.get(definition, :diverge_rules, [])),
      branch_rules: normalize_branch_rules(Map.get(definition, :branch_rules, [])),
      inputs: Map.get(definition, :inputs, %{})
    }
  end

  defp normalize_timeline(timeline) do
    Enum.map(timeline, fn step ->
      %{
        name: Map.get(step, :name, ""),
        depends_on: Enum.sort(Map.get(step, :depends_on, []))
      }
    end)
  end

  defp normalize_diverge_rules(rules) do
    Enum.map(rules, fn rule ->
      %{
        from_step: rule.from_step,
        patterns:
          Enum.map(Map.get(rule, :patterns, []), fn pattern ->
            %{pattern: pattern.pattern, target: pattern.target}
          end)
      }
    end)
  end

  defp normalize_branch_rules(rules) do
    Enum.map(rules, fn rule ->
      %{
        from_step: rule.from_step,
        branches:
          Enum.map(Map.get(rule, :branches, []), fn branch ->
            %{
              condition: Map.get(branch, :condition, ""),
              action: normalize_action(Map.get(branch, :action, %{}))
            }
          end)
      }
    end)
  end

  defp normalize_action(action) when is_map(action) do
    %{
      type: Map.get(action, :type, ""),
      target_step: Map.get(action, :target_step, "")
    }
  end

  defp normalize_action(_), do: %{type: "", target_step: ""}
end

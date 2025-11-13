defmodule Cerebelum.Workflow.Versioning do
  @moduledoc """
  Workflow versioning utilities.

  Computes and tracks workflow code versions to enable version-aware
  execution and replay. The version is a SHA256 hash of the module bytecode.

  ## Version Computation

  The version is computed from the compiled BEAM bytecode of the workflow module.
  Any change to the workflow code (step functions, metadata, etc.) will result
  in a different version hash.

  ## Usage

      iex> version = Versioning.compute_version(MyWorkflow)
      "a3b2c1d4e5f6..."

      iex> Versioning.get_version(MyWorkflow)
      "a3b2c1d4e5f6..."

  ## Version Mismatch Detection

  When replaying an execution, the system compares the workflow version
  that was used during the original execution with the current version.
  If they differ, a warning is issued.
  """

  @doc """
  Computes the version hash for a workflow module.

  The version is computed as the SHA256 hash of the module's BEAM bytecode.
  This means any code change will result in a different version.

  ## Parameters

  - `module` - The workflow module

  ## Returns

  A lowercase hexadecimal string representing the SHA256 hash.

  ## Examples

      iex> version = Versioning.compute_version(MyWorkflow)
      iex> String.length(version)
      64

      iex> version = Versioning.compute_version(MyWorkflow)
      iex> String.match?(version, ~r/^[0-9a-f]{64}$/)
      true
  """
  @spec compute_version(module()) :: String.t()
  def compute_version(module) do
    case :code.get_object_code(module) do
      {^module, bytecode} when is_binary(bytecode) ->
        # Pattern for modules loaded in memory (2-element tuple)
        :crypto.hash(:sha256, bytecode)
        |> Base.encode16(case: :lower)

      {^module, bytecode, _filename} when is_binary(bytecode) ->
        # Pattern for modules loaded from .beam files (3-element tuple)
        :crypto.hash(:sha256, bytecode)
        |> Base.encode16(case: :lower)

      :error ->
        # Module not loaded from file (e.g., in tests), use fallback
        compute_fallback_version(module)
    end
  end

  @doc """
  Gets the version from a workflow module's metadata.

  This retrieves the version that was computed when the workflow
  metadata was extracted.

  ## Parameters

  - `module` - The workflow module

  ## Returns

  The version string from the module's metadata.

  ## Examples

      iex> version = Versioning.get_version(MyWorkflow)
      iex> is_binary(version)
      true
  """
  @spec get_version(module()) :: String.t()
  def get_version(module) do
    metadata = module.__workflow_metadata__()
    Map.get(metadata, :version, compute_version(module))
  end

  @doc """
  Verifies if two versions match.

  ## Parameters

  - `version1` - First version string
  - `version2` - Second version string

  ## Returns

  - `{:ok, :match}` - Versions match
  - `{:error, :mismatch, details}` - Versions don't match

  ## Examples

      iex> Versioning.verify_version("abc123", "abc123")
      {:ok, :match}

      iex> Versioning.verify_version("abc123", "def456")
      {:error, :mismatch, %{expected: "abc123", actual: "def456"}}
  """
  @spec verify_version(String.t(), String.t()) ::
          {:ok, :match} | {:error, :mismatch, map()}
  def verify_version(expected_version, actual_version) do
    if expected_version == actual_version do
      {:ok, :match}
    else
      {:error, :mismatch, %{expected: expected_version, actual: actual_version}}
    end
  end

  @doc """
  Checks if a workflow has changed since a specific version.

  ## Parameters

  - `module` - The workflow module
  - `old_version` - The version to compare against

  ## Returns

  - `true` - Workflow has changed
  - `false` - Workflow is the same

  ## Examples

      iex> current_version = Versioning.compute_version(MyWorkflow)
      iex> Versioning.has_changed?(MyWorkflow, current_version)
      false

      iex> Versioning.has_changed?(MyWorkflow, "old_version_hash")
      true
  """
  @spec has_changed?(module(), String.t()) :: boolean()
  def has_changed?(module, old_version) do
    current_version = compute_version(module)
    current_version != old_version
  end

  ## Private Helpers

  # Fallback version computation when bytecode is not available
  # Uses module exports to create a deterministic hash
  # This is less precise than bytecode hashing but works in tests
  defp compute_fallback_version(module) do
    try do
      # Get function exports (doesn't cause infinite loop)
      exports = module.__info__(:functions) |> Enum.sort()

      # Create a deterministic representation
      data = {module, exports}

      :crypto.hash(:sha256, :erlang.term_to_binary(data))
      |> Base.encode16(case: :lower)
    rescue
      _ ->
        # If even that fails, use module name as fallback
        :crypto.hash(:sha256, Atom.to_string(module))
        |> Base.encode16(case: :lower)
    end
  end
end

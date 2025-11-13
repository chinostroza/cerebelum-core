defmodule Cerebelum.Workflow.VersioningTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Workflow.Versioning

  # Define test workflows
  defmodule SimpleWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        step1() |> step2() |> step3()
      end
    end

    def step1(_ctx), do: {:ok, 1}
    def step2(_ctx, {:ok, _}), do: {:ok, 2}
    def step3(_ctx, {:ok, _}, {:ok, _}), do: {:ok, 3}
  end

  defmodule AnotherWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        start() |> process() |> finish()
      end
    end

    def start(_ctx), do: {:ok, :started}
    def process(_ctx, {:ok, _}), do: {:ok, :processed}
    def finish(_ctx, {:ok, _}, {:ok, _}), do: {:ok, :done}
  end

  describe "compute_version/1" do
    test "computes a valid SHA256 hash" do
      version = Versioning.compute_version(SimpleWorkflow)

      # Should be a 64-character hexadecimal string
      assert String.length(version) == 64
      assert String.match?(version, ~r/^[0-9a-f]{64}$/)
    end

    test "different workflows have different versions" do
      version1 = Versioning.compute_version(SimpleWorkflow)
      version2 = Versioning.compute_version(AnotherWorkflow)

      assert version1 != version2
    end

    test "same workflow computed multiple times returns same version" do
      version1 = Versioning.compute_version(SimpleWorkflow)
      version2 = Versioning.compute_version(SimpleWorkflow)

      assert version1 == version2
    end

    test "version is deterministic" do
      # Computing version multiple times should give same result
      versions =
        Enum.map(1..5, fn _ ->
          Versioning.compute_version(SimpleWorkflow)
        end)

      assert Enum.uniq(versions) |> length() == 1
    end
  end

  describe "get_version/1" do
    test "retrieves version from workflow metadata" do
      version = Versioning.get_version(SimpleWorkflow)

      # Should match the computed version
      computed_version = Versioning.compute_version(SimpleWorkflow)
      assert version == computed_version
    end

    test "version is available through __workflow_metadata__" do
      metadata = SimpleWorkflow.__workflow_metadata__()

      assert Map.has_key?(metadata, :version)
      assert String.length(metadata.version) == 64
    end
  end

  describe "verify_version/2" do
    test "returns :ok when versions match" do
      version = "abc123"

      assert Versioning.verify_version(version, version) == {:ok, :match}
    end

    test "returns error when versions don't match" do
      version1 = "abc123"
      version2 = "def456"

      assert {:error, :mismatch, details} = Versioning.verify_version(version1, version2)
      assert details.expected == version1
      assert details.actual == version2
    end

    test "can verify actual workflow versions" do
      version = Versioning.get_version(SimpleWorkflow)

      assert Versioning.verify_version(version, version) == {:ok, :match}
    end
  end

  describe "has_changed?/2" do
    test "returns false when version hasn't changed" do
      current_version = Versioning.compute_version(SimpleWorkflow)

      refute Versioning.has_changed?(SimpleWorkflow, current_version)
    end

    test "returns true when comparing with different version" do
      fake_old_version = "0000000000000000000000000000000000000000000000000000000000000000"

      assert Versioning.has_changed?(SimpleWorkflow, fake_old_version)
    end

    test "detects changes between different workflows" do
      simple_version = Versioning.compute_version(SimpleWorkflow)

      # Using SimpleWorkflow's version to check AnotherWorkflow should show change
      assert Versioning.has_changed?(AnotherWorkflow, simple_version)
    end
  end

  describe "version stability" do
    test "workflow version is included in metadata" do
      metadata = SimpleWorkflow.__workflow_metadata__()

      assert is_binary(metadata.version)
      assert String.length(metadata.version) == 64
    end

    test "version doesn't change on repeated metadata calls" do
      metadata1 = SimpleWorkflow.__workflow_metadata__()
      metadata2 = SimpleWorkflow.__workflow_metadata__()

      assert metadata1.version == metadata2.version
    end
  end
end

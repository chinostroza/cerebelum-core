defmodule Cerebelum.ContextTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Context
  alias Cerebelum.Examples.CounterWorkflow

  describe "new/3" do
    test "creates context with required fields" do
      ctx = Context.new(CounterWorkflow, %{order_id: "123"})

      assert ctx.workflow_module == CounterWorkflow
      assert is_binary(ctx.execution_id)
      assert ctx.inputs == %{order_id: "123"}
      assert ctx.current_step == nil
      assert ctx.retry_count == 0
      assert ctx.iteration == 0
      assert is_binary(ctx.workflow_version)
      assert %DateTime{} = ctx.started_at
      assert %DateTime{} = ctx.updated_at
    end

    test "generates unique execution_id" do
      ctx1 = Context.new(CounterWorkflow, %{})
      ctx2 = Context.new(CounterWorkflow, %{})

      assert ctx1.execution_id != ctx2.execution_id
    end

    test "accepts custom execution_id" do
      ctx = Context.new(CounterWorkflow, %{}, execution_id: "custom-123")

      assert ctx.execution_id == "custom-123"
    end

    test "accepts correlation_id for tracing" do
      ctx = Context.new(CounterWorkflow, %{}, correlation_id: "trace-456")

      assert ctx.correlation_id == "trace-456"
    end

    test "accepts initial tags" do
      ctx = Context.new(CounterWorkflow, %{}, tags: ["priority:high", "env:prod"])

      assert "priority:high" in ctx.tags
      assert "env:prod" in ctx.tags
    end

    test "accepts initial metadata" do
      ctx = Context.new(CounterWorkflow, %{}, metadata: %{user_id: 123, org_id: 456})

      assert ctx.metadata.user_id == 123
      assert ctx.metadata.org_id == 456
    end

    test "sets started_at to current time" do
      before = DateTime.utc_now()
      ctx = Context.new(CounterWorkflow, %{})
      after_time = DateTime.utc_now()

      assert DateTime.compare(ctx.started_at, before) in [:gt, :eq]
      assert DateTime.compare(ctx.started_at, after_time) in [:lt, :eq]
    end

    test "extracts workflow version from module" do
      ctx = Context.new(CounterWorkflow, %{})

      # CounterWorkflow has __workflow_metadata__/0
      assert is_binary(ctx.workflow_version)
      assert ctx.workflow_version != "unknown"
    end
  end

  describe "valid?/1" do
    test "returns true for valid context" do
      ctx = Context.new(CounterWorkflow, %{})

      assert Context.valid?(ctx)
    end

    test "returns false for non-context struct" do
      refute Context.valid?(%{})
      refute Context.valid?("not a context")
      refute Context.valid?(nil)
    end

    test "returns false for context with invalid fields" do
      ctx = Context.new(CounterWorkflow, %{})

      # Modify struct directly (shouldn't do this in real code)
      invalid_ctx = %{ctx | retry_count: -1}
      refute Context.valid?(invalid_ctx)

      invalid_ctx = %{ctx | tags: "not a list"}
      refute Context.valid?(invalid_ctx)
    end
  end

  describe "update_step/2" do
    test "updates current_step" do
      ctx = Context.new(CounterWorkflow, %{})
      ctx = Context.update_step(ctx, :validate_order)
      assert ctx.current_step == :validate_order
    end

    test "updates updated_at timestamp" do
      ctx = Context.new(CounterWorkflow, %{})
      original_updated = ctx.updated_at

      :timer.sleep(1)  # Ensure time passes
      ctx = Context.update_step(ctx, :validate_order)

      assert DateTime.compare(ctx.updated_at, original_updated) == :gt
    end

    test "does not mutate original context" do
      ctx = Context.new(CounterWorkflow, %{})
      original_step = ctx.current_step
      _updated = Context.update_step(ctx, :validate_order)
      assert ctx.current_step == original_step
    end
  end

  describe "advance_to_step/2" do
    test "is an alias for update_step/2" do
      ctx = Context.new(CounterWorkflow, %{})
      ctx = Context.advance_to_step(ctx, :validate_order)
      assert ctx.current_step == :validate_order
    end
  end

  describe "increment_retry/1" do
    test "increments retry_count by 1" do
      ctx = Context.new(CounterWorkflow, %{})

      ctx = Context.increment_retry(ctx)
      assert ctx.retry_count == 1

      ctx = Context.increment_retry(ctx)
      assert ctx.retry_count == 2
    end

    test "updates updated_at timestamp" do
      ctx = Context.new(CounterWorkflow, %{})
      original_updated = ctx.updated_at

      :timer.sleep(1)
      ctx = Context.increment_retry(ctx)

      assert DateTime.compare(ctx.updated_at, original_updated) == :gt
    end
  end

  describe "reset_retry/1" do
    test "resets retry_count to 0" do
      ctx = Context.new(CounterWorkflow, %{})

      ctx = ctx
        |> Context.increment_retry()
        |> Context.increment_retry()
        |> Context.increment_retry()

      assert ctx.retry_count == 3

      ctx = Context.reset_retry(ctx)
      assert ctx.retry_count == 0
    end

    test "updates updated_at timestamp" do
      ctx = Context.new(CounterWorkflow, %{})
        |> Context.increment_retry()

      original_updated = ctx.updated_at

      :timer.sleep(1)
      ctx = Context.reset_retry(ctx)

      assert DateTime.compare(ctx.updated_at, original_updated) == :gt
    end
  end

  describe "increment_iteration/1" do
    test "increments iteration by 1" do
      ctx = Context.new(CounterWorkflow, %{})

      ctx = Context.increment_iteration(ctx)
      assert ctx.iteration == 1

      ctx = Context.increment_iteration(ctx)
      assert ctx.iteration == 2
    end

    test "updates updated_at timestamp" do
      ctx = Context.new(CounterWorkflow, %{})
      original_updated = ctx.updated_at

      :timer.sleep(1)
      ctx = Context.increment_iteration(ctx)

      assert DateTime.compare(ctx.updated_at, original_updated) == :gt
    end
  end

  describe "add_tag/2" do
    test "adds tag to tags list" do
      ctx = Context.new(CounterWorkflow, %{})

      ctx = Context.add_tag(ctx, "high_priority")
      assert "high_priority" in ctx.tags

      ctx = Context.add_tag(ctx, "urgent")
      assert "high_priority" in ctx.tags
      assert "urgent" in ctx.tags
    end

    test "does not add duplicate tags" do
      ctx = Context.new(CounterWorkflow, %{})

      ctx = ctx
        |> Context.add_tag("test")
        |> Context.add_tag("test")

      assert ctx.tags == ["test"]
    end

    test "updates updated_at timestamp" do
      ctx = Context.new(CounterWorkflow, %{})
      original_updated = ctx.updated_at

      :timer.sleep(1)
      ctx = Context.add_tag(ctx, "new_tag")

      assert DateTime.compare(ctx.updated_at, original_updated) == :gt
    end
  end

  describe "add_tags/2" do
    test "adds multiple tags at once" do
      ctx = Context.new(CounterWorkflow, %{})
      ctx = Context.add_tags(ctx, ["tag1", "tag2", "tag3"])

      assert "tag1" in ctx.tags
      assert "tag2" in ctx.tags
      assert "tag3" in ctx.tags
      assert length(ctx.tags) == 3
    end

    test "does not add duplicate tags" do
      ctx = Context.new(CounterWorkflow, %{})
      ctx = ctx
        |> Context.add_tag("existing")
        |> Context.add_tags(["existing", "new"])

      assert length(ctx.tags) == 2
      assert "existing" in ctx.tags
      assert "new" in ctx.tags
    end
  end

  describe "remove_tag/2" do
    test "removes tag from tags list" do
      ctx = Context.new(CounterWorkflow, %{})
        |> Context.add_tags(["tag1", "tag2", "tag3"])

      ctx = Context.remove_tag(ctx, "tag2")

      assert "tag1" in ctx.tags
      refute "tag2" in ctx.tags
      assert "tag3" in ctx.tags
    end

    test "does nothing if tag doesn't exist" do
      ctx = Context.new(CounterWorkflow, %{})
        |> Context.add_tag("tag1")

      ctx = Context.remove_tag(ctx, "nonexistent")

      assert ctx.tags == ["tag1"]
    end

    test "updates updated_at timestamp" do
      ctx = Context.new(CounterWorkflow, %{})
        |> Context.add_tag("temp")

      original_updated = ctx.updated_at

      :timer.sleep(1)
      ctx = Context.remove_tag(ctx, "temp")

      assert DateTime.compare(ctx.updated_at, original_updated) == :gt
    end
  end

  describe "put_metadata/3" do
    test "adds metadata to metadata map" do
      ctx = Context.new(CounterWorkflow, %{})
      ctx = Context.put_metadata(ctx, :user_id, "user-123")
      assert ctx.metadata[:user_id] == "user-123"
    end

    test "overwrites existing metadata key" do
      ctx = Context.new(CounterWorkflow, %{})

      ctx = ctx
        |> Context.put_metadata(:count, 1)
        |> Context.put_metadata(:count, 2)

      assert ctx.metadata[:count] == 2
    end

    test "accepts string keys" do
      ctx = Context.new(CounterWorkflow, %{})
      ctx = Context.put_metadata(ctx, "string_key", "value")
      assert ctx.metadata["string_key"] == "value"
    end

    test "updates updated_at timestamp" do
      ctx = Context.new(CounterWorkflow, %{})
      original_updated = ctx.updated_at

      :timer.sleep(1)
      ctx = Context.put_metadata(ctx, :key, "value")

      assert DateTime.compare(ctx.updated_at, original_updated) == :gt
    end
  end

  describe "get_metadata/3" do
    test "retrieves metadata value" do
      ctx = Context.new(CounterWorkflow, %{})
        |> Context.put_metadata(:user_id, 123)

      assert Context.get_metadata(ctx, :user_id) == 123
    end

    test "returns default for missing key" do
      ctx = Context.new(CounterWorkflow, %{})

      assert Context.get_metadata(ctx, :missing) == nil
      assert Context.get_metadata(ctx, :missing, :default) == :default
    end

    test "works with string keys" do
      ctx = Context.new(CounterWorkflow, %{})
        |> Context.put_metadata("string_key", "value")

      assert Context.get_metadata(ctx, "string_key") == "value"
    end
  end

  describe "merge_metadata/2" do
    test "merges metadata map into context" do
      ctx = Context.new(CounterWorkflow, %{})
        |> Context.put_metadata(:existing, "old")

      ctx = Context.merge_metadata(ctx, %{user_id: 123, org_id: 456})

      assert ctx.metadata.existing == "old"
      assert ctx.metadata.user_id == 123
      assert ctx.metadata.org_id == 456
    end

    test "overwrites existing keys" do
      ctx = Context.new(CounterWorkflow, %{})
        |> Context.put_metadata(:key, "old")

      ctx = Context.merge_metadata(ctx, %{key: "new"})

      assert ctx.metadata.key == "new"
    end

    test "updates updated_at timestamp" do
      ctx = Context.new(CounterWorkflow, %{})
      original_updated = ctx.updated_at

      :timer.sleep(1)
      ctx = Context.merge_metadata(ctx, %{key: "value"})

      assert DateTime.compare(ctx.updated_at, original_updated) == :gt
    end
  end

  describe "to_map/1" do
    test "converts context to map" do
      ctx = Context.new(CounterWorkflow, %{user_id: 123})
      map = Context.to_map(ctx)

      assert is_map(map)
      assert map.execution_id == ctx.execution_id
      assert map.workflow_module == CounterWorkflow
      assert map.inputs == %{user_id: 123}
    end

    test "converts datetime fields to ISO8601 strings" do
      ctx = Context.new(CounterWorkflow, %{})
      map = Context.to_map(ctx)

      assert is_binary(map.started_at)
      assert is_binary(map.updated_at)
      assert String.contains?(map.started_at, "T")
    end

    test "handles nil updated_at" do
      ctx = Context.new(CounterWorkflow, %{})
      # Force updated_at to nil (shouldn't happen in practice)
      ctx = %{ctx | updated_at: nil}
      map = Context.to_map(ctx)

      assert map.updated_at == nil
    end
  end

  describe "from_map/1" do
    test "creates context from map with atom keys" do
      map = %{
        execution_id: "test-123",
        workflow_module: CounterWorkflow,
        workflow_version: "abc123",
        started_at: "2025-01-01T00:00:00Z",
        updated_at: "2025-01-01T01:00:00Z",
        inputs: %{user_id: 123},
        retry_count: 2,
        iteration: 1,
        current_step: :validate,
        tags: ["tag1"],
        metadata: %{key: "value"}
      }

      {:ok, ctx} = Context.from_map(map)

      assert ctx.execution_id == "test-123"
      assert ctx.workflow_module == CounterWorkflow
      assert ctx.workflow_version == "abc123"
      assert %DateTime{} = ctx.started_at
      assert %DateTime{} = ctx.updated_at
      assert ctx.inputs == %{user_id: 123}
      assert ctx.retry_count == 2
      assert ctx.iteration == 1
      assert ctx.current_step == :validate
      assert ctx.tags == ["tag1"]
      assert ctx.metadata == %{key: "value"}
    end

    test "creates context from map with string keys" do
      map = %{
        "execution_id" => "test-456",
        "workflow_module" => CounterWorkflow,
        "workflow_version" => "def456",
        "started_at" => "2025-01-01T00:00:00Z"
      }

      {:ok, ctx} = Context.from_map(map)

      assert ctx.execution_id == "test-456"
      assert ctx.workflow_module == CounterWorkflow
    end

    test "handles datetime objects" do
      now = DateTime.utc_now()
      map = %{
        execution_id: "test-789",
        workflow_module: CounterWorkflow,
        workflow_version: "ghi789",
        started_at: now
      }

      {:ok, ctx} = Context.from_map(map)

      assert ctx.started_at == now
    end

    test "returns error for invalid datetime" do
      map = %{
        execution_id: "test-999",
        workflow_module: CounterWorkflow,
        workflow_version: "jkl999",
        started_at: "invalid-datetime"
      }

      assert {:error, _} = Context.from_map(map)
    end

    test "returns error for missing required fields" do
      map = %{execution_id: "test"}

      assert {:error, _} = Context.from_map(map)
    end

    test "round-trip conversion preserves data" do
      original = Context.new(CounterWorkflow, %{user_id: 123})
        |> Context.add_tag("test")
        |> Context.put_metadata(:key, "value")

      map = Context.to_map(original)
      {:ok, restored} = Context.from_map(map)

      assert restored.execution_id == original.execution_id
      assert restored.workflow_module == original.workflow_module
      assert restored.inputs == original.inputs
      assert restored.tags == original.tags
      assert restored.metadata == original.metadata
    end
  end

  describe "immutability" do
    test "all operations return new context without mutating original" do
      original = Context.new(CounterWorkflow, %{})

      _updated = original
        |> Context.increment_retry()
        |> Context.increment_iteration()
        |> Context.update_step(:step1)
        |> Context.add_tag("tag")
        |> Context.put_metadata(:key, "value")

      # Original should be unchanged
      assert original.retry_count == 0
      assert original.iteration == 0
      assert original.current_step == nil
      assert original.tags == []
      assert original.metadata == %{}
    end
  end
end

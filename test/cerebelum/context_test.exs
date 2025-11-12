defmodule Cerebelum.ContextTest do
    use ExUnit.Case, async: true

    alias Cerebelum.Context

    describe "new/3" do
      test "creates context with required fields" do
        ctx = Context.new(MyWorkflow, %{order_id: "123"})

        assert ctx.workflow_module == MyWorkflow
        assert is_binary(ctx.execution_id)
        assert ctx.inputs == %{order_id: "123"}
        assert ctx.current_step == nil
        assert ctx.retry_count == 0
        assert ctx.iteration == 0
      end

      test "generates unique execution_id" do
        ctx1 = Context.new(MyWorkflow, %{})
        ctx2 = Context.new(MyWorkflow, %{})

        assert ctx1.execution_id != ctx2.execution_id
      end

      test "accepts optional workflow_version" do
        ctx = Context.new(MyWorkflow, %{}, workflow_version: "abc123")

        assert ctx.workflow_version == "abc123"
      end

      test "sets started_at to current time" do
        before = DateTime.utc_now()
        ctx = Context.new(MyWorkflow, %{})
        after_time = DateTime.utc_now()

        assert DateTime.compare(ctx.started_at, before) in [:gt, :eq]
        assert DateTime.compare(ctx.started_at, after_time) in [:lt, :eq]
      end
    end

    describe "advance_to_step/2" do
      test "updates current_step" do
        ctx = Context.new(MyWorkflow, %{})
        ctx = Context.advance_to_step(ctx, :validate_order)
        assert ctx.current_step == :validate_order
      end

      test "does not mutate original context" do
        ctx = Context.new(MyWorkflow, %{})
        original_step = ctx.current_step
        _updated = Context.advance_to_step(ctx, :validate_order)
        assert ctx.current_step == original_step
      end
    end

    describe "increment_retry/1" do
      test "increments retry_count by 1" do
        ctx = Context.new(MyWorkflow, %{})

        ctx = Context.increment_retry(ctx)
        assert ctx.retry_count == 1

        ctx = Context.increment_retry(ctx)
        assert ctx.retry_count == 2
      end
    end

    describe "increment_iteration/1" do
      test "increments iteration by 1" do
        ctx = Context.new(MyWorkflow, %{})

        ctx = Context.increment_iteration(ctx)
        assert ctx.iteration == 1

        ctx = Context.increment_iteration(ctx)
        assert ctx.iteration == 2
      end
    end

    describe "add_tag/2" do
      test "adds tag to tags list" do
        ctx = Context.new(MyWorkflow, %{})

        ctx = Context.add_tag(ctx, :high_priority)
        assert :high_priority in ctx.tags

        ctx = Context.add_tag(ctx, :urgent)
        assert :high_priority in ctx.tags
        assert :urgent in ctx.tags
      end

      test "does not add duplicate tags" do
        ctx = Context.new(MyWorkflow, %{})

        ctx = ctx
          |> Context.add_tag(:test)
          |> Context.add_tag(:test)

        assert ctx.tags == [:test]
      end
    end

    describe "put_metadata/3" do
      test "adds metadata to metadata map" do
        ctx = Context.new(MyWorkflow, %{})
        ctx = Context.put_metadata(ctx, :user_id, "user-123")
        assert ctx.metadata[:user_id] == "user-123"
      end

      test "overwrites existing metadata key" do
        ctx = Context.new(MyWorkflow, %{})

        ctx = ctx
          |> Context.put_metadata(:count, 1)
          |> Context.put_metadata(:count, 2)

        assert ctx.metadata[:count] == 2
      end
    end
  end

defmodule Cerebelum.ResultsCacheTest do
  use ExUnit.Case, async: true

  alias Cerebelum.ResultsCache

  describe "new/0" do
    test "creates empty cache" do
      cache = ResultsCache.new()

      assert cache == %{}
      assert map_size(cache) == 0
    end
  end

  describe "put/3" do
    test "stores step result" do
      cache = ResultsCache.new()

      cache = ResultsCache.put(cache, :start, %{order_id: "123"})

      assert cache[:start] == %{order_id: "123"}
    end

    test "can store multiple steps" do
      cache = ResultsCache.new()

      cache = cache
        |> ResultsCache.put(:start, %{order_id: "123"})
        |> ResultsCache.put(:validate, %{valid: true})

      assert cache[:start] == %{order_id: "123"}
      assert cache[:validate] == %{valid: true}
    end

    test "overwrites existing step result" do
      cache = ResultsCache.new()

      cache = cache
        |> ResultsCache.put(:start, %{value: 1})
        |> ResultsCache.put(:start, %{value: 2})

      assert cache[:start] == %{value: 2}
    end

    test "does not mutate original cache" do
      cache = ResultsCache.new()
      original_size = map_size(cache)

      _updated = ResultsCache.put(cache, :start, %{})

      assert map_size(cache) == original_size
    end
  end

  describe "get/2" do
    test "returns {:ok, result} if step exists" do
      cache = ResultsCache.new()
        |> ResultsCache.put(:start, %{value: 42})

      assert ResultsCache.get(cache, :start) == {:ok, %{value: 42}}
    end

    test "returns :error if step does not exist" do
      cache = ResultsCache.new()

      assert ResultsCache.get(cache, :nonexistent) == :error
    end
  end

  describe "get!/2" do
    test "returns result if step exists" do
      cache = ResultsCache.new()
        |> ResultsCache.put(:start, %{value: 42})

      assert ResultsCache.get!(cache, :start) == %{value: 42}
    end

    test "raises KeyError if step does not exist" do
      cache = ResultsCache.new()

      assert_raise KeyError, fn ->
        ResultsCache.get!(cache, :nonexistent)
      end
    end
  end

  describe "has_step?/2" do
    test "returns true if step exists" do
      cache = ResultsCache.new()
        |> ResultsCache.put(:start, %{})

      assert ResultsCache.has_step?(cache, :start)
    end

    test "returns false if step does not exist" do
      cache = ResultsCache.new()

      refute ResultsCache.has_step?(cache, :start)
    end
  end

  describe "get_up_to/3" do
    test "returns cache with only steps up to specified step" do
      steps_order = [:start, :validate, :charge, :done]

      cache = ResultsCache.new()
        |> ResultsCache.put(:start, %{value: 1})
        |> ResultsCache.put(:validate, %{value: 2})
        |> ResultsCache.put(:charge, %{value: 3})

      # Get results up to :validate (inclusive)
      result = ResultsCache.get_up_to(cache, :validate, steps_order)

      assert result == %{
        start: %{value: 1},
        validate: %{value: 2}
      }
    end

    test "returns empty map if step is first" do
      steps_order = [:start, :validate, :charge]

      cache = ResultsCache.new()
        |> ResultsCache.put(:start, %{value: 1})
        |> ResultsCache.put(:validate, %{value: 2})

      # Get results up to :start (should include only start)
      result = ResultsCache.get_up_to(cache, :start, steps_order)

      assert result == %{start: %{value: 1}}
    end

    test "handles step not in order list" do
      steps_order = [:start, :validate]

      cache = ResultsCache.new()
        |> ResultsCache.put(:start, %{value: 1})

      # Step not in order
      result = ResultsCache.get_up_to(cache, :nonexistent, steps_order)

      assert result == %{}
    end
  end

  describe "executed_steps/1" do
    test "returns list of executed step names" do
      cache = ResultsCache.new()
        |> ResultsCache.put(:start, %{})
        |> ResultsCache.put(:validate, %{})
        |> ResultsCache.put(:charge, %{})

      steps = ResultsCache.executed_steps(cache)

      assert :start in steps
      assert :validate in steps
      assert :charge in steps
      assert length(steps) == 3
    end

    test "returns empty list for new cache" do
      cache = ResultsCache.new()

      assert ResultsCache.executed_steps(cache) == []
    end
  end
end

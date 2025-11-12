defmodule Cerebelum.Execution.ResultsCacheTest do
  use ExUnit.Case, async: true
  doctest Cerebelum.Execution.ResultsCache

  alias Cerebelum.Execution.ResultsCache

  describe "new/0" do
    test "creates an empty cache" do
      cache = ResultsCache.new()

      assert is_map(cache)
      assert map_size(cache) == 0
    end
  end

  describe "put/3 and get/2" do
    test "stores and retrieves a result" do
      cache = ResultsCache.new()
      cache = ResultsCache.put(cache, :step1, {:ok, "result"})

      assert {:ok, {:ok, "result"}} = ResultsCache.get(cache, :step1)
    end

    test "returns error for missing key" do
      cache = ResultsCache.new()

      assert :error = ResultsCache.get(cache, :missing)
    end

    test "overwrites existing value" do
      cache = ResultsCache.new()
      cache = ResultsCache.put(cache, :step1, "first")
      cache = ResultsCache.put(cache, :step1, "second")

      assert {:ok, "second"} = ResultsCache.get(cache, :step1)
    end

    test "stores multiple results independently" do
      cache = ResultsCache.new()
      cache = cache
        |> ResultsCache.put(:step1, "a")
        |> ResultsCache.put(:step2, "b")
        |> ResultsCache.put(:step3, "c")

      assert {:ok, "a"} = ResultsCache.get(cache, :step1)
      assert {:ok, "b"} = ResultsCache.get(cache, :step2)
      assert {:ok, "c"} = ResultsCache.get(cache, :step3)
    end
  end

  describe "get!/2" do
    test "retrieves existing result" do
      cache = ResultsCache.new()
      cache = ResultsCache.put(cache, :step1, "value")

      assert ResultsCache.get!(cache, :step1) == "value"
    end

    test "raises for missing key" do
      cache = ResultsCache.new()

      assert_raise KeyError, fn ->
        ResultsCache.get!(cache, :missing)
      end
    end
  end

  describe "has?/2" do
    test "returns true for existing key" do
      cache = ResultsCache.new()
      cache = ResultsCache.put(cache, :step1, "value")

      assert ResultsCache.has?(cache, :step1) == true
    end

    test "returns false for missing key" do
      cache = ResultsCache.new()

      assert ResultsCache.has?(cache, :missing) == false
    end
  end

  describe "take/2" do
    test "takes multiple results from cache" do
      cache = ResultsCache.new()
      cache = cache
        |> ResultsCache.put(:step1, "a")
        |> ResultsCache.put(:step2, "b")
        |> ResultsCache.put(:step3, "c")
        |> ResultsCache.put(:step4, "d")

      taken = ResultsCache.take(cache, [:step1, :step3])

      assert map_size(taken) == 2
      assert taken[:step1] == "a"
      assert taken[:step3] == "c"
      refute Map.has_key?(taken, :step2)
      refute Map.has_key?(taken, :step4)
    end

    test "handles empty list" do
      cache = ResultsCache.new()
      cache = ResultsCache.put(cache, :step1, "a")

      taken = ResultsCache.take(cache, [])

      assert map_size(taken) == 0
    end

    test "handles non-existent keys" do
      cache = ResultsCache.new()
      cache = ResultsCache.put(cache, :step1, "a")

      taken = ResultsCache.take(cache, [:step1, :missing])

      assert map_size(taken) == 1
      assert taken[:step1] == "a"
    end
  end

  describe "clear/1" do
    test "clears all results" do
      cache = ResultsCache.new()
      cache = cache
        |> ResultsCache.put(:step1, "a")
        |> ResultsCache.put(:step2, "b")

      cache = ResultsCache.clear(cache)

      assert map_size(cache) == 0
    end

    test "clearing empty cache returns empty cache" do
      cache = ResultsCache.new()
      cache = ResultsCache.clear(cache)

      assert map_size(cache) == 0
    end
  end

  describe "size/1" do
    test "returns zero for empty cache" do
      cache = ResultsCache.new()

      assert ResultsCache.size(cache) == 0
    end

    test "returns correct count" do
      cache = ResultsCache.new()
      cache = cache
        |> ResultsCache.put(:step1, "a")
        |> ResultsCache.put(:step2, "b")
        |> ResultsCache.put(:step3, "c")

      assert ResultsCache.size(cache) == 3
    end

    test "updates after modifications" do
      cache = ResultsCache.new()
      cache = ResultsCache.put(cache, :step1, "a")
      assert ResultsCache.size(cache) == 1

      cache = ResultsCache.put(cache, :step2, "b")
      assert ResultsCache.size(cache) == 2

      cache = ResultsCache.clear(cache)
      assert ResultsCache.size(cache) == 0
    end
  end

  describe "to_list/1" do
    test "converts empty cache to empty list" do
      cache = ResultsCache.new()
      list = ResultsCache.to_list(cache)

      assert list == []
    end

    test "converts cache to list of tuples" do
      cache = ResultsCache.new()
      cache = cache
        |> ResultsCache.put(:step1, "a")
        |> ResultsCache.put(:step2, "b")

      list = ResultsCache.to_list(cache)

      assert length(list) == 2
      assert {:step1, "a"} in list
      assert {:step2, "b"} in list
    end
  end

  describe "immutability" do
    test "operations return new cache without mutating original" do
      cache1 = ResultsCache.new()
      cache2 = ResultsCache.put(cache1, :step1, "value")

      assert map_size(cache1) == 0
      assert map_size(cache2) == 1
    end

    test "multiple operations preserve immutability" do
      original = ResultsCache.new()

      _modified = original
        |> ResultsCache.put(:step1, "a")
        |> ResultsCache.put(:step2, "b")
        |> ResultsCache.clear()

      assert map_size(original) == 0
    end
  end

  describe "integration with real workflow results" do
    test "can store typical workflow results" do
      cache = ResultsCache.new()

      cache = cache
        |> ResultsCache.put(:initialize, {:ok, 0})
        |> ResultsCache.put(:increment, {:ok, 1})
        |> ResultsCache.put(:double, {:ok, 2})
        |> ResultsCache.put(:finalize, {:ok, 2})

      assert ResultsCache.size(cache) == 4
      assert {:ok, {:ok, 0}} = ResultsCache.get(cache, :initialize)
      assert {:ok, {:ok, 2}} = ResultsCache.get(cache, :finalize)
    end

    test "can store error results" do
      cache = ResultsCache.new()

      cache = cache
        |> ResultsCache.put(:step1, {:ok, "success"})
        |> ResultsCache.put(:step2, {:error, :timeout})

      assert {:ok, {:error, :timeout}} = ResultsCache.get(cache, :step2)
    end
  end
end

defmodule Cerebelum.PatternMatcherTest do
  use ExUnit.Case, async: true

  alias Cerebelum.PatternMatcher

  describe "match/2 - atoms" do
    test "matches exact atoms" do
      patterns = [
        {:timeout, :retry_action},
        {:invalid_data, :failed_action}
      ]

      assert {:ok, :retry_action} = PatternMatcher.match(patterns, :timeout)
      assert {:ok, :failed_action} = PatternMatcher.match(patterns, :invalid_data)
    end

    test "returns :no_match if no pattern matches" do
      patterns = [{:timeout, :retry_action}]

      assert :no_match = PatternMatcher.match(patterns, :unknown)
    end

    test "empty patterns list always returns :no_match" do
      assert :no_match = PatternMatcher.match([], :anything)
    end
  end

  describe "match/2 - wildcards" do
    test "_ matches any value" do
      patterns = [
        {:timeout, :retry_action},
        {:_, :catch_all_action}
      ]

      assert {:ok, :retry_action} = PatternMatcher.match(patterns, :timeout)
      assert {:ok, :catch_all_action} = PatternMatcher.match(patterns, :anything)
      assert {:ok, :catch_all_action} = PatternMatcher.match(patterns, 123)
      assert {:ok, :catch_all_action} = PatternMatcher.match(patterns, %{data: 1})
    end

    test "_ in tuples matches any value in that position" do
      patterns = [
        {{:error, :_}, :error_action}
      ]

      assert {:ok, :error_action} = PatternMatcher.match(patterns, {:error, :network})
      assert {:ok, :error_action} = PatternMatcher.match(patterns, {:error, :timeout})
      assert :no_match = PatternMatcher.match(patterns, {:ok, :data})
    end
  end

  describe "match/2 - tuples" do
    test "matches exact tuples" do
      patterns = [
        {{:error, :network}, :retry_action},
        {{:error, :validation}, :failed_action}
      ]

      assert {:ok, :retry_action} = PatternMatcher.match(patterns, {:error, :network})
      assert {:ok, :failed_action} = PatternMatcher.match(patterns, {:error, :validation})
    end

    test "matches tuples with wildcards" do
      patterns = [
        {{:error, :out_of_stock}, :back_to_action},
        {{:error, :_}, :generic_error_action}
      ]

      assert {:ok, :back_to_action} = PatternMatcher.match(patterns, {:error, :out_of_stock})
      assert {:ok, :generic_error_action} = PatternMatcher.match(patterns, {:error, :network})
      assert {:ok, :generic_error_action} = PatternMatcher.match(patterns, {:error, :anything})
    end

    test "tuple size must match" do
      patterns = [
        {{:error, :_}, :two_element_action}
      ]

      assert {:ok, :two_element_action} = PatternMatcher.match(patterns, {:error, :network})
      assert :no_match = PatternMatcher.match(patterns, {:error, :network, :extra})
      assert :no_match = PatternMatcher.match(patterns, {:error})
    end
  end

  describe "match/2 - nested structures" do
    test "matches nested tuples" do
      patterns = [
        {{:error, {:validation, :_}}, :validation_action}
      ]

      assert {:ok, :validation_action} =
               PatternMatcher.match(patterns, {:error, {:validation, :email}})

      assert {:ok, :validation_action} =
               PatternMatcher.match(patterns, {:error, {:validation, :phone}})

      assert :no_match = PatternMatcher.match(patterns, {:error, :network})
    end

    test "deeply nested wildcards" do
      patterns = [
        {{:error, {:validation, {:field, :_}}}, :field_error_action}
      ]

      assert {:ok, :field_error_action} =
               PatternMatcher.match(patterns, {:error, {:validation, {:field, :email}}})
    end
  end

  describe "match/2 - order matters" do
    test "returns first matching pattern" do
      patterns = [
        {{:error, :_}, :generic_action},
        {{:error, :network}, :specific_action}
      ]

      # El genérico está primero, así que siempre matchea primero
      assert {:ok, :generic_action} = PatternMatcher.match(patterns, {:error, :network})
    end

    test "specific patterns should come before wildcards" do
      patterns = [
        {{:error, :network}, :specific_action},
        {{:error, :_}, :generic_action}
      ]

      # Ahora el específico está primero
      assert {:ok, :specific_action} = PatternMatcher.match(patterns, {:error, :network})
      assert {:ok, :generic_action} = PatternMatcher.match(patterns, {:error, :other})
    end
  end

  describe "match/2 - complex values" do
    test "matches maps with exact values" do
      patterns = [
        {%{status: :error}, :error_action}
      ]

      assert {:ok, :error_action} = PatternMatcher.match(patterns, %{status: :error})
      assert :no_match = PatternMatcher.match(patterns, %{status: :ok})
    end

    test "matches with wildcard values in maps" do
      patterns = [
        {%{status: :_}, :any_status_action}
      ]

      assert {:ok, :any_status_action} = PatternMatcher.match(patterns, %{status: :error})
      assert {:ok, :any_status_action} = PatternMatcher.match(patterns, %{status: :ok})
      assert {:ok, :any_status_action} = PatternMatcher.match(patterns, %{status: 123})
    end
  end

  describe "matches?/2" do
    test "returns true if pattern matches value" do
      assert PatternMatcher.matches?(:timeout, :timeout)
      assert PatternMatcher.matches?({:error, :_}, {:error, :network})
      assert PatternMatcher.matches?(:_, :anything)
    end

    test "returns false if pattern does not match" do
      refute PatternMatcher.matches?(:timeout, :invalid)
      refute PatternMatcher.matches?({:error, :network}, {:error, :timeout})
      refute PatternMatcher.matches?({:error, :_}, :error)
    end
  end
end

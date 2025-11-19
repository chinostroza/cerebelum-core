defmodule Cerebelum.CondEvaluatorTest do
  use ExUnit.Case, async: true

  alias Cerebelum.CondEvaluator

  describe "evaluate/2 - comparison operators" do
    test "evaluates > (greater than)" do
      conditions = [
        {quote(do: score > 0.8), :high_risk},
        {quote(do: true), :default}
      ]

      assert {:ok, :high_risk} = CondEvaluator.evaluate(conditions, %{score: 0.9})
      assert {:ok, :default} = CondEvaluator.evaluate(conditions, %{score: 0.5})
    end

    test "evaluates < (less than)" do
      conditions = [
        {quote(do: score < 0.3), :low_risk}
      ]

      assert {:ok, :low_risk} = CondEvaluator.evaluate(conditions, %{score: 0.2})
      assert :no_match = CondEvaluator.evaluate(conditions, %{score: 0.5})
    end

    test "evaluates >= (greater or equal)" do
      conditions = [
        {quote(do: score >= 0.5), :pass}
      ]

      assert {:ok, :pass} = CondEvaluator.evaluate(conditions, %{score: 0.5})
      assert {:ok, :pass} = CondEvaluator.evaluate(conditions, %{score: 0.9})
      assert :no_match = CondEvaluator.evaluate(conditions, %{score: 0.4})
    end

    test "evaluates <= (less or equal)" do
      conditions = [
        {quote(do: score <= 0.5), :low}
      ]

      assert {:ok, :low} = CondEvaluator.evaluate(conditions, %{score: 0.5})
      assert {:ok, :low} = CondEvaluator.evaluate(conditions, %{score: 0.3})
      assert :no_match = CondEvaluator.evaluate(conditions, %{score: 0.7})
    end

    test "evaluates == (equal)" do
      conditions = [
        {quote(do: status == :approved), :approved_action}
      ]

      assert {:ok, :approved_action} =
               CondEvaluator.evaluate(conditions, %{status: :approved})

      assert :no_match = CondEvaluator.evaluate(conditions, %{status: :pending})
    end

    test "evaluates != (not equal)" do
      conditions = [
        {quote(do: status != :pending), :process}
      ]

      assert {:ok, :process} = CondEvaluator.evaluate(conditions, %{status: :approved})
      assert :no_match = CondEvaluator.evaluate(conditions, %{status: :pending})
    end
  end

  describe "evaluate/2 - boolean operators" do
    test "evaluates 'and'" do
      conditions = [
        {quote(do: score > 0.5 and score < 0.8), :medium_risk}
      ]

      assert {:ok, :medium_risk} = CondEvaluator.evaluate(conditions, %{score: 0.6})
      assert :no_match = CondEvaluator.evaluate(conditions, %{score: 0.9})
      assert :no_match = CondEvaluator.evaluate(conditions, %{score: 0.3})
    end

    test "evaluates 'or'" do
      conditions = [
        {quote(do: score < 0.3 or score > 0.8), :extreme}
      ]

      assert {:ok, :extreme} = CondEvaluator.evaluate(conditions, %{score: 0.2})
      assert {:ok, :extreme} = CondEvaluator.evaluate(conditions, %{score: 0.9})
      assert :no_match = CondEvaluator.evaluate(conditions, %{score: 0.5})
    end

    test "evaluates 'not'" do
      conditions = [
        {quote(do: not approved), :rejected}
      ]

      assert {:ok, :rejected} = CondEvaluator.evaluate(conditions, %{approved: false})
      assert :no_match = CondEvaluator.evaluate(conditions, %{approved: true})
    end
  end

  describe "evaluate/2 - literals" do
    test "evaluates true literal (catch-all)" do
      conditions = [
        {quote(do: score > 0.8), :high},
        {quote(do: true), :default}
      ]

      assert {:ok, :default} = CondEvaluator.evaluate(conditions, %{score: 0.5})
    end

    test "evaluates false literal" do
      conditions = [
        {quote(do: false), :never_matches},
        {quote(do: true), :always_matches}
      ]

      assert {:ok, :always_matches} = CondEvaluator.evaluate(conditions, %{})
    end
  end

  describe "evaluate/2 - complex conditions" do
    test "evaluates nested boolean expressions" do
      conditions = [
        {quote(do: (score > 0.8 or priority == :high) and not manual_review), :auto_process}
      ]

      # score > 0.8, no manual_review
      assert {:ok, :auto_process} =
               CondEvaluator.evaluate(conditions, %{
                 score: 0.9,
                 priority: :low,
                 manual_review: false
               })

      # priority high, no manual_review
      assert {:ok, :auto_process} =
               CondEvaluator.evaluate(conditions, %{
                 score: 0.5,
                 priority: :high,
                 manual_review: false
               })

      # manual_review = true, no match
      assert :no_match =
               CondEvaluator.evaluate(conditions, %{
                 score: 0.9,
                 priority: :high,
                 manual_review: true
               })
    end

    test "evaluates multiple variable references" do
      conditions = [
        {quote(do: amount > threshold and currency == :usd), :process_usd}
      ]

      assert {:ok, :process_usd} =
               CondEvaluator.evaluate(conditions, %{
                 amount: 1000,
                 threshold: 500,
                 currency: :usd
               })

      assert :no_match =
               CondEvaluator.evaluate(conditions, %{
                 amount: 1000,
                 threshold: 500,
                 currency: :eur
               })
    end
  end

  describe "evaluate/2 - order matters" do
    test "returns first true condition" do
      conditions = [
        {quote(do: score > 0.5), :first},
        {quote(do: score > 0.3), :second},
        {quote(do: true), :third}
      ]

      # 0.9 > 0.5, primera condición
      assert {:ok, :first} = CondEvaluator.evaluate(conditions, %{score: 0.9})

      # 0.4 > 0.3, segunda condición (primera falla)
      assert {:ok, :second} = CondEvaluator.evaluate(conditions, %{score: 0.4})

      # Ninguna se cumple, tercera (catch-all)
      assert {:ok, :third} = CondEvaluator.evaluate(conditions, %{score: 0.2})
    end
  end

  describe "evaluate/2 - edge cases" do
    test "empty conditions returns :no_match" do
      assert :no_match = CondEvaluator.evaluate([], %{})
    end

    test "missing variable in bindings raises error" do
      conditions = [
        {quote(do: missing_var > 10), :action}
      ]

      assert_raise KeyError, fn ->
        CondEvaluator.evaluate(conditions, %{})
      end
    end

    test "handles string comparisons" do
      conditions = [
        {quote(do: name == "Alice"), :alice_action}
      ]

      assert {:ok, :alice_action} = CondEvaluator.evaluate(conditions, %{name: "Alice"})
      assert :no_match = CondEvaluator.evaluate(conditions, %{name: "Bob"})
    end
  end

  describe "eval_condition/2" do
    test "evaluates a single condition to boolean" do
      assert CondEvaluator.eval_condition(quote(do: score > 0.8), %{score: 0.9}) == true
      assert CondEvaluator.eval_condition(quote(do: score > 0.8), %{score: 0.5}) == false
    end

    test "evaluates boolean literals" do
      assert CondEvaluator.eval_condition(quote(do: true), %{}) == true
      assert CondEvaluator.eval_condition(quote(do: false), %{}) == false
    end

    test "evaluates complex expressions" do
      bindings = %{x: 10, y: 20}

      assert CondEvaluator.eval_condition(quote(do: x > 5 and y < 30), bindings) == true
      assert CondEvaluator.eval_condition(quote(do: x > 15 or y == 20), bindings) == true
      assert CondEvaluator.eval_condition(quote(do: not (x > 15)), bindings) == true
    end

    test "raises KeyError with detailed message when variable is missing" do
      assert_raise KeyError, ~r/Variable 'missing_var' not found in bindings/, fn ->
        CondEvaluator.eval_condition(quote(do: missing_var > 10), %{other: 1})
      end
    end

    test "raises KeyError listing available variables when variable is missing" do
      error =
        assert_raise KeyError, fn ->
          CondEvaluator.eval_condition(quote(do: x > 10), %{y: 1, z: 2})
        end

      assert error.message =~ "Available variables: [:y, :z]"
      assert error.message =~ "Condition: x > 10"
    end

    test "raises CompileError for invalid syntax in condition" do
      # Create invalid AST that will cause compilation error
      invalid_ast = {:invalid_operator, [], [:x, :y]}

      assert_raise CompileError, ~r/Invalid condition syntax/, fn ->
        CondEvaluator.eval_condition(invalid_ast, %{x: 1, y: 2})
      end
    end
  end
end

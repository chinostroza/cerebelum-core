defmodule CerebelumCoreTest do
  use ExUnit.Case
  doctest CerebelumCore

  test "greets the world" do
    assert CerebelumCore.hello() == :world
  end
end

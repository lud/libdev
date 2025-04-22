defmodule LibdevTest do
  use ExUnit.Case
  doctest Libdev

  test "greets the world" do
    assert Libdev.hello() == :world
  end
end

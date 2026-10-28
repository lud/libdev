defmodule Mix.Tasks.Libdev.CheckTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Libdev.Check

  @checks [credo: [], docs: [], dialyzer: false]

  test "no skip option" do
    assert {:ok, []} = Check.parse_skip([], @checks)
  end

  test "repeated names are accepted" do
    assert {:ok, [:credo, :docs]} = Check.parse_skip(["credo", "docs"], @checks)
    assert {:ok, [:credo, :docs]} = Check.parse_skip(["credo", "docs", "credo"], @checks)
  end

  test "disabled checks can be named and are dropped" do
    assert {:ok, [:credo]} = Check.parse_skip(["dialyzer", "credo"], @checks)
  end

  test "unknown names are rejected with the list of known checks" do
    assert {:error, errmsg} = Check.parse_skip(["credo", "doc"], @checks)
    assert errmsg =~ ~s("doc")
    assert errmsg =~ "credo, docs, dialyzer"
  end

  test "pre-checks cannot be skipped" do
    assert {:error, _} = Check.parse_skip(["compile"], @checks)
  end
end

defmodule Libdev.Runner.CycleInvariantTest do
  use ExUnit.Case, async: true

  alias Libdev.Runner.Cycle

  @pool [:a, :b, :c]
  @recorded [:pass, :fail, :absent]

  defp manifests do
    Enum.reduce(@pool, [%{}], fn id, acc ->
      for m <- acc, st <- @recorded do
        record(m, id, st)
      end
    end)
  end

  defp record(manifest, _id, :absent) do
    manifest
  end

  defp record(manifest, id, status) do
    Map.put(manifest, id, status)
  end

  defp drive(cycle, pool, verdict, planned \\ []) do
    case Cycle.plan(cycle, pool) do
      {:done, cycle} ->
        {cycle, planned}

      {:run, ids, cycle} ->
        results = Map.new(ids, &{&1, verdict.(&1)})

        case Cycle.plan(cycle, pool, results) do
          {:done, cycle} -> {cycle, planned ++ ids}
          {:run, _, cycle} -> drive(cycle, pool, verdict, planned ++ ids)
        end
    end
  end

  test "whatever the manifest holds, a green cycle ran every tool of the pool exactly once" do
    for manifest <- manifests(), pool <- [@pool, [:a, :b], []] do
      {cycle, planned} = drive(Cycle.new(manifest), pool, fn _ -> :pass end)

      assert Enum.sort(planned) == Enum.sort(pool), inspect({manifest, pool, planned})
      assert Cycle.success?(cycle) == (pool != []), inspect({manifest, pool})
    end
  end

  test "whatever the manifest holds, a failure never leads to a green cycle" do
    for manifest <- manifests(), failing <- @pool do
      {cycle, planned} =
        drive(
          Cycle.new(manifest),
          @pool,
          fn id ->
            if id == failing do
              :fail
            else
              :pass
            end
          end
        )

      assert failing in planned
      refute Cycle.success?(cycle), inspect({manifest, failing})
    end
  end
end

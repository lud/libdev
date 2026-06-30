defmodule Libdev.Runner.Cycle do
  @moduledoc false
  def new do
    %{}
  end

  def new(old_cycle) when is_map(old_cycle) do
    old_cycle
    |> Enum.flat_map(fn
      {k, :pass} -> [{k, :stale_pass}]
      {k, :fail} -> [{k, :stale_fail}]
      _ -> []
    end)
    |> Map.new()
  end

  def plan(cycle, ids, results \\ %{})

  def plan(cycle, ids, results) do
    cycle =
      cycle
      |> Map.merge(results)
      |> Map.take(ids)
      |> Enum.into(Map.new(ids, &{&1, :unknown}))

    flags =
      Map.new(ids, fn id ->
        {Map.get(cycle, id, :unknown), true}
      end)

    case flags do
      %{fail: true} ->
        {:done, cycle}

      %{stale_fail: true} ->
        {:run, ids_with_statuses(cycle, ids, [:stale_fail, :unknown]), cycle}

      %{stale_pass: true} ->
        {:run, ids_with_statuses(cycle, ids, [:stale_pass, :unknown]), cycle}

      %{unknown: true} ->
        {:run, ids_with_statuses(cycle, ids, [:unknown]), cycle}

      _ ->
        {:done, cycle}
    end
  end

  defp ids_with_statuses(cycle, ids, statuses) do
    Enum.filter(ids, &(Map.fetch!(cycle, &1) in statuses))
  end

  def success?(map) when map_size(map) == 0 do
    false
  end

  def success?(map) when map_size(map) > 0 do
    Enum.all?(map, fn {_, v} -> v == :pass end)
  end
end

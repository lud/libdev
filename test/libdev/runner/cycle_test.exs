defmodule Libdev.Runner.CycleTest do
  use ExUnit.Case, async: true

  alias Libdev.Runner.Cycle

  describe "first ever cycle (empty state)" do
    test "plan returns every tool in the pool" do
      assert {:run, [:a, :b, :c, :d], _} = Cycle.plan(Cycle.new(), [:a, :b, :c, :d], %{})
    end

    test "an empty pool is immediately :done" do
      assert {:done, _} = Cycle.plan(Cycle.new(), [], %{})
    end

    test "after every tool passes, plan returns :done" do
      {:run, _, state} = Cycle.plan(Cycle.new(), [:a, :b], %{})
      assert {:done, _} = Cycle.plan(state, [:a, :b], %{a: :pass, b: :pass})
    end

    test "after any failure, plan returns :done" do
      {:run, _, state} = Cycle.plan(Cycle.new(), [:a, :b, :c], %{})
      assert {:done, _} = Cycle.plan(state, [:a, :b, :c], %{a: :pass, b: :pass, c: :fail})
    end
  end

  describe "pool changes between cycles" do
    test "a previously-failing tool dropped from the pool is skipped" do
      prior = finish_cycle([:a, :b, :c], %{a: :pass, b: :pass, c: :fail})
      state = Cycle.new(prior)
      assert {:run, [:a, :b], _} = Cycle.plan(state, [:a, :b], %{})
    end

    test "a brand-new tool runs alongside the rest when there are no prior failures" do
      prior = finish_cycle([:a, :b], %{a: :pass, b: :pass})
      state = Cycle.new(prior)
      assert {:run, [:a, :b, :c], _} = Cycle.plan(state, [:a, :b, :c], %{})
    end

    test "a brand-new tool runs alongside failing tools when there are prior failures" do
      # Prior failure: :b. New tool: :c. Stale: :a.
      # Batch = failures + new; the stale (:a) sits out this cycle.
      prior = finish_cycle([:a, :b], %{a: :pass, b: :fail})
      state = Cycle.new(prior)
      assert {:run, [:b, :c], _} = Cycle.plan(state, [:a, :b, :c], %{})
    end
  end

  describe "subsequent cycle (rotated via Cycle.new/1)" do
    test "after a fully-successful prior cycle, every tool runs again" do
      # Cycle 1 finished green — persisted state is %{a: :pass, b: :pass}.
      # Cycle 2 must re-verify everything; a stale pass is not the same as a fresh pass.
      prior = finish_cycle([:a, :b], %{a: :pass, b: :pass})
      state = Cycle.new(prior)
      assert {:run, [:a, :b], _} = Cycle.plan(state, [:a, :b], %{})
    end

    test "after a prior cycle with failures, only the failing tools run again" do
      # Stales (:a, :b) sit out — they'll be re-verified on the next clean cycle.
      prior =
        finish_cycle([:a, :b, :c, :d], %{a: :pass, b: :pass, c: :fail, d: :fail})

      state = Cycle.new(prior)
      assert {:run, [:c, :d], _} = Cycle.plan(state, [:a, :b, :c, :d], %{})
    end

    test "any failure recorded in the batch ends the cycle" do
      prior =
        finish_cycle([:a, :b, :c, :d], %{a: :pass, b: :pass, c: :fail, d: :fail})

      state = Cycle.new(prior)
      {:run, _, state} = Cycle.plan(state, [:a, :b, :c, :d], %{})

      assert {:done, _} =
               Cycle.plan(state, [:a, :b, :c, :d], %{a: :pass, b: :pass, c: :pass, d: :fail})
    end

    test "after the failure batch clears, the stale tools run, then :done" do
      # Phase 1: failures (:b) + new (:c). Stale :a sits out this batch.
      # Phase 2: now that failures are clear, the stale :a is re-verified.
      # Then :done.
      prior = finish_cycle([:a, :b], %{a: :pass, b: :fail})
      state = Cycle.new(prior)

      assert {:run, [:b, :c], state} = Cycle.plan(state, [:a, :b, :c], %{})
      assert {:run, [:a], state} = Cycle.plan(state, [:a, :b, :c], %{b: :pass, c: :pass})
      assert {:done, _} = Cycle.plan(state, [:a, :b, :c], %{a: :pass})
    end

    test "state carries the latest known status forward across cycles" do
      # Cycle 1: :a fails, :b passes.
      cycle1 = finish_cycle([:a, :b], %{a: :fail, b: :pass})

      # Cycle 2: phase 1 = [:a] (failure focus). Phase 2 = [:b] (stale). Then :done.
      state = Cycle.new(cycle1)
      {:run, _, state} = Cycle.plan(state, [:a, :b], %{})
      {:run, _, state} = Cycle.plan(state, [:a, :b], %{a: :pass})
      {:done, cycle2} = Cycle.plan(state, [:a, :b], %{b: :pass})

      # Cycle 3: no prior failures — plan re-verifies the whole pool.
      state = Cycle.new(cycle2)
      assert {:run, [:a, :b], _} = Cycle.plan(state, [:a, :b], %{})
    end
  end

  describe "success?/1" do
    test "is false on a fresh state" do
      refute Cycle.success?(Cycle.new())
    end

    test "is false on a freshly-rotated state (cycle hasn't started yet)" do
      prior = finish_cycle([:a, :b], %{a: :pass, b: :pass})
      refute Cycle.success?(Cycle.new(prior))
    end

    test "is false mid-cycle (between :run and :done)" do
      {:run, _, state} = Cycle.plan(Cycle.new(), [:a, :b], %{})
      refute Cycle.success?(state)
    end

    test "is true after a cycle in which every tool passed" do
      {:run, _, state} = Cycle.plan(Cycle.new(), [:a, :b], %{})
      {:done, state} = Cycle.plan(state, [:a, :b], %{a: :pass, b: :pass})
      assert Cycle.success?(state)
    end

    test "is false after a cycle that ended on a failure" do
      {:run, _, state} = Cycle.plan(Cycle.new(), [:a, :b], %{})
      {:done, state} = Cycle.plan(state, [:a, :b], %{a: :pass, b: :fail})
      refute Cycle.success?(state)
    end
  end

  describe "plan/3 is idempotent with empty results" do
    test "consecutive plan calls on a fresh state return the same to_run set" do
      assert {:run, [:a, :b, :c], state} = Cycle.plan(Cycle.new(), [:a, :b, :c], %{})
      assert {:run, [:a, :b, :c], _} = Cycle.plan(state, [:a, :b, :c], %{})
    end

    test "consecutive plan calls on a rotated state return the same to_run set" do
      prior = finish_cycle([:a, :b, :c], %{a: :pass, b: :pass, c: :fail})
      state = Cycle.new(prior)
      assert {:run, [:c], state} = Cycle.plan(state, [:a, :b, :c], %{})
      assert {:run, [:c], _} = Cycle.plan(state, [:a, :b, :c], %{})
    end
  end

  describe "partial results loop back to :run" do
    test "if the caller records results for only some ids in the batch, the rest re-appear" do
      {:run, _, state} = Cycle.plan(Cycle.new(), [:a, :b, :c], %{})
      assert {:run, [:b, :c], _} = Cycle.plan(state, [:a, :b, :c], %{a: :pass})
    end
  end

  describe "to_run order" do
    test "ids are returned in the order they appear in the pool" do
      prior = finish_cycle([:a, :b, :c, :d], %{a: :pass, b: :pass, c: :fail, d: :fail})
      state = Cycle.new(prior)
      # Pool in non-alphabetical order — the failures come back in pool order,
      # not sorted.
      assert {:run, [:d, :c], _} = Cycle.plan(state, [:d, :a, :c, :b], %{})
    end
  end

  # Helpers ----------------------------------------------------------------

  defp finish_cycle(pool, results) do
    state = Cycle.new()
    {:run, _, state} = Cycle.plan(state, pool, %{})
    {:done, state} = Cycle.plan(state, pool, results)
    state
  end
end

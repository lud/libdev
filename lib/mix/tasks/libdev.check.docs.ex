defmodule Mix.Tasks.Libdev.Check.Docs do
  use Mix.Task

  @shortdoc "Checks moduledoc and function documentation coverage"
  @requirements ["app.config"]

  @default_min_module_coverage 100.0
  @default_min_function_coverage 100.0

  @moduledoc """
  Checks that the project's modules and public functions are documented.

  The task compiles the project, inspects the documentation metadata of every
  module of the current application and reports the modules that have at least
  one documentation problem.

  Modules with `@moduledoc false` are ignored entirely: their public functions
  do not count towards the coverage thresholds and are never checked. Functions
  implementing a behaviour callback are also skipped.

  ## Options

    * `--min-module-coverage` - the minimum percentage of modules that must have
      a `@moduledoc`. Defaults to `#{@default_min_module_coverage}`.
    * `--min-function-coverage` - the minimum percentage of public functions that
      must have a `@doc`. Defaults to `#{@default_min_function_coverage}`.
  """

  @impl Mix.Task
  def run(argv) do
    {opts, _argv} =
      OptionParser.parse!(argv,
        strict: [min_module_coverage: :float, min_function_coverage: :float]
      )

    min_module_coverage =
      Keyword.get(opts, :min_module_coverage, @default_min_module_coverage)

    min_function_coverage =
      Keyword.get(opts, :min_function_coverage, @default_min_function_coverage)

    {report, counts} = build_report()

    report = Enum.sort_by(report, & &1.module)

    # Always print the problems first, so that the threshold results stay at the
    # bottom and remain visible even when the report is huge.
    print_report(report)

    module_coverage = coverage(counts.module_ok, counts.module_count)
    function_coverage = coverage(counts.function_ok, counts.function_count)

    module_pass? = module_coverage >= min_module_coverage
    function_pass? = function_coverage >= min_function_coverage

    IO.puts("")
    print_threshold("Module coverage", module_coverage, min_module_coverage, module_pass?)

    print_threshold(
      "Function coverage",
      function_coverage,
      min_function_coverage,
      function_pass?
    )

    if !(module_pass? and function_pass?) do
      System.halt(1)
    end
  end

  defp build_report do
    app = Keyword.fetch!(Mix.Project.config(), :app)
    {:ok, modules} = :application.get_key(app, :modules)

    accin = %{
      module_count: 0,
      module_ok: 0,
      module_missing: 0,
      function_count: 0,
      function_ok: 0,
      function_missing: 0
    }

    Enum.flat_map_reduce(modules, accin, &reduce_module/2)
  end

  defp reduce_module(module, acc) do
    case Code.fetch_docs(module) do
      # `@moduledoc false` modules are ignored entirely.
      {:docs_v1, _anno, _lang, _format, :hidden, _meta, _docs} ->
        {[], acc}

      {:docs_v1, _anno, _lang, _format, moduledoc, meta, docs} ->
        moduledoc_status =
          if moduledoc == :none do
            :missing
          else
            :ok
          end

        {functions, fun_counts} = missing_function_docs(docs, meta)

        functions = Enum.sort_by(functions, & &1.function)

        acc =
          acc
          |> count_module(moduledoc_status)
          |> merge_counts(fun_counts)

        reports =
          case {moduledoc_status, functions} do
            {:ok, []} -> []
            _ -> [build_entry(module, moduledoc_status, functions)]
          end

        {reports, acc}

      # No docs chunk available (e.g. compiled without docs): nothing to check.
      {:error, _reason} ->
        {[], acc}
    end
  end

  defp build_entry(module, moduledoc, missing_functions) do
    %{module: module, moduledoc: moduledoc, functions: missing_functions}
  end

  defp missing_function_docs(docs, module_meta) do
    docs = filter_functions(docs, module_meta)

    accin = %{function_count: 0, function_ok: 0, function_missing: 0}

    Enum.flat_map_reduce(docs, accin, fn
      {{kind, name, arity}, _anno, _signature, doc, _meta}, counts
      when kind in [:function, :macro] ->
        case doc do
          :none ->
            {[%{function: name, arity: arity, doc: :missing}], count_function(counts, :missing)}

          _ ->
            {[], count_function(counts, :ok)}
        end

      _other, counts ->
        {[], counts}
    end)
  end

  # Skip the callbacks of every behaviour the module implements: their
  # implementations are conventionally left undocumented (e.g. `handle_call/3`,
  # `init/1`, `run/1`, ...).
  defp filter_functions(docs, %{behaviours: [_ | _] = behaviours}) do
    Enum.reduce(behaviours, docs, fn behaviour, docs ->
      skip_defs(docs, behaviour_callbacks(behaviour))
    end)
  end

  defp filter_functions(docs, _module_meta) do
    docs
  end

  defp behaviour_callbacks(module) do
    pkey = {__MODULE__, :behaviour, module}

    case Process.get(pkey, :__undef__) do
      :__undef__ ->
        callbacks =
          try do
            module.behaviour_info(:callbacks)
          rescue
            UndefinedFunctionError -> []
          end

        Process.put(pkey, callbacks)
        callbacks

      callbacks ->
        callbacks
    end
  end

  defp skip_defs(docs, fun_arities) do
    Enum.reduce(fun_arities, docs, fn fun_arity, docs -> skip_def(docs, fun_arity) end)
  end

  defp skip_def(docs, {fun, arity}) do
    Enum.filter(docs, fn
      {{:function, ^fun, ^arity}, _anno, _signature, _doc, _meta} -> false
      _ -> true
    end)
  end

  defp count_module(acc, :missing) do
    acc
    |> increment(:module_count)
    |> increment(:module_missing)
  end

  defp count_module(acc, :ok) do
    acc
    |> increment(:module_count)
    |> increment(:module_ok)
  end

  defp count_function(acc, :missing) do
    acc
    |> increment(:function_count)
    |> increment(:function_missing)
  end

  defp count_function(acc, :ok) do
    acc
    |> increment(:function_count)
    |> increment(:function_ok)
  end

  defp merge_counts(counts_a, counts_b) do
    Map.merge(counts_a, counts_b, fn _, a, b -> a + b end)
  end

  defp increment(map, key) do
    Map.update!(map, key, &(&1 + 1))
  end

  defp coverage(_ok, 0) do
    100.0
  end

  defp coverage(ok, total) do
    ok / total * 100
  end

  defp print_report([]) do
    IO.puts([IO.ANSI.green(), "Documentation is complete", IO.ANSI.reset()])
  end

  defp print_report(report) do
    IO.puts([IO.ANSI.red(), "Documentation coverage is below threshold", IO.ANSI.reset()])
    Enum.each(report, &print_module_entry/1)
  end

  defp print_module_entry(entry) do
    IO.puts("")
    IO.puts([IO.ANSI.bright(), IO.ANSI.yellow(), inspect(entry.module), IO.ANSI.reset()])

    if entry.moduledoc == :missing do
      IO.puts("  - missing @moduledoc")
    end

    Enum.each(entry.functions, fn fun ->
      IO.puts("  - missing @doc for #{fun.function}/#{fun.arity}")
    end)
  end

  defp print_threshold(label, coverage, min, pass?) do
    color =
      if pass? do
        IO.ANSI.green()
      else
        IO.ANSI.red()
      end

    IO.puts([
      color,
      String.pad_trailing(label, 20),
      " ",
      format_pct(coverage),
      " (min ",
      format_pct(min),
      ")",
      IO.ANSI.reset()
    ])
  end

  defp format_pct(value) do
    :erlang.float_to_binary(value, decimals: 1) <> "%"
  end
end

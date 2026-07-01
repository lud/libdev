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
  one documentation problem. Each problem is reported with the source file and
  line of the definition that misses its documentation.

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

    module_coverage = coverage(counts.module_ok, counts.module_count)
    function_coverage = coverage(counts.function_ok, counts.function_count)

    module_pass? = module_coverage >= min_module_coverage
    function_pass? = function_coverage >= min_function_coverage

    # The problems come first, so that the threshold results stay at the
    # bottom and remain visible even when the report is huge.
    lines =
      report_lines(report) ++
        [
          "",
          threshold_line("Module coverage", module_coverage, min_module_coverage, module_pass?),
          threshold_line(
            "Function coverage",
            function_coverage,
            min_function_coverage,
            function_pass?
          )
        ]

    lines |> Enum.intersperse("\n") |> IO.ANSI.format() |> IO.puts()

    if !(module_pass? and function_pass?) do
      System.halt(1)
    end
  end

  defp build_report do
    app = Keyword.fetch!(Mix.Project.config(), :app)
    {:ok, modules} = :application.get_key(app, :modules)

    Enum.flat_map_reduce(modules, new_counts(), &reduce_module/2)
  end

  defp new_counts do
    %{
      module_count: 0,
      module_ok: 0,
      module_missing: 0,
      function_count: 0,
      function_ok: 0,
      function_missing: 0
    }
  end

  @doc false
  def scan_module(module) do
    reduce_module(module, new_counts())
  end

  defp reduce_module(module, acc) do
    case Code.fetch_docs(module) do
      # `@moduledoc false` modules are ignored entirely.
      {:docs_v1, _anno, _lang, _format, :hidden, _meta, _docs} ->
        {[], acc}

      {:docs_v1, anno, _lang, _format, moduledoc, meta, docs} ->
        source_path = source_path(meta)

        moduledoc_status =
          if moduledoc == :none do
            :missing
          else
            :ok
          end

        {functions, fun_counts} = missing_function_docs(docs, meta, source_path)

        functions = Enum.sort_by(functions, & &1.function)

        acc =
          acc
          |> count_module(moduledoc_status)
          |> merge_counts(fun_counts)

        reports =
          case {moduledoc_status, functions} do
            {:ok, []} ->
              []

            _ ->
              location = entry_location(source_path, meta, anno)
              [build_entry(module, moduledoc_status, functions, location)]
          end

        {reports, acc}

      # No docs chunk available (e.g. compiled without docs): nothing to check.
      {:error, _reason} ->
        {[], acc}
    end
  end

  defp build_entry(module, moduledoc, missing_functions, location) do
    %{module: module, moduledoc: moduledoc, functions: missing_functions, location: location}
  end

  defp missing_function_docs(docs, module_meta, source_path) do
    docs = filter_functions(docs, module_meta)

    accin = %{function_count: 0, function_ok: 0, function_missing: 0}

    Enum.flat_map_reduce(docs, accin, fn
      {{kind, name, arity}, anno, _signature, doc, fun_meta}, counts
      when kind in [:function, :macro] ->
        case doc do
          :none ->
            entry = %{
              function: name,
              arity: arity,
              doc: :missing,
              location: entry_location(source_path, fun_meta, anno)
            }

            {[entry], count_function(counts, :missing)}

          _ ->
            {[], count_function(counts, :ok)}
        end

      _other, counts ->
        {[], counts}
    end)
  end

  # The docs chunk gives two locations for an entry: the `:source_annos`
  # metadata points at the `defmodule`/`def` itself while the entry anno points
  # at the documentation attributes above it. Prefer the definition site.
  defp entry_location(nil, _meta, _anno) do
    nil
  end

  defp entry_location(source_path, meta, anno) do
    source_anno_line =
      case meta do
        %{source_annos: [first | _]} -> anno_line(first)
        _ -> nil
      end

    case source_anno_line || anno_line(anno) do
      nil -> source_path
      line -> "#{source_path}:#{line}"
    end
  end

  defp anno_line(line) when is_integer(line) do
    line
  end

  defp anno_line({line, _column}) when is_integer(line) do
    line
  end

  defp anno_line(anno) when is_list(anno) do
    anno_line(:proplists.get_value(:location, anno, nil))
  end

  defp anno_line(_other) do
    nil
  end

  defp source_path(%{source_path: path}) do
    path |> to_string() |> Path.relative_to_cwd()
  end

  defp source_path(_meta) do
    nil
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

  defp report_lines([]) do
    [[:green, "Documentation is complete", :reset]]
  end

  defp report_lines(report) do
    header = [:red, "Documentation coverage is below threshold", :reset]

    [header | Enum.flat_map(report, &module_entry_lines/1)]
  end

  defp module_entry_lines(entry) do
    module_line = [:bright, :yellow, inspect(entry.module), :reset]

    moduledoc_lines =
      if entry.moduledoc == :missing do
        [["  - missing ", :bright, "@moduledoc", :reset, location_suffix(entry.location)]]
      else
        []
      end

    function_lines =
      Enum.map(entry.functions, fn fun ->
        [
          "  - missing ",
          :bright,
          "@doc",
          :reset,
          " for ",
          :yellow,
          "#{fun.function}/#{fun.arity}",
          :reset,
          location_suffix(fun.location)
        ]
      end)

    ["", module_line | moduledoc_lines ++ function_lines]
  end

  defp location_suffix(nil) do
    []
  end

  defp location_suffix(location) do
    [:faint, " (", location, ")", :reset]
  end

  defp threshold_line(label, coverage, min, pass?) do
    color =
      if pass? do
        :green
      else
        :red
      end

    [
      color,
      String.pad_trailing(label, 20),
      " ",
      format_pct(coverage),
      " (min ",
      format_pct(min),
      ")",
      :reset
    ]
  end

  defp format_pct(value) do
    :erlang.float_to_binary(value, decimals: 1) <> "%"
  end
end

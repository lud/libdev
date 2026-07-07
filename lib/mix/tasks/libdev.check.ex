defmodule Mix.Tasks.Libdev.Check do
  use Mix.Task
  alias Libdev.XConf

  @shortdoc "Compiles the project and runs the configured static checks"

  @pre_checks [
    compile: [],
    compile_test: [mix_task: "compile", env: %{"MIX_ENV" => "test"}]
  ]

  @default_checks [
    credo: [argv: ~w(--all --strict)],
    format: [argv: ~w(--check-formatted)],
    test: [argv: ~w(--warnings-as-errors)],
    docs: [],
    docs_check: [mix_task: "libdev.check.docs"],
    hex_audit: [mix_task: "hex.audit"],
    sobelow: [argv: ~w(--skip)],
    dialyzer: []
  ]

  @sample_config_checks [
    credo: [argv: ~w(--all --no-strict)],
    docs: [env: %{"MIX_ENV" => "docs"}],
    dialyzer: false
  ]

  @sample_replace_checks [
    sobelow: [argv: []]
  ]

  @sample_custom_checks [
    coverage: [mix_task: "coveralls", argv: ~w(--raise)],
    gettext: []
  ]

  [_ | _] = sobelow_example_args = get_in(@default_checks, [:sobelow, :argv])

  @moduledoc """
  Runs a suite of static checks for the library.

  The task works in three steps:

    1. Compile the project (and the test environment) as pre-checks. If
       compilation fails, nothing else runs.
    2. Run the checks (formatting, tests, docs, dependency audit, static
       analysis, ...).
    3. Print a summary of every check with its status and run time.

  ## Re-running failures

  To keep feedback fast, the task remembers the result of the previous run and
  re-runs only the checks that failed. Stale passing checks are skipped while
  failures remain.

  This is only an optimization: as soon as the previously failing checks pass
  again, the task runs the remaining checks before reporting. An all-green
  result therefore always means every check ran and passed in this run.

  There is no all-green result that covered only a subset of the checks.

  Pass `--all` to ignore the remembered result and run every check from scratch.

  ```console
  mix libdev.check --all
  ```

  ## Configuration

  Configuration is read from a `.libdev.exs` file located at the **root of your
  project** (the directory where you run `mix libdev.check`). The file is
  optional: when it is missing the default checks are used as-is. It must
  evaluate to a keyword list, and checks are configured under the top-level
  `:checks` key.

  The default checks are run as if your `.libdev.exs` contained the following:

  ```elixir
  # .libdev.exs
  #{inspect([checks: @default_checks], pretty: true)}
  ```

  You can override some checks by adding configuration that is _deeply merged_
  into the default configuration. Disable a check completely with `false`.

  ```elixir
  # .libdev.exs
  #{inspect([checks: @sample_config_checks], pretty: true)}
  ```

  ### Check options

  Each check value is either a boolean or a keyword list:

    * `false` - disable the check entirely.
    * `true` - keep the default configuration for the check (useful to undo a
      `false` coming from another configuration layer).
    * a keyword list to override the default's options. Supported options are:

      * `:mix_task` - a string naming the Mix task to run for this check, when
        it differs from the check name (e.g. `"hex.audit"` for the `:hex_audit`
        check).
      * `:argv` - a list of strings appended to the underlying command's
        arguments (e.g. `["--check-formatted"]`).
      * `:env` - environment variables to set for the check, as a map or keyword
        list of `string => string` (e.g. `%{"MIX_ENV" => "test"}`).

  Overrides are deeply merged, so specifying one option leaves the other default
  options of that check untouched. The values themselves are replaced, not
  combined: a given `:argv` or `:env` overrides the default outright rather than
  appending to it. For instance, the default `:sobelow` check passes
  `#{inspect(sobelow_example_args)}`;
  override `:argv` with an empty list to drop that argument:

  ```elixir
  # .libdev.exs
  #{inspect([checks: @sample_replace_checks], pretty: true)}
  ```

  ### Custom checks

  The `:checks` list is not limited to the built-in checks above. Any extra
  entry is run as its own check: its key is used as the name of the Mix task to
  run, so `my_task: []` runs `mix my_task`. Use `:mix_task` when the task name
  differs from the key, plus `:argv`/`:env` as needed. The only requirement is
  that the Mix task exists in your project.

  ```elixir
  # .libdev.exs
  #{inspect([checks: @sample_custom_checks], pretty: true)}
  ```
  """

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: [all: :boolean])

    conf = load_config!()

    checks =
      case XConf.fetch(conf, :checks, {:keyword, &validate_check/1}, []) do
        {:ok, raw_user_checks} -> build_user_checks(raw_user_checks)
        {:error, errmsg} -> abort(errmsg)
      end

    case checks do
      [] -> :ok
      _ -> Libdev.Runner.run(pre_checks: @pre_checks, checks: checks, all: opts[:all] || false)
    end
  end

  defp load_config! do
    case Libdev.XConf.read_config_file(Path.join(File.cwd!(), ".libdev.exs")) do
      {:ok, conf} ->
        conf

      {:error, errmsg} ->
        abort(errmsg)
    end
  end

  @spec abort(binary) :: no_return
  defp abort(errmsg) do
    Mix.Shell.IO.error(errmsg)
    System.halt(1)
  end

  defp build_user_checks(raw_user_checks) do
    merged = merge_checks(@default_checks, raw_user_checks)

    Enum.flat_map(merged, fn
      {_, false} -> []
      {key, true} -> [{key, []}]
      kv -> [kv]
    end)
  end

  defp merge_checks(checks_a, checks_b) do
    Keyword.merge(checks_a, checks_b, fn
      _, _, false ->
        false

      _, check_a, true ->
        check_a

      _, check_a, check_b ->
        Keyword.merge(check_a, check_b, &deep_merge/3)
    end)
  end

  defp deep_merge(_key, value1, value2) do
    if Keyword.keyword?(value1) and Keyword.keyword?(value2) do
      Keyword.merge(value1, value2, &deep_merge/3)
    else
      value2
    end
  end

  defp validate_check(bool) when is_boolean(bool) do
    {:ok, bool}
  end

  defp validate_check(raw) do
    with {:keyword?, true} <- {:keyword?, Keyword.keyword?(raw)},
         :ok <- validate_check(:argv, raw),
         :ok <- validate_check(:mix_task, raw),
         :ok <- validate_check(:env, raw) do
      {:ok, raw}
    else
      {:keyword?, false} ->
        {:error, "invalid check, expected a keyword or boolean, got: #{inspect(raw)}"}

      {:error, _} = err ->
        err
    end
  end

  defp validate_check(key, raw) do
    validate_check_value(key, Keyword.get(raw, key, :__undef__))
  end

  defp validate_check_value(_key, :__undef__) do
    :ok
  end

  defp validate_check_value(:argv, argv) do
    if is_list(argv) and Enum.all?(argv, &is_binary/1) do
      :ok
    else
      {:error, ":argv must be a list of binaries, got: #{inspect(argv)}"}
    end
  end

  defp validate_check_value(:mix_task, mix_task) do
    if is_binary(mix_task) do
      :ok
    else
      {:error, ":mix_task must be a binary, got: #{inspect(mix_task)}"}
    end
  end

  defp validate_check_value(:env, env) when is_map(env) or is_list(env) do
    if Enum.all?(env, fn
         {k, v} -> is_binary(k) and is_binary(v)
         _ -> false
       end) do
      :ok
    else
      {:error, ":env must be a map or keyword list of string => string, got: #{inspect(env)}"}
    end
  end

  defp validate_check_value(:env, env) do
    {:error, ":env must be a map or keyword list of string => string, got: #{inspect(env)}"}
  end
end

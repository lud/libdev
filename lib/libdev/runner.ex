defmodule Libdev.Runner do
  @moduledoc false

  alias Libdev.Runner.Cycle

  defmodule CommandState do
    @moduledoc false
    @enforce_keys [
      :id,
      :command,
      :opts,
      :port,
      :exit_status,
      :output,
      :port_opts,
      :started_at,
      :finished_at
    ]
    defstruct @enforce_keys

    defimpl Inspect do
      def inspect(t, _) do
        "#CommandState<#{status(t)}#{t.id}}>"
      end

      defp status(t) do
        case t.exit_status do
          nil -> "."
          0 -> "✔"
          _ -> "✘"
        end
      end
    end
  end

  def run(opts) do
    pre_checks = Keyword.fetch!(opts, :pre_checks)
    checks = Keyword.fetch!(opts, :checks)
    all? = Keyword.get(opts, :all, false)

    ctx = %{elixir_exe: :os.find_executable(~c"elixir"), started_at: now(), finished_at: nil}
    compile_batch = run_batch(prepare_batch(pre_checks), ctx)

    last_batch =
      if all_success?(compile_batch) do
        run_staged(checks, ctx, all?)
      else
        compile_batch
      end

    _ = summarize_batch(last_batch, %{ctx | finished_at: now()})

    if not all_success?(last_batch) do
      System.halt(1)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp load_manifest do
    with {:ok, json} <- File.read(manifest_path()),
         {:ok, manifest} when is_map(manifest) <- JSON.decode(json) do
      cast_manifest(manifest)
    else
      _ -> %{}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp write_manifest(states) do
    json = json_encode_pretty!(states)
    File.write!(manifest_path(), json)
  end

  defp update_manifest(manifest, states, all_ids) do
    manifest =
      manifest
      |> Map.merge(states)
      |> Map.filter(fn {k, _} -> k in all_ids end)

    write_manifest(manifest)
    manifest
  end

  if Code.ensure_loaded?(:json) and function_exported?(:json, :format, 1) do
    def json_encode_pretty!(term) do
      :json.format(term)
    end
  else
    def json_encode_pretty!(term) do
      JSON.encode_to_iodata!(term)
    end
  end

  defp manifest_path do
    cwd = File.cwd!()
    base = Path.basename(cwd)
    Path.join(System.tmp_dir!(), "libdev-#{unique_id(base, cwd, "-")}.manifest.json")
  end

  defp cast_manifest(map) when is_map(map) do
    Map.new(map, fn
      {k, "pass"} -> {k, :pass}
      {k, "fail"} -> {k, :fail}
    end)
  end

  defp run_staged(checks, ctx, all?) do
    batch_all = prepare_batch(checks)
    all_ids = Enum.map(batch_all, & &1.id)

    manifest =
      if all? do
        %{}
      else
        load_manifest()
      end

    cycle = Cycle.new(manifest)

    # Stage 1 is potentially partial: when the manifest holds prior failures, the
    # cycle only re-runs those (plus brand-new checks) and leaves the stale passes
    # for stage 2.
    {:run, ids_stage_1, cycle} = Cycle.plan(cycle, all_ids)
    {batch_stage_1, states_stage_1} = run_stage(batch_all, ids_stage_1, ctx)
    manifest = update_manifest(manifest, states_stage_1, all_ids)

    case Cycle.plan(cycle, all_ids, states_stage_1) do
      # Stage 1 was the whole picture (all checks ran, or a re-run failure killed
      # the cycle). Stop here, success or failure.
      {:done, _cycle} ->
        batch_stage_1

      # Stage 1 (the failure subset) went green, so the stale passes still need
      # verifying. Stage 2 runs them and always settles to :done.
      {:run, ids_stage_2, cycle} ->
        {batch_stage_2, states_stage_2} = run_stage(batch_all, ids_stage_2, ctx)
        {:done, _cycle} = Cycle.plan(cycle, all_ids, states_stage_2)
        _manifest = update_manifest(manifest, states_stage_2, all_ids)
        batch_stage_1 ++ batch_stage_2
    end
  end

  defp run_stage(batch_all, ids, ctx) do
    batch =
      batch_all
      |> Enum.filter(&(&1.id in ids))
      |> run_batch(ctx)

    states =
      Map.new(batch, fn cstate ->
        status =
          if success?(cstate) do
            :pass
          else
            :fail
          end

        {cstate.id, status}
      end)

    {batch, states}
  end

  defp run_batch(batch, ctx) do
    batch
    |> spawn_batch(ctx)
    |> receive_batch()
  end

  defp prepare_batch(commands) do
    commands
    |> Enum.map(&build_command/1)
  end

  defp build_command({command, opts}) do
    mix_task = opts[:mix_task] || Atom.to_string(command)

    port_args = [
      "--erl-config",
      erl_config_path(),
      "-S",
      "mix",
      mix_task | Keyword.get(opts, :argv, [])
    ]

    port_opts = [
      :stream,
      :binary,
      :exit_status,
      :hide,
      :use_stdio,
      :stderr_to_stdout,
      args: port_args,
      env: convert_env(Keyword.get(opts, :env, []))
    ]

    %CommandState{
      id: unique_id(command, {command, opts}),
      command: command,
      opts: opts,
      port: nil,
      exit_status: nil,
      started_at: nil,
      finished_at: nil,
      output: nil,
      port_opts: port_opts
    }
  end

  defp convert_env(env) do
    Enum.map(env, fn {k, v} when is_binary(k) and is_binary(v) ->
      {String.to_charlist(k), String.to_charlist(v)}
    end)
  end

  defp erl_config_path do
    if IO.ANSI.enabled?() do
      Application.app_dir(:libdev, ["priv", "erl-port-ansi"])
    else
      Application.app_dir(:libdev, ["priv", "erl-port"])
    end
  end

  defp unique_id(prefix, data, separator \\ "__") do
    digest =
      data
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha, &1))
      |> Base.encode32(padding: false, case: :lower)

    String.pad_trailing("#{prefix}#{separator}", 32, digest)
  end

  defp spawn_batch(batch, ctx) do
    batch
    |> Enum.map(&format_command_start/1)
    |> Enum.intersperse("\n")
    |> IO.ANSI.format()
    |> IO.puts()

    Enum.map(batch, fn cstate ->
      %{cstate | port: spawn_port(cstate, ctx), started_at: now()}
    end)
  end

  defp spawn_port(cstate, ctx) do
    Port.open({:spawn_executable, ctx.elixir_exe}, cstate.port_opts)
  end

  defp receive_batch(batch) do
    Enum.map(batch, &receive_command/1)
  end

  defp receive_command(cstate) do
    IO.puts(IO.ANSI.format(format_command_output_header(cstate)))
    {output, exit_status, finished_at} = receive_port(cstate.port, [])
    state = %{cstate | output: output, exit_status: exit_status, finished_at: finished_at}
    IO.puts(IO.ANSI.format(format_command_finished(state)))
    state
  end

  defp receive_port(port, buffer) do
    receive do
      {^port, {:data, data}} ->
        IO.write(data)
        receive_port(port, [data | buffer])

      {any_port, {:exit_status, exit_status}} ->
        send(self(), {:port_finished, any_port, exit_status, now()})
        receive_port(port, buffer)

      {:port_finished, ^port, exit_status, finished_at} ->
        {:lists.reverse(buffer), exit_status, finished_at}
    end
  end

  defp summarize_batch(batch, ctx) do
    success? = all_success?(batch)

    color =
      if success? do
        :success
      else
        :error
      end

    [
      format_summary_header(ctx, color),
      "\n",
      Enum.map_intersperse(batch, ?\n, fn cstate -> format_command_summary(cstate) end),
      "\n\n"
    ]
    |> IO.ANSI.format()
    |> IO.puts()

    batch
  end

  defp success?(cstate) do
    cstate.exit_status == 0
  end

  defp all_success?(batch) do
    Enum.all?(batch, &success?/1)
  end

  defp now do
    System.monotonic_time(:millisecond)
  end

  defp format_command_start(cstate) do
    [
      color(:neutral),
      log_prefix(),
      " starting ",
      :bright,
      to_string(cstate.command),
      :reset
    ]
  end

  defp format_command_output_header(cstate) do
    main_output =
      [
        log_prefix(),
        " output from ",
        :bright,
        to_string(cstate.command)
      ]

    format_header(main_output, :neutral)
  end

  defp format_summary_header(ctx, color) do
    seconds = exec_time(ctx)

    main_output =
      [
        log_prefix(),
        " results (",
        :bright,
        "#{seconds}s",
        :normal,
        " total time) "
      ]

    format_header(main_output, color)
  end

  defp format_command_finished(cstate) do
    seconds = exec_time(cstate)

    color =
      if success?(cstate) do
        :success
      else
        :error
      end

    [
      "\n",
      color(color),
      log_prefix(),
      " finished ",
      :bright,
      to_string(cstate.command),
      :normal,
      " in ",
      :bright,
      to_string(seconds),
      "s",
      :reset,
      "\n"
    ]
  end

  defp format_command_summary(cstate) do
    if success?(cstate) do
      [
        color(:success),
        "  ✔ ",
        :bright,
        to_string(cstate.command),
        :normal,
        " finished in ",
        :bright,
        format_time(cstate),
        :reset
      ]
    else
      [
        color(:error),
        "  ✘ ",
        :bright,
        to_string(cstate.command),
        :normal,
        " finished in ",
        :bright,
        format_time(cstate),
        :normal,
        " with exit=",
        :bright,
        to_string(cstate.exit_status),
        :reset
      ]
    end
  end

  defp format_header(main_output, color) do
    raw_text_len = raw_len(main_output)

    cols =
      case :io.columns() do
        {:ok, cols} -> cols
        {:error, _} -> 80
      end

    pad_left = 0
    pad_right = max(0, cols - raw_text_len - pad_left)

    out = [
      background_color(color),
      List.duplicate(?\s, pad_left),
      main_output,
      List.duplicate(?\s, pad_right),
      :reset
    ]

    ["\n", out, "\n"]
  end

  defp raw_len(ansi_data) do
    case ansi_data do
      b when is_binary(b) -> String.length(b)
      a when is_atom(a) -> 0
      [h | t] -> raw_len(h) + raw_len(t)
      [] -> 0
    end
  end

  defp exec_time(state_or_context) do
    milliseconds = state_or_context.finished_at - state_or_context.started_at
    _seconds = Float.round(milliseconds / 1000, 2)
  end

  defp format_time(state_or_context) do
    [to_string(exec_time(state_or_context)), "s"]
  end

  defp log_prefix do
    "libdev>"
  end

  defp color(emotion) do
    case emotion do
      :neutral -> :light_blue
      :success -> :green
      :error -> :red
    end
  end

  # sobelow_skip ["DOS.BinToAtom"]
  defp background_color(emotion) do
    :"#{color(emotion)}_background"
  end
end

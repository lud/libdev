defmodule Mix.Tasks.Update.Deps.Vsns do
  @moduledoc false
  use Mix.Task

  @impl true
  def run(_argv) do
    versions = min_versions()

    {ast, comments} =
      "mix.exs"
      |> File.read!()
      |> Code.string_to_quoted_with_comments!(token_metadata: true, unescape: false)

    new_source =
      ast
      |> replace_deps(versions)
      |> Code.quoted_to_algebra(comments: comments)
      |> Inspect.Algebra.format(:infinity)
      |> IO.iodata_to_binary()
      |> Code.format_string!()

    File.write!("mix.exs", new_source)
    Mix.Task.run("format")
  end

  defp min_versions do
    "mix.lock"
    |> File.read!()
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Code.eval_string()
    |> case(do: ({deps, _} -> deps))
    |> Map.new(fn {dep, {:hex, dep, vsn, _hash, _, _, _, _}} -> {dep, vsn} end)
  end

  defp replace_deps(mix_exs_ast, min_versions) do
    Macro.postwalk(mix_exs_ast, fn
      {:defp, meta1, [{:auto_updated_deps, meta2, _no_args}, [do: body]]} ->
        body = update_vsns(body, min_versions)
        # force args to be nil to remote the parenthesis
        {:defp, meta1, [{:auto_updated_deps, meta2, nil}, [do: body]]}

      other ->
        other
    end)
  end

  defp update_vsns(quoted_deps, min_versions) do
    Enum.map(quoted_deps, fn {:{}, meta, [dep, cur_req | tuple_vars]} ->
      new_req =
        case new_req(dep, min_versions) do
          ^cur_req ->
            cur_req

          new_req ->
            print_update(dep, cur_req, new_req)
            new_req
        end

      {:{}, meta, [dep, new_req | tuple_vars]}
    end)
  end

  defp new_req(dep, min_versions) do
    latest_vsn = Map.fetch!(min_versions, dep)
    ">= #{latest_vsn}"
  end

  defp print_update(dep, cur_req, new_req) do
    IO.puts([
      "Updated requirement for ",
      inspect(dep),
      " ",
      format_req(cur_req),
      " to ",
      format_req(new_req)
    ])
  end

  defp format_req(">= " <> req), do: format_req(req)
  defp format_req(req), do: [?', req, ?']
end

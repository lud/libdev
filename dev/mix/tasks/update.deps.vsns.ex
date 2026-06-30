defmodule Mix.Tasks.Update.Deps.Vsns do
  @moduledoc false
  use Mix.Task

  @impl true
  def run(_argv) do
    deps_declarations = Mix.Project.get!().meta_package_deps()
    deps = Enum.map(deps_declarations, fn {dep, _vsn, _} -> dep end)

    versions = min_versions(deps)

    {ast, comments} =
      "mix.exs"
      |> File.read!()
      |> Code.string_to_quoted_with_comments!(token_metadata: true, unescape: false)

    {new_ast, updates} = replace_deps(ast, versions)

    new_source =
      new_ast
      |> Code.quoted_to_algebra(comments: comments)
      |> Inspect.Algebra.format(:infinity)
      |> IO.iodata_to_binary()
      |> Code.format_string!()

    commit_msg = commit_msg(updates)

    File.write!("mix.exs", new_source)
    File.write!(".manifest", manifest(versions))
    File.write!(".commitmsg", commit_msg)
    Mix.Task.run("format", ~w(--migrate))
  end

  defp min_versions(managed_deps) do
    "mix.lock"
    |> File.read!()
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Code.eval_string()
    |> case do
      ({deps, _} -> deps)
    end
    |> Enum.flat_map(fn
      {dep, {:hex, dep, vsn, _hash, _, _, _, _}} ->
        if dep in managed_deps do
          [{dep, vsn}]
        else
          []
        end
    end)
    |> Map.new()
  end

  defp replace_deps(mix_exs_ast, min_versions) do
    {new_ast, {found?, updates}} =
      Macro.postwalk(mix_exs_ast, {_found? = false, []}, fn
        {def_p, meta1, [{:meta_package_deps, meta2, _no_args}, [do: body]]},
        {false = _found?, updates}
        when def_p in [:def, :defp] ->
          {body, updates} = update_vsns(body, min_versions, updates)
          # force args to be nil to remove the parenthesis
          fun_ast = {def_p, meta1, [{:meta_package_deps, meta2, nil}, [do: body]]}
          {fun_ast, {_found? = true, updates}}

        other, acc ->
          {other, acc}
      end)

    if not found? do
      raise "AST clause was not found"
    end

    {new_ast, updates}
  end

  defp update_vsns(quoted_deps, min_versions, updates) do
    Enum.map_reduce(quoted_deps, updates, fn {:{}, meta, [dep, cur_req | tuple_vars]}, acc ->
      {new_req, acc} =
        case new_req(dep, min_versions) do
          ^cur_req ->
            {cur_req, acc}

          new_req ->
            print_update(dep, cur_req, new_req)
            {new_req, [{dep, cur_req, new_req} | acc]}
        end

      ast = {:{}, meta, [dep, new_req | tuple_vars]}
      {ast, acc}
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

  defp format_req(">= " <> req) do
    format_req(req)
  end

  defp format_req(req) do
    [?', req, ?']
  end

  defp manifest(versions) do
    versions
    |> Enum.sort_by(fn {dep, _vsn} -> dep end)
    |> inspect(pretty: true)
    |> tap(&IO.puts/1)
  end

  defp commit_msg(updates) do
    heading =
      case updates do
        [_single] -> "deps: Updated dependency "
        _ -> "deps: Updated dependencies "
      end

    deps =
      Enum.map_intersperse(updates, ", ", fn {dep, _, ">= " <> new_req} ->
        [Atom.to_string(dep), " ", new_req]
      end)

    [heading, deps, ?\n]
  end
end

if Code.ensure_loaded?(Readmix.Generator) do
  defmodule Libdev.DocGen.Generator do
    use Readmix.Generator

    action :readme_deps, params: []

    def readme_deps(_params, _ctx) do
      md_list =
        Mix.Project.config()
        |> Keyword.fetch!(:deps)
        |> Enum.filter(fn {_, _, opts} -> not Keyword.has_key?(opts, :only) end)
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn dep ->
          dep_name = elem(dep, 0)
          "* [#{dep_name}](https://hex.pm/packages/#{dep_name})\n"
        end)

      # Extra newline to prevent comments showing on hexdocs
      {:ok, ["\n", md_list, "\n"]}
    end
  end
end

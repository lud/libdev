defmodule Libdev.MixProject do
  use Mix.Project

  @version "0.2.7"
  @source_url "https://github.com/lud/libdev"

  def project do
    [
      app: :libdev,
      description: "A meta package to pull common development libraries.",
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      source_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: docs(),
      deps: deps(),
      dialyzer: dialyzer(),
      package: package()
    ]
  end

  def application do
    []
  end

  defp elixirc_paths(:dev) do
    ["lib", "dev"]
  end

  defp elixirc_paths(_) do
    ["lib"]
  end

  defp docs do
    [main: "readme", source_ref: "v#{@version}", source_url: @source_url, extras: ["README.md"]]
  end

  defp deps do
    auto_updated_deps() ++ self_deps()
  end

  def auto_updated_deps do
    [
      {:credo, ">= 1.7.14", runtime: false},
      {:dialyxir, ">= 1.4.7", runtime: false},
      {:doctor, ">= 0.22.0", runtime: false},
      {:ex_check, ">= 0.16.0", runtime: false},
      {:ex_doc, ">= 0.39.3", runtime: false},
      {:mix_audit, ">= 2.1.5", runtime: false},
      {:sobelow, ">= 0.14.1", runtime: false}
    ]
  end

  defp self_deps do
    [
      {:readmix, "~> 0.4", only: [:dev, :test], runtime: false},
      {:mix_version, "~> 2.4", only: [:dev, :test], runtime: false}
    ]
  end

  def cli do
    [preferred_envs: [dialyzer: :test]]
  end

  defp dialyzer do
    [
      flags: [:unmatched_returns, :error_handling, :unknown, :extra_return],
      list_unused_filters: true,
      plt_add_deps: :app_tree,
      plt_add_apps: [:ex_unit, :mix],
      plt_local_path: "_build/plts"
    ]
  end

  defp package do
    [licenses: ["MIT"], links: %{"Github" => @source_url}]
  end
end

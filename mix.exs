defmodule Libdev.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/lud/libdev"

  def project do
    [
      app: :libdev,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      source_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: docs(),
      deps: deps(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    []
  end

  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end

  defp deps do
    [
      # Users dependencies
      {:credo, "~> 1.7", runtime: false},
      {:dialyxir, "~> 1.4", runtime: false},
      {:doctor, "~> 0.22", runtime: false},
      {:ex_check, "~> 0.16", runtime: false},
      {:ex_doc, "~> 0.37", runtime: false},
      {:mix_audit, "~> 2.1", runtime: false},
      {:sobelow, "~> 0.13", runtime: false},

      # Libdev's dependencies
      {:readmix, "~> 0.4.0", only: [:dev, :test], runtime: false}
    ]
  end


  def cli do
    [
      preferred_envs: [dialyzer: :test]
    ]
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
end

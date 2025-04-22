defmodule Libdev.MixProject do
  use Mix.Project

  def project do
    [
      app: :libdev,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    []
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
      {:sobelow, "~> 0.13", runtime: false}

      # Libdev's dependencies
    ]
  end
end

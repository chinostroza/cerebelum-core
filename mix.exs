defmodule CerebelumCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :cerebelum_core,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Cerebelum.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # JSON encoding/decoding
      {:jason, "~> 1.4"},

      # Database
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.19"},

      # UUID generation
      {:ecto, "~> 3.12"}
    ]
  end
end

defmodule CerebelumCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :cerebelum_core,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),

      # Aliases
      aliases: aliases(),

      # Test coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],

      # Documentation
      name: "Cerebelum Core",
      source_url: "https://github.com/cerebelum-io/cerebelum-core",
      docs: [
        main: "Cerebelum",
        extras: [
          "README.md",
          "docs/guides/getting-started.md",
          "docs/tutorials/01-first-workflow.md"
        ],
        groups_for_modules: [
          "Core": [Cerebelum, Cerebelum.Workflow],
          "DSL": [
            Cerebelum.Workflow.DSL,
            Cerebelum.Workflow.DSL.Timeline,
            Cerebelum.Workflow.DSL.Diverge,
            Cerebelum.Workflow.DSL.Branch
          ],
          "Execution": [
            Cerebelum.Execution.Engine,
            Cerebelum.Execution.Supervisor,
            Cerebelum.Context
          ],
          "Event Sourcing": [
            Cerebelum.EventStore,
            Cerebelum.Events
          ],
          "Metrics": [
            Cerebelum.Metrics,
            Cerebelum.Database.Metrics
          ]
        ]
      ]
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
  defp aliases do
    [
      "test.clean": ["ecto.drop --quiet", "ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "coveralls.clean": ["ecto.drop --quiet", "ecto.create --quiet", "ecto.migrate --quiet", "coveralls"],
      "coveralls.html.clean": ["ecto.drop --quiet", "ecto.create --quiet", "ecto.migrate --quiet", "coveralls.html"],
      "protobuf.generate": ["cmd protoc --elixir_out=plugins=grpc:./lib --proto_path=priv/protos priv/protos/*.proto"]
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # JSON encoding/decoding
      {:jason, "~> 1.4"},

      # Database
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.19"},

      # UUID generation
      {:ecto, "~> 3.12"},

      # Telemetry for metrics
      {:telemetry, "~> 1.2"},

      # gRPC for multi-language SDK support
      {:grpc, "~> 0.11"},
      {:protobuf, "~> 0.14"},
      {:google_protos, "~> 0.4"},

      # Development & Testing
      {:excoveralls, "~> 0.18", only: :test},
      {:stream_data, "~> 1.1", only: :test},
      {:benchee, "~> 1.3", only: :dev},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end

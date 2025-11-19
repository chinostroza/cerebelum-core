import Config

# Test database config
config :cerebelum_core, Cerebelum.Repo,
  database: "cerebelum_core_test#{System.get_env("MIX_TEST_PARTITION")}",
  username: "dev",
  hostname: "localhost",
  password: "",  # Add password if needed
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# gRPC server disabled in test environment
config :cerebelum_core,
  enable_grpc_server: false

# Print only warnings and errors during test
config :logger, level: :warning

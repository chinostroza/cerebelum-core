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

# Workflow resurrection settings for testing
config :cerebelum_core,
  # Enable resurrection for testing
  enable_workflow_resurrection: true,
  # Fast scans for tests (50ms)
  resurrection_scan_interval_ms: 50,
  # Fewer retry attempts in tests
  max_resurrection_attempts: 2,
  # Hibernation disabled in tests by default
  enable_workflow_hibernation: false,
  # Lower threshold for hibernation tests
  hibernation_threshold_ms: 100

# Print only warnings and errors during test
config :logger, level: :warning

import Config

# Development database config
config :cerebelum_core, Cerebelum.Repo,
  database: "cerebelum_core_dev",
  username: "dev",
  hostname: "localhost",
  password: "",  # Add password if needed
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# gRPC server configuration (enabled for Python SDK testing)
# Set to true if you need to test multi-language SDK workers
config :cerebelum_core,
  enable_grpc_server: true,
  grpc_port: 9090  # Using 9090 instead of 50051 for testing

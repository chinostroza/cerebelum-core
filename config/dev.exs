import Config

# Development database config
config :cerebelum_core, Cerebelum.Repo,
  database: "cerebelum_core_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

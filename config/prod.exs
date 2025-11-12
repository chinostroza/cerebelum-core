import Config

# Production database config (from environment variables)
config :cerebelum_core, Cerebelum.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: true

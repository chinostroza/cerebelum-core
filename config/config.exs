import Config

# Configure Ecto Repo
config :cerebelum_core, Cerebelum.Repo,
  database: "cerebelum_core_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool_size: 10

config :cerebelum_core, ecto_repos: [Cerebelum.Repo]

# Import environment specific config
import_config "#{config_env()}.exs"

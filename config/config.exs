import Config

# Configure Ecto Repo
config :cerebelum_core, Cerebelum.Repo,
  database: "cerebelum_core_dev",
  username: "dev",
  hostname: "localhost",
  pool_size: 10

config :cerebelum_core, ecto_repos: [Cerebelum.Repo]

# Workflow Resurrection Configuration
config :cerebelum_core,
  # Enable workflow resurrection (boot-time and periodic)
  enable_workflow_resurrection: true,

  # Scan interval for periodic resurrection (in milliseconds)
  # Default: 30 seconds
  resurrection_scan_interval_ms: 30_000,

  # Maximum resurrection attempts before moving to DLQ
  # Default: 3 attempts
  max_resurrection_attempts: 3,

  # Enable workflow hibernation for long sleeps
  # Default: false (disabled for safety)
  enable_workflow_hibernation: false,

  # Hibernation threshold (in milliseconds)
  # Workflows sleeping longer than this will be hibernated
  # Default: 1 hour (3,600,000 ms)
  hibernation_threshold_ms: 3_600_000

# Import environment specific config
import_config "#{config_env()}.exs"

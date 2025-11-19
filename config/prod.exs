import Config

# Production configuration
# Runtime configuration (environment variables) is loaded in config/runtime.exs

# Do not print debug messages in production
config :logger, level: :info

# Enable server by default
config :cerebelum_core,
  server: true

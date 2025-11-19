# Cerebelum Core - Configuration Guide

## Using Cerebelum as a Dependency

When using Cerebelum Core as a dependency in your application (e.g., `venture_core`), you need to configure it properly.

### Database Configuration

**IMPORTANT**: Cerebelum Core does NOT require a separate database. It uses your application's existing Ecto repository.

If you get this error:
```
[error] Postgrex.Protocol failed to connect:
** (ArgumentError) missing the :database key in options for Cerebelum.Repo
```

**Solution**: Configure Cerebelum's Repo in your application's config:

```elixir
# config/dev.exs (in YOUR application, e.g., venture_core)
config :cerebelum_core, Cerebelum.Repo,
  username: "dev",
  password: "",
  hostname: "localhost",
  database: "your_app_dev",  # Use YOUR application's database
  pool_size: 10

# Or, to share the same Repo as your application:
config :cerebelum_core, Cerebelum.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "dev",
  password: "",
  hostname: "localhost",
  database: "venture_dev",  # Your app's database
  pool_size: 10
```

### gRPC Server Configuration

By default, the gRPC server is **DISABLED** in development and test environments.

#### Development Environment

```elixir
# config/dev.exs
config :cerebelum_core,
  enable_grpc_server: false,  # Default: disabled
  grpc_port: 50051
```

If you need to test multi-language SDK workers in development, enable it:

```elixir
# config/dev.exs
config :cerebelum_core,
  enable_grpc_server: true,  # Enable for SDK testing
  grpc_port: 50051  # or any other available port
```

#### Test Environment

gRPC server is always disabled in tests to avoid port conflicts:

```elixir
# config/test.exs
config :cerebelum_core,
  enable_grpc_server: false
```

#### Production Environment

In production, the gRPC server is enabled by default for multi-language SDK support:

```elixir
# config/prod.exs
config :cerebelum_core,
  enable_grpc_server: true,  # or set via ENV: ENABLE_GRPC_SERVER=true
  grpc_port: 50051  # or set via ENV: GRPC_PORT=50051
```

Environment variables:
- `ENABLE_GRPC_SERVER`: "true" or "false"
- `GRPC_PORT`: Port number (default: 50051)

### Common Issues

#### Error: Port 50051 already in use

```
{:listen_error, "Cerebelum.Endpoint", :eaddrinuse}
```

**Solutions:**

1. **Disable gRPC server** (recommended for dev when not testing SDKs):
   ```elixir
   config :cerebelum_core, enable_grpc_server: false
   ```

2. **Change the port**:
   ```elixir
   config :cerebelum_core, grpc_port: 50052
   ```

3. **Kill existing process**:
   ```bash
   lsof -ti:50051 | xargs kill -9
   ```

#### Error: Repo configuration missing

Make sure you have `ecto_repos` configured:

```elixir
# config/config.exs
config :cerebelum_core, ecto_repos: [Cerebelum.Repo]
```

### Complete Example Configuration

```elixir
# config/dev.exs in your application
import Config

# Your app's database
config :your_app, YourApp.Repo,
  username: "dev",
  password: "",
  hostname: "localhost",
  database: "your_app_dev",
  pool_size: 10

# Cerebelum Core database (can share the same database)
config :cerebelum_core, Cerebelum.Repo,
  username: "dev",
  password: "",
  hostname: "localhost",
  database: "your_app_dev",  # Same database
  pool_size: 10

# Cerebelum Core gRPC (disabled by default in dev)
config :cerebelum_core,
  enable_grpc_server: false
```

### Running Mix Tasks

When running mix tasks like `mix ecto.reset`, Cerebelum will start but won't interfere:

```bash
cd your_app
mix ecto.reset  # Works now! Cerebelum won't start gRPC server
```

### Enabling gRPC for SDK Testing

Only enable when you need to test Kotlin/TypeScript/Python SDK workers:

```elixir
# config/dev.exs
config :cerebelum_core,
  enable_grpc_server: true,
  grpc_port: 50051
```

Then start your app:

```bash
iex -S mix
# gRPC server listening on port 50051
# SDK workers can now connect
```

### Migration to Your Own Database

Cerebelum needs its own tables. Run migrations:

```bash
# From your application directory
mix ecto.migrate
```

This will create Cerebelum's tables in your database:
- `events` - Event store table
- `metrics` - Metrics collection

## Questions?

- **Do I need a separate database?** No, Cerebelum can share your application's database.
- **Can I disable gRPC?** Yes, set `enable_grpc_server: false` (default in dev/test).
- **What port does gRPC use?** Port 50051 by default (configurable).
- **How do I test SDK workers?** Enable gRPC server in dev config.

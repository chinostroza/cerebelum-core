# Cerebelum Core

**Status:** ✅ Phase 8 Complete - Production Ready
**Version:** 0.1.0
**License:** MIT

Core workflow orchestration engine with deterministic execution, event sourcing, and graph-based state management.

## 🎯 Purpose

Cerebelum Core is the foundation of the Cerebelum platform. It provides:

- ⚙️ **Workflow Orchestration** - Define and execute complex workflows
- 🎲 **Deterministic Execution** - 100% reproducible runs with time travel debugging
- 📚 **Event Sourcing** - Complete execution history
- 🔀 **Graph-Based State** - Support for cycles and conditional routing (like LangGraph)
- 🔄 **Checkpointing** - Save and resume long-running workflows
- 🏗️ **Clean Architecture** - SOLID principles, testable, maintainable
- 🌐 **Multi-Language SDK Support** - Python SDK with gRPC communication
- 💀 **Dead Letter Queue (DLQ)** - Robust error handling and task retry management

**Key Difference:** This is a **general-purpose** workflow engine. AI features are in separate `cerebelum-ai` module.

## 🏗️ Architecture

Cerebelum Core follows Clean Architecture with strict layer separation:

```
Domain Layer (Pure Business Logic)
  ↓ depends on
Application Layer (Use Cases)
  ↓ depends on
Infrastructure Layer (External Integrations)
  ↑ implements
Presentation Layer (HTTP API)
```

## 📦 Modules

- **Domain Layer** - Entities, value objects, domain services, ports (behaviours)
- **Application Layer** - Use cases, commands, queries
- **Infrastructure Layer** - Repositories, event store, deterministic system
- **Presentation Layer** - Phoenix HTTP API (optional, can use via `cerebelum-web`)

## 🚀 Quick Start

```elixir
# Add to mix.exs
def deps do
  [
    {:cerebelum_core, "~> 0.1.0"}
  ]
end

# Define a workflow using the DSL
defmodule MyApp.OrderWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      validate_order() |> process_payment() |> ship_order()
    end

    # Error handling with diverge
    diverge from: validate_order() do
      {:error, :invalid_order} -> :failed
      :timeout -> :retry
    end

    # Conditional routing with branch
    branch after: process_payment(), on: result do
      result.amount > 1000 -> :high_value_path
      true -> :standard_path
    end
  end

  def validate_order(context) do
    order = context.inputs[:order]
    if valid?(order), do: {:ok, order}, else: {:error, :invalid_order}
  end

  def process_payment(_context, order) do
    {:ok, %{amount: calculate_total(order), status: :paid}}
  end

  def ship_order(_context, _order, payment) do
    {:ok, %{tracking: "TRACK-123", carrier: "FedEx"}}
  end

  defp valid?(order), do: !is_nil(order) && order[:id]
  defp calculate_total(order), do: 1000
end

# Execute the workflow
{:ok, execution} = Cerebelum.execute_workflow(
  MyApp.OrderWorkflow,
  %{order: %{id: "ORD-123", items: []}}
)

# Get execution status
{:ok, status} = Cerebelum.get_execution_status(execution.id)
#=> %{state: :completed, results: %{...}, timeline_progress: "3/3", ...}

# List all executions
executions = Cerebelum.list_executions()

# Stop an execution
Cerebelum.stop_execution(execution.id)
```

## 🔑 Key Features

### Deterministic Execution
Every workflow run is 100% reproducible:
- Virtual time (no real waiting)
- Seeded randomness
- Memoized external calls
- Version-aware replay

### Event Sourcing
Complete audit trail:
- Every state change recorded
- Time travel debugging
- Replay any execution
- Event streaming

### Graph-Based Workflows
Like LangGraph, but deterministic:
- **Cycles allowed** (iterate until condition met)
- **Conditional edges** - Branch to different paths based on results
- **Error handling** - Diverge to retry or fail gracefully
- **State management** - Results automatically passed to subsequent steps

```elixir
# Diverge for error handling and retries
diverge from: validate_order() do
  {:error, :invalid_order} -> :failed
  :timeout -> :retry
end

# Branch for conditional routing
branch after: process_payment(), on: result do
  result.amount > 1000 -> :high_value_path
  true -> :standard_path
end
```

### Clean Architecture
Maintainable and testable:
- No framework coupling
- Dependency inversion via behaviours
- Each layer independently testable
- SOLID principles

## 📋 Requirements

See [specs/01-requirements.md](./specs/01-requirements.md) for complete requirements.

**Core Requirements Covered:**
- Req 1: Workflow Definition and Management
- Req 2: Deterministic Time Management
- Req 3: Deterministic Random Operations
- Req 4: External Call Memoization
- Req 5: Workflow Versioning and Evolution
- Req 6: Event Sourcing and Execution History
- Req 7: Time Travel Debugging
- Req 8: Clean Architecture Compliance
- Req 9: SOLID Principles Implementation
- Req 10: Comprehensive Testing Strategy
- Req 11: Workflow Execution Engine
- Req 14: Workflow State Checkpointing
- Req 16: Database Persistence
- Req 18: Error Handling and Recovery
- Req 34: Graph-Based State Management

## 📚 Documentation

- [Requirements](./specs/01-requirements.md) - What we're building
- [Design](./specs/02-design.md) - How it's architected
- [Implementation Tasks](./specs/03-implementation-tasks.md) - Development roadmap

## 🧪 Testing

```bash
# Run all tests
mix test

# Run tests with clean database
mix test.clean

# Generate coverage report
mix coveralls

# Generate HTML coverage report
mix coveralls.html

# Coverage with clean database
mix coveralls.clean

# Run specific test file
mix test test/cerebelum/workflow_test.exs

# Run specific test pattern
mix test --only integration
```

## 🔗 Related Modules

| Module | Purpose | Dependency |
|--------|---------|------------|
| `cerebelum-workers` | SDK support via gRPC | Optional |
| `cerebelum-ai` | AI agents, LLM integration | Optional |
| `cerebelum-tools` | Tool registry | Optional |
| `cerebelum-web` | Web UI and API | Optional |
| `cerebelum-observability` | Metrics and monitoring | Optional |

## 🛠️ Development

```bash
# Setup
mix deps.get
mix ecto.create
mix ecto.migrate

# Run interactive shell
iex -S mix

# Code quality checks
mix format --check-formatted  # Check formatting
mix format                    # Auto-format code
mix credo                     # Static analysis
mix dialyzer                  # Type checking

# Generate documentation
mix docs

# Generate gRPC protobuf files (if modified)
mix protobuf.generate
```

## 📦 Installation (when published)

```elixir
def deps do
  [
    {:cerebelum_core, "~> 1.0"}
  ]
end
```

## 🤝 Contributing

This module is part of the Cerebelum family. See main [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines.

**Development Workflow:**
1. Check [specs/03-implementation-tasks.md](./specs/03-implementation-tasks.md)
2. All 8 phases are complete - future work will be enhancements
3. Write tests first (TDD)
4. Follow Clean Architecture principles
5. Run tests and quality checks before committing:
   ```bash
   mix test
   mix format
   mix credo
   ```

## 📄 License

MIT License - See [LICENSE](./LICENSE) for details.

## 🔗 Links

- [Main Documentation](https://docs.cerebelum.io)
- [GitHub Organization](https://github.com/cerebelum-io)
- [Hex Package](https://hex.pm/packages/cerebelum_core) (when published)

## Configuration

### Using as a Dependency

When using Cerebelum Core in your application:

```elixir
# mix.exs
def deps do
  [
    {:cerebelum_core, path: "../cerebelum-core"}  # or from hex/git
  ]
end
```

### Database Setup

Configure Cerebelum to use your application's database:

```elixir
# config/dev.exs
config :cerebelum_core, Cerebelum.Repo,
  username: "dev",
  password: "",
  hostname: "localhost",
  database: "your_app_dev",
  pool_size: 10
```

### gRPC Server (Optional)

The gRPC server is **disabled by default** in development and test environments.

Enable only when testing multi-language SDK workers:

```elixir
# config/dev.exs
config :cerebelum_core,
  enable_grpc_server: true,  # Enable for SDK testing
  grpc_port: 50051
```

### Common Issues

**Port 50051 in use?**
- gRPC server is disabled by default now
- Or set `enable_grpc_server: false` in your config

**Database configuration missing?**
- See `docs/configuration.md` for complete guide
- Or `TEAM_SETUP_GUIDE.md` for quick setup

For detailed configuration, see:
- `docs/configuration.md` - Complete configuration guide
- `TEAM_SETUP_GUIDE.md` - Quick setup for teams


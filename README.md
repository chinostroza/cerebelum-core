# Cerebelum Core

**Status:** 🚧 In Development
**Version:** 0.1.0 (pre-alpha)
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

# Define a workflow
workflow = %{
  "name" => "simple_workflow",
  "entrypoint" => "start",
  "nodes" => %{
    "start" => %{
      "type" => "function",
      "module" => "MyApp.Tasks",
      "function" => "process",
      "next" => ["end"]
    },
    "end" => %{
      "type" => "function",
      "module" => "MyApp.Tasks",
      "function" => "finish"
    }
  }
}

# Create and execute
{:ok, workflow_id} = Cerebelum.create_workflow(workflow)
{:ok, execution_id} = Cerebelum.execute_workflow(workflow_id, %{data: "input"})

# Get status
{:ok, status} = Cerebelum.get_execution_status(execution_id)

# Replay for debugging
{:ok, replay_result} = Cerebelum.replay_execution(execution_id)
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
- Conditional edges
- Parallel execution
- State merge strategies

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

# Run by layer
mix test.unit          # Domain layer
mix test.use_cases     # Application layer
mix test.integration   # Infrastructure layer

# Coverage
mix test.coverage
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
mix ecto.setup

# Development server (if using web)
mix phx.server

# Code quality
mix format
mix credo
mix dialyzer

# All quality checks
mix quality
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
2. Pick a task from Phase 1-7
3. Write tests first (TDD)
4. Implement following Clean Architecture
5. Run `mix quality` before committing

## 📄 License

MIT License - See [LICENSE](./LICENSE) for details.

## 🔗 Links

- [Main Documentation](https://docs.cerebelum.io)
- [GitHub Organization](https://github.com/cerebelum-io)
- [Hex Package](https://hex.pm/packages/cerebelum_core) (when published)

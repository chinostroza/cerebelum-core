<div align="center">

# Cerebelum Core

### Production-Ready Workflow Orchestration Engine

[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](https://github.com/cerebelum-io/cerebelum-core)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)
[![Status](https://img.shields.io/badge/status-production%20ready-brightgreen.svg)]()
[![Elixir](https://img.shields.io/badge/elixir-1.18-purple.svg)](https://elixir-lang.org/)

**Deterministic workflow orchestration with event sourcing, graph-based state management, and multi-language support.**

[Features](#-key-features) • [Quick Start](#-quick-start) • [Documentation](#-documentation) • [Examples](#-examples) • [Deployment](#-deployment)

</div>

---

## 🎯 What is Cerebelum Core?

Cerebelum Core is a **general-purpose workflow orchestration engine** built with Elixir/OTP that provides:

- **🎲 Deterministic Execution** - 100% reproducible workflow runs with time-travel debugging
- **📚 Event Sourcing** - Complete audit trail with 640K+ events/sec throughput
- **🔀 Graph-Based Workflows** - Cycles, conditional branches, and error divergence (like LangGraph)
- **🌐 Multi-Language Support** - Python, Kotlin, TypeScript SDKs via gRPC
- **⚡ High Performance** - Built on Erlang/OTP with supervised process trees
- **🔄 Long-Running Workflows** - Checkpointing, human-in-the-loop approvals
- **🏗️ Clean Architecture** - SOLID principles, testable, maintainable

> **Note:** This is a general-purpose workflow engine. AI/LLM features are in the separate `cerebelum-ai` module.

---

## ✨ Key Features

### Deterministic Execution

Every workflow run is **100% reproducible**:

```elixir
# Same inputs = Same outputs, always
{:ok, execution1} = Cerebelum.execute_workflow(MyWorkflow, %{seed: 42})
{:ok, execution2} = Cerebelum.execute_workflow(MyWorkflow, %{seed: 42})

# execution1.results == execution2.results ✓
```

- **Virtual time** - No actual waiting, instant replay
- **Seeded randomness** - Predictable random values
- **Memoized external calls** - Recorded and replayed
- **Version-aware replay** - State reconstruction from events

### Event Sourcing Architecture

Complete audit trail with high throughput:

- **640K+ events/sec** with batching (100ms flush window)
- **18 event types** - ExecutionStarted, StepExecuted, BranchTaken, etc.
- **PostgreSQL partitioning** by execution_id for scalability
- **Time-travel debugging** - Replay any execution from events
- **Optimistic concurrency** control with version numbers

### Graph-Based Workflows (Like LangGraph)

Build complex workflow graphs with cycles and conditions:

```elixir
workflow do
  timeline do
    start() |> process() |> check_quality()
  end

  # Conditional branching
  branch after: check_quality(), on: result do
    result.score >= 0.9 -> :approve
    result.score >= 0.5 -> :review
    true -> :reject
  end

  # Error handling with diverge
  diverge from: process() do
    {:error, :timeout} -> :retry
    {:error, :invalid_data} -> :failed
  end

  # Cycles - loop back to earlier steps
  branch after: review() do
    approved? -> :approve
    true -> back_to(process())  # Re-process
  end
end
```

### Multi-Language SDK Support

Write workflow steps in any language:

| Language | Status | gRPC | Local Mode |
|----------|--------|------|------------|
| **Python** | ✅ v1.2 | ✅ | ✅ |
| **Elixir** | ✅ Native | N/A | ✅ |
| Kotlin | 🚧 Planned | ✅ | - |
| TypeScript | 🚧 Planned | ✅ | - |

---

## 🚀 Quick Start

### Elixir DSL

```elixir
# 1. Add to mix.exs
def deps do
  [{:cerebelum_core, "~> 0.1.0"}]
end

# 2. Define a workflow
defmodule MyApp.OrderWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      validate_order() |> process_payment() |> ship_order()
    end

    diverge from: validate_order() do
      {:error, :invalid_order} -> :failed
      :timeout -> :retry
    end

    branch after: process_payment(), on: result do
      result.amount > 1000 -> :high_value_flow
      true -> :standard_flow
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
    {:ok, %{tracking: generate_tracking(), carrier: "FedEx"}}
  end
end

# 3. Execute
{:ok, execution} = Cerebelum.execute_workflow(
  MyApp.OrderWorkflow,
  %{order: %{id: "ORD-123", items: [...]}}
)

# 4. Check status
{:ok, status} = Cerebelum.get_execution_status(execution.id)
# => %{state: :completed, results: %{...}, timeline_progress: "3/3"}
```

### Python SDK (v1.2)

```python
from cerebelum import step, workflow, Context

# 1. Define steps with @step decorator
@step
async def validate_order(context: Context, inputs: dict):
    order = inputs.get("order")
    if not order.get("id"):
        raise ValueError("Invalid order")  # Auto-wrapped to error
    return order  # Auto-wrapped to {"ok": order}

@step
async def process_payment(context: Context, validate_order: dict):
    # Dependencies auto-injected by parameter name
    order = validate_order
    return {"amount": calculate_total(order), "status": "paid"}

@step
async def ship_order(context: Context, validate_order: dict, process_payment: dict):
    payment = process_payment
    return {"tracking": generate_tracking(), "carrier": "FedEx"}

# 2. Define workflow
@workflow
def order_workflow(wf):
    wf.timeline(
        validate_order >> process_payment >> ship_order
    )

# 3. Execute (local mode - no Core needed!)
result = await order_workflow.execute({
    "order": {"id": "ORD-123", "items": [...]}
})
print(f"Status: {result.state}")  # completed
```

**Python SDK Highlights:**

- **Local mode** - No Core/Docker needed for development
- **Auto-wrapping** - `return value` → `{"ok": value}`, `raise Error` → `{"error": ...}`
- **Dependency injection** - Parameter names = dependencies
- **Parallel execution** - `[step_a, step_b, step_c]` syntax
- **100% async/await** - Modern Python idioms

See [Python SDK Tutorial](./examples/python-sdk/README.md) for complete guide (7 tutorials, 80 minutes).

---

## 📦 Installation

### Elixir (from source)

```bash
# Clone repository
git clone https://github.com/cerebelum-io/cerebelum-core.git
cd cerebelum-core

# Install dependencies
mix deps.get

# Setup database
mix ecto.create
mix ecto.migrate

# Run tests
mix test

# Start interactive shell
iex -S mix
```

### Docker (Production)

```bash
# Clone and configure
git clone https://github.com/cerebelum-io/cerebelum-core.git
cd cerebelum-core
cp .env.example .env
# Edit .env with your database credentials

# Deploy
docker compose up -d

# Run migrations
docker compose exec app bin/cerebelum_core eval "Cerebelum.Release.migrate()"

# Check status
docker compose logs -f app
```

See [DEPLOYMENT.md](./DEPLOYMENT.md) for complete production setup guide.

---

## 📚 Documentation

### Guides

- [Getting Started](./guides/getting-started.md) - First workflow tutorial
- [Configuration Guide](./guides/configuration.md) - Environment variables, database, gRPC
- [Error Handling](./guides/error-handling.md) - Diverge, retries, DLQ
- [Python SDK Tutorial](./examples/python-sdk/README.md) - 7 tutorials from beginner to advanced

### Specifications

- [Core Foundation](./specs/core-foundation/) - Architecture and design (Phase 1 & 2 complete)
- [Cloud Platform](./specs/cloud-platform/) - Roadmap for no-code UI (v0.2.0, all phases complete)
- [All Specifications](./specs/) - Complete specifications index

### API Documentation

```bash
# Generate ExDoc documentation
mix docs

# Open in browser
open doc/index.html
```

---

## 🎓 Examples

### 1. Hello World (Python SDK)

```bash
cd examples/python-sdk
python3 01_hello_world.py
```

**Time:** 3 minutes | **Difficulty:** 🟢 Beginner

### 2. Dependencies & Composition

```bash
python3 02_dependencies.py
```

Learn how steps depend on each other and data flows through the workflow.

### 3. Parallel Execution

```bash
python3 03_parallel_execution.py
```

Execute multiple steps concurrently with `[step_a, step_b]` syntax.

### 4. Complete E-Commerce Example

```bash
python3 05_complete_example.py
```

**8-step workflow** with authentication, validation, payment, and parallel notifications.

### 5. Distributed Mode (Production)

```bash
# Terminal 1: Start Core
mix run --no-halt

# Terminal 2: Start Worker
python3 06_distributed_server.py

# Terminal 3: Execute workflows
python3 06_execute_workflow.py hello_workflow Alice
```

**Production setup** with Core orchestrator + gRPC workers.

### 6. Enterprise Onboarding (Advanced)

```bash
# Start infrastructure (Core + Worker)
mix run --no-halt  # Terminal 1
python3 07_distributed_server.py  # Terminal 2

# Execute onboarding
python3 07_execute_workflow.py "Jane Doe" "jane@company.com" "Engineering" "Developer"
```

**12-step complex workflow** with 3 phases of parallel execution:
- Provisioning (user account, workspace, tools)
- Configuration (permissions, integrations, docs)
- Notifications (email, Slack, calendar)

---

## 🏗️ Architecture

### Clean Architecture Layers

```
┌─────────────────────────────────────┐
│     Presentation Layer              │  ← gRPC, HTTP API
│  (Worker Service, Future Phoenix)   │
├─────────────────────────────────────┤
│    Infrastructure Layer             │  ← EventStore, Repo, DLQ
│  (External integrations, adapters)  │
├─────────────────────────────────────┤
│     Application Layer               │  ← Use cases, commands
│   (Business rules orchestration)    │
├─────────────────────────────────────┤
│       Domain Layer                  │  ← Entities, workflows
│   (Pure business logic, DSL)        │
└─────────────────────────────────────┘
```

### Key Components

**Workflow Layer:**
- `Workflow.DSL` - Macro-based workflow definition
- `Workflow.Validator` - Compile-time validation
- `Workflow.Versioning` - Deterministic version computation

**Execution Engine:**
- `Execution.Engine` - Main orchestrator (GenServer)
- `Execution.StepExecutor` - Individual step execution
- `Execution.ParallelExecutor` - Concurrent step execution
- `Execution.BranchHandler` - Conditional routing
- `Execution.DivergHandler` - Error handling

**Event Sourcing:**
- `EventStore` - Append-only event log with batching
- `Events` - 18 event types (ExecutionStarted, StepExecuted, etc.)
- `StateReconstructor` - Replay execution from events

---

## 🔧 Technology Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| **Language** | Elixir | 1.18 |
| **Runtime** | Erlang/OTP | 27.x |
| **Database** | PostgreSQL | 12+ |
| **RPC** | gRPC | 0.11 |
| **Serialization** | Protocol Buffers | 0.14 |
| **ORM** | Ecto | 3.12 |
| **JSON** | Jason | 1.4 |
| **Telemetry** | Telemetry | 1.2 |
| **Containerization** | Docker | Alpine Linux |

**Development:**
- **Testing:** ExUnit + StreamData (property testing)
- **Coverage:** ExCoveralls (40 test files)
- **Linting:** Credo
- **Type Checking:** Dialyxir
- **Benchmarking:** Benchee
- **Documentation:** ExDoc

---

## 🚢 Deployment

### Docker Compose (Recommended)

```bash
# 1. Configure environment
cp .env.example .env
nano .env  # Set DATABASE_URL, SECRET_KEY_BASE, etc.

# 2. Deploy
./deploy.sh

# 3. Verify
docker compose ps
docker compose logs -f app
```

### Standalone VPS

```bash
# 1. Setup PostgreSQL
sudo -u postgres createdb cerebelum_prod

# 2. Install dependencies
mix deps.get

# 3. Compile release
MIX_ENV=prod mix release

# 4. Run migrations
_build/prod/rel/cerebelum_core/bin/cerebelum_core eval "Cerebelum.Release.migrate()"

# 5. Start server
_build/prod/rel/cerebelum_core/bin/cerebelum_core start
```

See [DEPLOYMENT.md](./DEPLOYMENT.md) for detailed instructions.

---

## 🧪 Testing & Quality

```bash
# Run all tests (40 test files)
mix test

# Run with clean database
mix test.clean

# Generate coverage report
mix coveralls.html
open cover/excoveralls.html

# Code quality checks
mix format --check-formatted  # Check formatting
mix format                    # Auto-format
mix credo --strict            # Linting
mix dialyzer                  # Type checking

# Run benchmarks
mix run benchmarks/event_store_bench.exs
```

---

## 🔄 Comparison with Other Frameworks

| Feature | Cerebelum | Temporal | Apache Airflow | LangGraph |
|---------|-----------|----------|----------------|-----------|
| **Deterministic** | ✅ Always | ⚠️ Partial | ❌ No | ⚠️ Manual |
| **Event Sourcing** | ✅ Built-in | ✅ Yes | ❌ No | ❌ No |
| **Graph Cycles** | ✅ Native | ❌ No | ✅ DAG only | ✅ Yes |
| **Multi-Language** | ✅ gRPC SDKs | ✅ Many | ✅ Python focus | ✅ Python only |
| **Time Travel Debug** | ✅ Always | ⚠️ Limited | ❌ No | ❌ No |
| **Local Development** | ✅ Zero setup | ⚠️ Docker required | ⚠️ Complex | ✅ Simple |
| **High Throughput** | ✅ 640K events/s | ✅ Scalable | ⚠️ Moderate | ❌ Single process |

**Cerebelum is best for:**
- Workflows requiring complete audit trails
- Systems where reproducibility is critical (finance, healthcare, compliance)
- Development teams wanting local-first workflow testing
- Complex workflows with cycles and conditional logic

---

## 🗺️ Roadmap

### v0.1.0 (Current) - Core Foundation ✅

- [x] Deterministic execution engine
- [x] Event sourcing with PostgreSQL
- [x] Graph-based workflow DSL
- [x] Python SDK v1.2
- [x] gRPC multi-language support
- [x] Docker deployment
- [x] 40+ tests with coverage

### v0.2.0 (Planned) - Cloud Platform

- [ ] No-code workflow builder UI (Next.js)
- [ ] Visual workflow editor
- [ ] Execution monitoring dashboard
- [ ] User authentication (Auth0)
- [ ] Workflow templates library
- [ ] REST API for workflow management

### v0.3.0 (Future)

- [ ] Mobile SDK for human-in-the-loop
- [ ] Lazy replay optimization
- [ ] Advanced observability (Prometheus, Grafana)
- [ ] Kotlin SDK
- [ ] TypeScript SDK
- [ ] Signal system for event coordination

See [specs/cloud-platform/](./specs/cloud-platform/) for details.

---

## 🤝 Contributing

We welcome contributions! Here's how to get started:

### Development Workflow

```bash
# 1. Fork and clone
git clone https://github.com/YOUR_USERNAME/cerebelum-core.git

# 2. Create feature branch
git checkout -b feature/my-feature

# 3. Make changes and test
mix test
mix format
mix credo

# 4. Commit and push
git commit -m "feat: add amazing feature"
git push origin feature/my-feature

# 5. Open Pull Request
```

### Guidelines

- **Tests first** - Write tests before implementation (TDD)
- **Clean Architecture** - Follow layer separation
- **Code quality** - Pass `mix format`, `mix credo`, `mix dialyzer`
- **Documentation** - Update relevant docs and guides
- **Commit messages** - Follow [Conventional Commits](https://www.conventionalcommits.org/)

### Areas for Contribution

- 🐛 Bug fixes and stability improvements
- 📝 Documentation and tutorials
- 🧪 Additional test coverage
- 🎨 Python SDK improvements
- 🚀 Performance optimizations
- 🌐 New language SDKs (Kotlin, TypeScript)

---

## 📊 Project Status

- **Version:** 0.1.0 (Production Ready)
- **Phase:** 8/8 Complete
- **License:** MIT
- **Last Updated:** December 2024
- **Active Development:** Yes
- **Production Users:** Internal use

### Stats

- **Lines of Code:** ~10,000 (Elixir core)
- **Test Coverage:** 40 test files
- **Production Files:** 63 `.ex` files
- **Event Throughput:** 640K+ events/second
- **Supported Languages:** Elixir, Python (Kotlin/TypeScript planned)

---

## 🆘 Support & Community

### Getting Help

- **Documentation:** [guides/](./guides/), [specs/](./specs/)
- **Issues:** [GitHub Issues](https://github.com/cerebelum-io/cerebelum-core/issues)
- **Discussions:** [GitHub Discussions](https://github.com/cerebelum-io/cerebelum-core/discussions)

### Troubleshooting

**Problem:** Database connection refused

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Verify credentials in .env or config/dev.exs
psql -h localhost -U cerebelum -d cerebelum_prod
```

**Problem:** gRPC connection refused

```bash
# Enable gRPC server in config
config :cerebelum_core, enable_grpc_server: true

# Verify port is open
netstat -tlnp | grep 9090
```

See [DEPLOYMENT.md](./DEPLOYMENT.md) for more troubleshooting.

---

## 📜 License

MIT License - see [LICENSE](./LICENSE) for details.

Copyright (c) 2024 Cerebelum.io

---

## 🙏 Acknowledgments

Built with:
- [Elixir](https://elixir-lang.org/) - Functional programming on Erlang VM
- [PostgreSQL](https://www.postgresql.org/) - World's most advanced open source database
- [gRPC](https://grpc.io/) - High-performance RPC framework
- [Ecto](https://hexdocs.pm/ecto/) - Database wrapper and query language

Inspired by:
- [Temporal](https://temporal.io/) - Workflow orchestration
- [LangGraph](https://github.com/langchain-ai/langgraph) - Graph-based workflows
- [Event Sourcing](https://martinfowler.com/eaaDev/EventSourcing.html) - Martin Fowler's pattern

---

## 🔗 Links

- **GitHub:** [https://github.com/cerebelum-io/cerebelum-core](https://github.com/cerebelum-io/cerebelum-core)
- **Documentation:** [guides/](./guides/) • [specs/](./specs/)
- **Examples:** [examples/python-sdk/](./examples/python-sdk/)
- **Deployment:** [DEPLOYMENT.md](./DEPLOYMENT.md)

---

<div align="center">

**Made with ❤️ using Elixir and OTP**

[⬆ Back to Top](#cerebelum-core)

</div>

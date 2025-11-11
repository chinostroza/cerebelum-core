# Requirements - Cerebelum Core

**Module:** cerebelum-core
**Version:** 0.1.0
**Status:** Draft

## Introduction

Cerebelum Core is the foundational workflow orchestration engine. It provides deterministic execution, event sourcing, and graph-based state management for building reliable, reproducible workflows.

**Scope:** Core orchestration capabilities **without** AI-specific features (those are in `cerebelum-ai`).

**Key Principles:**
- General-purpose workflow engine
- Deterministic and reproducible
- Event-sourced for complete history
- Clean Architecture for maintainability
- No external service dependencies (pure orchestration)

---

## Requirements

### Requirement 1: Code-First Workflow Definition

**User Story:** As a developer, I want to define workflows using pure Elixir code so that I get compile-time validation, type safety, IDE support, and trivial testing.

#### Acceptance Criteria

1. WHEN developer creates workflow module THEN system SHALL provide `use Cerebelum.Workflow` macro for DSL
2. IF workflow references non-existent function THEN Elixir compiler SHALL fail with compile-time error
3. WHILE workflow is being defined THEN system SHALL support nodes as module functions with standard signatures
4. WHERE workflow contains conditional branches THEN system SHALL evaluate edge conditions using pattern matching or guards
5. WHEN workflow module is compiled THEN system SHALL extract and validate workflow graph structure
6. IF function has incorrect arity THEN Elixir compiler SHALL fail with clear error message
7. WHILE workflow execution is in progress THEN original module code SHALL remain immutable (versioned)
8. WHERE workflow has circular dependencies THEN system SHALL detect during compile-time graph analysis

**Code-First Features:**
```elixir
defmodule MyWorkflow do
  use Cerebelum.Workflow

  @doc "Start node"
  def start(input), do: {:ok, Map.put(input, :status, :started)}

  @doc "Process data"
  def process(state), do: {:ok, transform(state)}

  def finish(state), do: {:ok, state}

  # Define graph using function references (compile-time checked!)
  workflow do
    edge &start/1 -> &process/1
    edge &process/1 -> &finish/1
  end
end
```

**Compile-Time Validation:**
- Module existence checked by compiler
- Function existence checked by compiler
- Function arity checked by compiler
- Type specs validated by Dialyzer
- Undefined variables caught immediately
- Pattern matching errors detected

**Edge Cases:**
- Workflows with no edges (single-node)
- Self-referencing nodes (recursive calls)
- Disconnected graph components
- Private functions referenced in workflow
- Dynamic function references (not allowed)
- Workflows calling other workflows

---

### Requirement 2: Deterministic Time Management

**User Story:** As a developer, I want time-dependent operations to be deterministic so that workflow executions are 100% reproducible across runs.

#### Acceptance Criteria

1. WHEN workflow uses `DateTime.utc_now()` THEN system SHALL return controlled deterministic time
2. IF workflow calls `Process.sleep(ms)` THEN system SHALL advance virtual time without actual waiting
3. WHILE deterministic mode is active THEN system SHALL maintain separate virtual time per workflow execution
4. WHERE workflow schedules delayed tasks THEN system SHALL execute them at deterministic virtual timestamps
5. WHEN workflow execution is replayed THEN system SHALL use identical time sequence as original run
6. IF workflow execution spans multiple OTP processes THEN system SHALL synchronize deterministic time across all processes
7. WHILE time-based operations execute THEN system SHALL record all time operations in event log
8. WHERE workflow requests current time multiple times THEN system SHALL return monotonically increasing time values

**Edge Cases:**
- Time operations across process boundaries
- Timezone conversions in deterministic mode
- Leap seconds and DST transitions
- Concurrent time requests from parallel nodes
- Negative time deltas

---

### Requirement 3: Deterministic Random Operations

**User Story:** As a developer, I want random operations to be reproducible so that workflows with randomness can be debugged and tested.

#### Acceptance Criteria

1. WHEN workflow uses `:rand.uniform()` THEN system SHALL return seeded deterministic random values
2. IF workflow generates UUIDs THEN system SHALL produce deterministic UUIDs based on execution seed
3. WHILE deterministic mode is active THEN system SHALL maintain per-execution random seed
4. WHERE workflow uses `Enum.shuffle()` THEN system SHALL produce identical shuffle order on replay
5. WHEN workflow execution is replayed THEN system SHALL use same random seed as original execution
6. IF multiple nodes request random values concurrently THEN system SHALL ensure deterministic ordering
7. WHILE random operations execute THEN system SHALL record random calls in event log
8. WHERE workflow forks into parallel branches THEN system SHALL assign deterministic sub-seeds to each branch

**Edge Cases:**
- Random operations in recursive functions
- Random seed overflow/exhaustion
- Cryptographic vs non-cryptographic randomness
- Random operations in error handlers
- Concurrent random requests

---

### Requirement 4: External Call Memoization

**User Story:** As a developer, I want external API calls and database queries to be recorded and replayed so that workflows are fully deterministic even with external dependencies.

#### Acceptance Criteria

1. WHEN workflow makes HTTP request THEN system SHALL record request and response for replay
2. IF workflow executes database query THEN system SHALL memoize query results
3. WHILE workflow is being replayed THEN system SHALL return memoized responses instead of making real calls
4. WHERE memoized call doesn't exist during replay THEN system SHALL fail with descriptive error
5. WHEN workflow makes identical external call twice THEN system SHALL record both calls separately
6. IF external call fails during recording THEN system SHALL record failure for replay
7. WHILE memoization is active THEN system SHALL hash call parameters to detect changes
8. WHERE workflow execution uses different parameters on replay THEN system SHALL detect divergence and warn

**Edge Cases:**
- External calls with side effects
- Non-idempotent API operations
- Large response payloads (>1MB)
- Streaming responses
- WebSocket connections
- File system operations

---

### Requirement 5: Workflow Versioning and Evolution

**User Story:** As a developer, I want to replay old workflow executions even after code changes so that I can debug production issues.

#### Acceptance Criteria

1. WHEN workflow module code changes THEN system SHALL create new version while preserving old module bytecode
2. IF workflow execution is replayed THEN system SHALL use exact module version (BEAM bytecode) from original execution
3. WHILE workflow code evolves THEN system SHALL maintain version registry with compiled module snapshots
4. WHERE workflow module is recompiled THEN system SHALL detect version mismatch during replay
5. WHEN workflow version is incompatible THEN system SHALL provide clear migration path or compatibility mode
6. IF workflow calls other modules THEN system SHALL snapshot dependency module bytecode with execution
7. WHILE multiple workflow versions exist THEN system SHALL allow selective cleanup of old versions
8. WHERE workflow has breaking changes (function signature changes) THEN system SHALL prevent replay and suggest re-execution

**Module Version Tracking:**
- Store compiled BEAM bytecode for each version
- Hash module attributes and function signatures
- Detect function signature changes (arity, return types)
- Track `@moduledoc`, `@vsn`, and custom version attributes
- Maintain version graph for migrations

**Edge Cases:**
- Deleted workflow modules
- Module renaming/moving in codebase
- Dependency version changes (Hex packages)
- Elixir version upgrades
- OTP behavior changes
- Private function changes (internal refactoring)

---

### Requirement 6: Event Sourcing and Execution History

**User Story:** As a developer, I want complete execution history stored as events so that I can analyze, replay, and debug any workflow run.

#### Acceptance Criteria

1. WHEN workflow executes THEN system SHALL emit events for every state transition
2. IF node completes execution THEN system SHALL record node result, timing, and metadata
3. WHILE workflow is running THEN system SHALL stream events to event store in real-time
4. WHERE workflow fails THEN system SHALL record complete error context and stack trace
5. WHEN events are queried THEN system SHALL return chronologically ordered event stream
6. IF event store is unavailable THEN system SHALL buffer events in memory with overflow handling
7. WHILE events are being recorded THEN system SHALL include correlation IDs for distributed tracing
8. WHERE execution spans multiple nodes THEN system SHALL link events with parent-child relationships

**Edge Cases:**
- Event store failures
- Event ordering in concurrent execution
- Large event payloads
- Event schema evolution
- Long-running workflows with millions of events

---

### Requirement 7: Time Travel Debugging

**User Story:** As a developer, I want to step through workflow execution history event by event so that I can understand exactly what happened at each step.

#### Acceptance Criteria

1. WHEN debug session is created THEN system SHALL load complete execution history
2. IF developer requests step forward THEN system SHALL advance to next event and update state
3. WHILE stepping through execution THEN system SHALL display current function, state, and variables
4. WHERE developer jumps to specific event THEN system SHALL reconstruct state up to that point
5. WHEN developer requests current state THEN system SHALL show exact workflow state at that event
6. IF execution contains errors THEN system SHALL allow stepping up to and past error event
7. WHILE debugging THEN system SHALL support breakpoints on specific functions (e.g., `&MyWorkflow.process/1`)
8. WHERE execution has parallel branches THEN system SHALL show concurrent execution timeline

**Debug Visualization:**
```elixir
# Example debug output
Cerebelum.Debug.step_forward(execution_id)
# =>
# Function: MyWorkflow.process/1
# State: %{order_id: "123", total: 99.99}
# Event: node_completed
# Timestamp: 2024-01-15T10:30:45Z
# Next: &MyWorkflow.charge_card/1
```

**Edge Cases:**
- Stepping through infinite loops (recursive functions)
- Debugging recursive workflows
- Very large state objects (>10MB)
- Debugging across process boundaries
- Concurrent execution visualization

---

### Requirement 8: Clean Architecture Compliance

**User Story:** As a developer, I want the codebase to follow Clean Architecture so that it remains maintainable as complexity grows.

#### Acceptance Criteria

1. WHEN adding new features THEN system SHALL enforce layer separation (Domain, Application, Infrastructure, Presentation)
2. IF Infrastructure needs domain logic THEN it SHALL implement behaviours defined in Domain ports
3. WHILE developing THEN dependencies SHALL flow inward toward Domain layer only
4. WHERE Application layer needs external services THEN it SHALL depend on abstractions, not concrete implementations
5. WHEN testing components THEN each layer SHALL be independently testable via dependency injection
6. IF Domain entities change THEN Infrastructure layer SHALL adapt without affecting Application layer
7. WHILE adding adapters THEN new implementations SHALL satisfy existing port contracts
8. WHERE business rules exist THEN they SHALL reside only in Domain layer, never in Infrastructure

**Edge Cases:**
- Circular dependencies across layers
- Shared utilities placement
- Cross-cutting concerns (logging, metrics)
- Framework-specific code isolation

---

### Requirement 9: SOLID Principles Implementation

**User Story:** As a developer, I want code to follow SOLID principles so that features are easy to extend without breaking existing functionality.

#### Acceptance Criteria

1. WHEN creating modules THEN each SHALL have single, well-defined responsibility (SRP)
2. IF extending functionality THEN system SHALL use behaviours and protocols for extension (OCP)
3. WHILE implementing behaviours THEN implementations SHALL be substitutable (LSP)
4. WHERE defining interfaces THEN they SHALL be specific and cohesive, not monolithic (ISP)
5. WHEN high-level modules need low-level functionality THEN they SHALL depend on abstractions (DIP)
6. IF use case needs multiple services THEN it SHALL receive them via dependency injection
7. WHILE adding node types THEN system SHALL use plugin architecture without modifying core
8. WHERE validation logic exists THEN it SHALL be composable via small, focused validators

---

### Requirement 10: Comprehensive Testing Strategy

**User Story:** As a developer, I want comprehensive test coverage so that I can refactor confidently without breaking functionality.

#### Acceptance Criteria

1. WHEN adding Domain entities THEN unit tests SHALL verify business logic in isolation
2. IF creating use cases THEN tests SHALL use mocks for external dependencies
3. WHILE implementing Infrastructure THEN integration tests SHALL verify database and external services
4. WHERE adding API endpoints THEN controller tests SHALL verify HTTP contracts
5. WHEN writing deterministic features THEN property tests SHALL verify reproducibility
6. IF implementing behaviours THEN contract tests SHALL verify all implementations satisfy interface
7. WHILE developing THEN test coverage SHALL maintain minimum 90% line coverage
8. WHERE bugs are found THEN regression tests SHALL be added before fixing

**Test Types Required:**
- Unit tests (Domain layer)
- Use case tests (Application layer)
- Integration tests (Infrastructure layer)
- API tests (Presentation layer)
- Property-based tests (Deterministic behavior)
- Contract tests (Behaviour implementations)

---

### Requirement 11: Workflow Execution Engine

**User Story:** As a developer, I want to execute workflows with support for sequential, parallel, and conditional execution so that I can model complex business processes.

#### Acceptance Criteria

1. WHEN workflow starts THEN system SHALL execute from designated entrypoint function
2. IF function completes successfully THEN system SHALL follow edges to next functions
3. WHILE executing parallel functions THEN system SHALL run them concurrently using Task.async without blocking
4. WHERE edge has condition (guard or pattern match) THEN system SHALL evaluate condition before traversal
5. WHEN all functions complete THEN system SHALL mark workflow as completed
6. IF function execution raises exception THEN system SHALL execute error handler function if defined
7. WHILE workflow runs THEN system SHALL enforce timeout limits per function and total execution
8. WHERE workflow has cycles THEN system SHALL detect infinite loops and terminate with error

**Execution Model:**
```elixir
defmodule MyWorkflow do
  use Cerebelum.Workflow

  # Sequential execution
  def start(input), do: {:ok, input}
  def process(state), do: {:ok, transform(state)}

  # Parallel execution - returns list of async tasks
  def parallel_step(state) do
    {:parallel, [
      fn -> fetch_user(state) end,
      fn -> fetch_orders(state) end,
      fn -> fetch_inventory(state) end
    ]}
  end

  # Conditional branching via pattern matching
  def conditional_step({:ok, data}), do: {:ok, data}
  def conditional_step({:error, reason}), do: {:error, reason}

  # Delay execution (doesn't block BEAM)
  def wait_step(state), do: {:sleep, seconds: 60, state: state}

  # Error handler
  def handle_error(state, error), do: {:compensate, error}

  workflow do
    edge &start/1 -> &process/1
    edge &process/1 -> &parallel_step/1
    edge &parallel_step/1 -> &conditional_step/1
  end
end
```

**Function Return Types:**
- `{:ok, state}` - Continue to next edge
- `{:error, reason}` - Trigger error handler
- `{:sleep, opts, state}` - Pause without blocking
- `{:parallel, tasks}` - Execute tasks concurrently
- `{:wait_for_approval, opts}` - Human-in-the-loop pause

---

### Requirement 14: Workflow State Checkpointing

**User Story:** As a developer, I want to save workflow state at arbitrary points so that long-running workflows can resume after crashes.

#### Acceptance Criteria

1. WHEN checkpoint is created THEN system SHALL serialize complete workflow state
2. IF workflow process crashes THEN system SHALL restore from last checkpoint
3. WHILE checkpoint is being created THEN execution SHALL pause briefly without losing events
4. WHERE checkpoint is restored THEN workflow SHALL resume from exact same state
5. WHEN checkpoint is requested THEN system SHALL include deterministic context (time seed, random seed, memoization state)
6. IF checkpoint data is corrupted THEN system SHALL detect corruption and fail fast with clear error
7. WHILE checkpoint is stored THEN system SHALL use compression to minimize storage
8. WHERE multiple checkpoints exist THEN system SHALL allow selective restoration to any checkpoint

---

### Requirement 16: Database Persistence

**User Story:** As a system administrator, I want workflow data persisted in PostgreSQL so that data survives system restarts.

#### Acceptance Criteria

1. WHEN workflow is created THEN system SHALL persist definition to database
2. IF execution starts THEN system SHALL create execution record with initial state
3. WHILE execution runs THEN system SHALL update execution status and progress
4. WHERE events are generated THEN system SHALL batch insert events for performance
5. WHEN querying workflows THEN system SHALL support filtering by status, date, and tags
6. IF database is unavailable THEN system SHALL fail gracefully and return 503 Service Unavailable
7. WHILE under load THEN system SHALL use connection pooling with configured pool size
8. WHERE data grows large THEN system SHALL support partitioning by date for event tables

**Database Schema:**
- workflows table (id, definition, version, created_at)
- executions table (id, workflow_id, status, started_at, completed_at)
- events table (id, execution_id, type, payload, timestamp)
- checkpoints table (id, execution_id, state, created_at)

---

### Requirement 18: Error Handling and Recovery

**User Story:** As a developer, I want comprehensive error handling so that workflow failures are graceful and debuggable.

#### Acceptance Criteria

1. WHEN node execution fails THEN system SHALL capture exception, message, and stacktrace
2. IF error handler is defined THEN system SHALL execute error handler with error context
3. WHILE error propagates THEN system SHALL mark execution as failed with failure reason
4. WHERE retry policy is configured THEN system SHALL retry failed nodes with backoff
5. WHEN unhandled error occurs THEN system SHALL fail workflow but preserve all events
6. IF supervisor detects crash THEN system SHALL restart process and restore from checkpoint
7. WHILE debugging failures THEN system SHALL provide full error context in event log
8. WHERE multiple errors occur THEN system SHALL aggregate errors and report all failure points

**Error Categories:**
- Validation errors (4xx equivalent)
- Execution errors (runtime failures)
- Timeout errors
- Resource exhaustion errors
- External service errors
- System errors (5xx equivalent)

---

### Requirement 20: Horizontal Scalability and Distributed Execution

**User Story:** As a system architect, I want the system to scale linearly from 1 node to 1000+ nodes using the same architecture, so that I never need to migrate or rewrite code when growing from MVP to enterprise scale.

**Competitive Context:** Must match Temporal.io's scalability (1M+ concurrent workflows) while maintaining simpler operations (1 service vs 5+ services).

#### Acceptance Criteria - Day 1 Scalability

1. WHEN system is deployed on 1 node THEN it SHALL use distributed architecture (Horde) that works identically on N nodes
2. IF deploying to production THEN system SHALL NOT require code changes to scale from 1 to 1000 nodes
3. WHILE adding nodes to cluster THEN system SHALL automatically discover new nodes via libcluster
4. WHERE executions are distributed THEN system SHALL use Horde.DynamicSupervisor for automatic load balancing
5. WHEN looking up execution THEN system SHALL use Horde.Registry for distributed lookup from any node
6. IF node crashes THEN system SHALL automatically failover executions to healthy nodes within 5 seconds
7. WHILE failover occurs THEN system SHALL recover execution state from event store with zero data loss
8. WHERE multiple deployment strategies exist THEN system SHALL support Kubernetes, Docker Swarm, and manual clustering

#### Acceptance Criteria - Performance Targets

9. WHEN running on single node (8 cores, 16GB RAM) THEN system SHALL support minimum 100,000 concurrent executions
10. IF running on 10 nodes THEN system SHALL support minimum 1,000,000 concurrent executions (linear scaling)
11. WHILE processing workflows THEN system SHALL maintain p99 latency < 50ms for single step execution
12. WHERE throughput is measured THEN system SHALL process minimum 100,000 workflows/second on 10 nodes
13. WHEN comparing to Temporal.io THEN system SHALL achieve equivalent throughput with fewer resources
14. IF memory per workflow is measured THEN system SHALL use < 1KB per concurrent execution
15. WHILE database writes occur THEN system SHALL use partitioned tables (minimum 64 partitions) for write scalability
16. WHERE event storage is measured THEN system SHALL achieve minimum 640,000 events/second with 64 partitions

#### Acceptance Criteria - Clustering and Discovery

17. WHEN deploying to Kubernetes THEN system SHALL use DNS-based discovery via libcluster
18. IF deploying to development THEN system SHALL work on single node without clustering configuration
19. WHILE cluster topology changes THEN system SHALL handle node joins/leaves gracefully
20. WHERE network partition occurs THEN system SHALL continue operating on majority partition
21. WHEN cluster forms THEN system SHALL elect no leader (leaderless architecture for HA)
22. IF using Horde THEN system SHALL configure delta-CRDT sync interval < 100ms
23. WHILE nodes communicate THEN system SHALL use Erlang distribution protocol (no gRPC overhead)
24. WHERE cluster health is monitored THEN system SHALL expose metrics for node count, execution distribution, and cluster lag

#### Acceptance Criteria - Load Balancing and Distribution

25. WHEN starting new execution THEN Horde SHALL select node with lowest current load automatically
26. IF node reaches capacity THEN system SHALL refuse new executions until capacity available
27. WHILE executions run THEN system SHALL distribute evenly across all nodes (< 10% variance)
28. WHERE execution affinity is needed THEN system SHALL support pinning executions to specific nodes
29. WHEN node is draining THEN system SHALL prevent new executions and allow existing to complete
30. IF node is removed THEN system SHALL redistribute executions to remaining nodes within 10 seconds
31. WHILE rebalancing THEN system SHALL NOT interrupt running executions
32. WHERE cluster scales up THEN new nodes SHALL start receiving executions immediately

#### Acceptance Criteria - Failover and High Availability

33. WHEN node crashes THEN Horde SHALL detect failure within 5 seconds via heartbeat timeout
34. IF execution was running on crashed node THEN system SHALL restart on healthy node automatically
35. WHILE recovering execution THEN system SHALL reconstruct state from event store
36. WHERE execution has no events THEN system SHALL restart from beginning
37. WHEN failover completes THEN execution SHALL continue from last committed event
38. IF execution fails repeatedly THEN system SHALL implement exponential backoff before retries
39. WHILE cluster has failures THEN system SHALL maintain operation with majority of nodes healthy
40. WHERE multiple nodes fail THEN system SHALL NOT lose any committed events (event store is durable)

#### Acceptance Criteria - Caching Strategy

41. WHEN accessing workflow metadata THEN system SHALL use Persistent Term (fastest, immutable)
42. IF caching execution snapshots THEN system SHALL use ETS per-node (fast, mutable)
43. WHILE looking up execution location THEN system SHALL use Horde.Registry (distributed, consistent)
44. WHERE cache hit rate is measured THEN workflow metadata SHALL achieve > 99% hit rate
45. WHEN cache is invalidated THEN only affected entries SHALL be removed (no full flush)
46. IF memory pressure occurs THEN ETS caches SHALL implement TTL-based eviction
47. WHILE distributed cache syncs THEN system SHALL tolerate < 100ms eventual consistency
48. WHERE cache coherency is required THEN system SHALL use Horde Registry as source of truth

#### Acceptance Criteria - Database Scalability

49. WHEN storing events THEN system SHALL partition by execution_id hash across minimum 64 tables
50. IF query load is high THEN system SHALL support PostgreSQL read replicas for query distribution
51. WHILE writing events THEN system SHALL batch inserts when possible (< 100ms window)
52. WHERE database is partitioned THEN each partition SHALL have independent indexes
53. WHEN event table grows THEN system SHALL support table sharding beyond single database
54. IF using CockroachDB THEN system SHALL achieve automatic global distribution
55. WHILE queries execute THEN system SHALL maintain p95 < 5ms for single-partition queries
56. WHERE database bottleneck exists THEN system SHALL provide clear metrics for diagnosis

**Performance Targets (Enterprise Scale):**

**Single Node (8 cores, 16GB RAM):**
- Concurrent executions: 100,000
- Throughput: 10,000 workflows/second
- Latency p99: < 50ms
- Memory per execution: < 1KB

**10 Nodes Cluster:**
- Concurrent executions: 1,000,000
- Throughput: 100,000 workflows/second
- Latency p99: < 100ms (includes network overhead)
- Event writes: 640,000/second (64 partitions)

**100 Nodes Cluster:**
- Concurrent executions: 10,000,000
- Throughput: 1,000,000 workflows/second
- Latency p99: < 150ms
- Event writes: 6,400,000/second

**Scaling Characteristics:**
- Linear scaling up to 100 nodes
- < 10% variance in load distribution
- < 5 second failover time
- Zero data loss on node failure
- Zero downtime deployments via hot code reload

**Comparison to Temporal.io:**
- Match: Concurrent workflow capacity (1M+)
- Match: Throughput (100K+ workflows/sec)
- Better: Operational complexity (1 service vs 5+)
- Better: Latency (BEAM vs gRPC overhead)
- Better: Resource efficiency (fewer servers needed)
- Better: Developer experience (same code 1-1000 nodes)

**Edge Cases:**
- All nodes crash simultaneously (recover from database)
- Network partition (split-brain scenarios)
- Node with 90% of executions crashes (redistribution load)
- Rapid scaling up/down (rebalancing performance)
- Database unavailable (in-memory operation degradation)
- Event storage full (backpressure and alerting)

---

### Requirement 21: Development Experience

**User Story:** As a developer, I want excellent DX so that I can be productive quickly.

#### Acceptance Criteria

1. WHEN starting development THEN `mix setup` SHALL install all dependencies and setup database
2. IF running tests THEN `mix test` SHALL execute all tests with clear output
3. WHILE coding THEN `mix format` SHALL format code according to project standards
4. WHERE code quality is checked THEN `mix quality` SHALL run linting, formatting, and type checking
5. WHEN documentation is needed THEN `mix docs` SHALL generate comprehensive HTML docs
6. IF starting server THEN `mix phx.server` SHALL start with live reload enabled
7. WHILE debugging THEN IEx sessions SHALL support full introspection and tracing
8. WHERE deploying THEN `mix release` SHALL build production-ready release

**DX Features:**
- Single command setup (`mix setup`)
- Fast test suite (< 5 seconds for unit tests)
- Live reload for development
- Comprehensive error messages
- Interactive debugging (IEx)
- Generated API documentation

---

### Requirement 34: Graph-Based State Management

**Module:** `cerebelum-core` (core package)
**Dependencies:** None (core feature)

**User Story:** As a developer, I want to define workflows as graphs with cycles so that agents can iterate until a condition is met (like LangGraph).

#### Acceptance Criteria

1. WHEN defining workflow THEN developer SHALL specify functions and conditional edges using pattern matching
2. IF edge has condition (guard clause or pattern) THEN system SHALL evaluate condition before traversal
3. WHILE executing graph THEN system SHALL support cycles for iterative refinement
4. WHERE cycle detected THEN system SHALL track iteration count and enforce max limit
5. WHEN state merges THEN system SHALL apply merge strategy (replace, append, custom function)
6. IF function has parallel edges THEN system SHALL execute target functions concurrently
7. WHILE iterating THEN system SHALL record all iterations in event log
8. WHERE termination condition met THEN system SHALL exit loop and proceed

**Code-First Graph Definition:**
```elixir
defmodule IterativeWorkflow do
  use Cerebelum.Workflow

  @max_iterations 5

  # Generate initial content
  def generate(state) do
    content = AI.generate(state.prompt)
    {:ok, Map.put(state, :content, content)}
  end

  # Evaluate quality - returns different tuples based on quality
  def evaluate(%{content: content, iteration: iter} = state) when iter >= @max_iterations do
    {:max_iterations, state}  # Force exit after max iterations
  end

  def evaluate(%{content: content} = state) do
    case quality_check(content) do
      {:ok, score} when score >= 0.8 ->
        {:high_quality, Map.put(state, :score, score)}
      {:ok, score} ->
        {:needs_improvement, Map.put(state, :score, score)}
    end
  end

  # Improve content based on feedback
  def improve(state) do
    improved = AI.improve(state.content, state.feedback)
    iteration = Map.get(state, :iteration, 0) + 1

    state
    |> Map.put(:content, improved)
    |> Map.put(:iteration, iteration)
    |> then(&{:ok, &1})
  end

  # Finalize result
  def finalize(state) do
    {:ok, Map.put(state, :status, :completed)}
  end

  # Define graph with cycles
  workflow do
    edge &generate/1 -> &evaluate/1

    # Conditional edges based on pattern matching
    edge &evaluate/1 -> &finalize/1, when: {:high_quality, _}
    edge &evaluate/1 -> &improve/1, when: {:needs_improvement, _}
    edge &evaluate/1 -> &finalize/1, when: {:max_iterations, _}

    # Cycle: improve loops back to generate
    edge &improve/1 -> &generate/1
  end
end
```

**State Management:**
- State is immutable (pure functional)
- Each function returns `{:ok, new_state}` or `{:status, new_state}`
- Pattern matching on return tuples determines edge traversal
- Merge strategies for parallel edges via custom functions
- State history tracked in event log

**Safety Features:**
- Max iterations limit (compile-time constant `@max_iterations`)
- Guard clauses prevent infinite loops
- Timeout per iteration (enforced by execution engine)
- Cycle detection with warnings in compile-time graph analysis
- State size limits (configurable per workflow)

---

### Requirement 35: Multi-Language SDK Support

**User Story:** As a developer using Kotlin/TypeScript/Python/etc., I want to define and execute workflows using my preferred language's native syntax so that I can leverage Cerebelum without learning Elixir.

**Philosophy:** DX-First - The SDK must feel native to each ecosystem, not a "Cerebelum style" imposed on all languages.

#### Acceptance Criteria - Core Principles

1. WHEN developer uses SDK THEN syntax SHALL feel native to their language ecosystem
2. IF developer references non-existent step THEN IDE/compiler SHALL show error before runtime
3. WHILE defining workflows THEN developer SHALL NEVER use strings to reference steps
4. WHEN developer writes step function THEN IDE SHALL autocomplete input/output types
5. WHEN workflow compiles THEN type mismatches SHALL be caught before execution

#### Acceptance Criteria - Kotlin SDK (Priority 1)

6. WHEN Kotlin developer defines workflow THEN they SHALL use Jetpack Compose-style lambda with receiver syntax
7. WHEN Kotlin developer references step function THEN they SHALL use `::functionName` syntax (KFunction)
8. WHEN Kotlin developer writes `branch(on = validate)` THEN IDE SHALL autocomplete `validate` variable (StepRef)
9. WHEN Kotlin developer writes condition `{ it.amount > 1000 }` THEN `it` SHALL be typed as Order (not Any)
10. WHEN Kotlin developer compiles workflow THEN Kotlin compiler SHALL verify all step references exist
11. IF Kotlin developer tries `skipTo(nonExistent)` THEN IDE SHALL show "Unresolved reference: nonExistent"
12. WHEN Kotlin developer runs workflow locally THEN no infrastructure SHALL be required
13. WHEN Kotlin developer runs workflow distributed THEN worker SHALL connect via gRPC to Core BEAM

**Example:**
```kotlin
val orderFlow = workflow("order-flow") {
    val validate = step<OrderInput, Order>(::validateOrder)
    val payment = step<Order, Payment>(::chargePayment)
    val notify = step<Payment, Unit>(::sendNotification)

    timeline {
        +validate  // StepRef<OrderInput, Order>
        +payment   // StepRef<Order, Payment>
        +notify    // StepRef<Payment, Unit>
    }

    diverge(on = payment) {
        pattern<PaymentError.Timeout> { retry(maxAttempts = 3) }
        pattern<PaymentError.InsufficientFunds> { failed() }
    }

    branch(on = validate) {
        condition { it.amount > 10000 } then skipTo(manualReview)
        //          ^^ 'it' is typed as Order, IDE autocompletes .amount
        condition { it.fraudScore > 0.9 } then backTo(validate)
        otherwise { continue() }
    }
}

// Step functions
fun validateOrder(input: OrderInput): Order { /* ... */ }
fun chargePayment(ctx: Context, order: Order): Payment { /* ... */ }
fun sendNotification(ctx: Context, payment: Payment) { /* ... */ }
```

#### Acceptance Criteria - TypeScript SDK (Priority 1)

14. WHEN TypeScript developer defines workflow THEN they SHALL use builder pattern with type inference
15. WHEN TypeScript developer passes step function THEN TypeScript SHALL infer input/output types
16. WHEN TypeScript developer writes `diverge` block THEN pattern matching SHALL be type-safe
17. WHEN TypeScript developer compiles code THEN `tsc` SHALL verify all step references exist
18. IF TypeScript developer tries `skipTo("nonExistent")` THEN TypeScript compiler SHALL error
19. WHEN TypeScript developer uses VSCode THEN IntelliSense SHALL autocomplete step names
20. WHEN TypeScript developer runs `npm test` THEN local execution SHALL work without Docker

**Example:**
```typescript
const orderFlow = workflow({
  id: "order-flow",
  steps: {
    validateOrder: (input: OrderInput): Order => { /* ... */ },
    chargePayment: (ctx: Context, order: Order): Payment => { /* ... */ },
    sendNotification: (ctx: Context, payment: Payment): void => { /* ... */ }
  },
  timeline: ["validateOrder", "chargePayment", "sendNotification"],
  diverge: {
    chargePayment: [
      { pattern: { type: "timeout" }, action: retry({ maxAttempts: 3 }) },
      { pattern: { type: "insufficient_funds" }, action: failed() }
    ]
  },
  branch: {
    validateOrder: [
      { condition: (order) => order.amount > 10000, action: skipTo("manualReview") },
      { condition: (order) => order.fraudScore > 0.9, action: backTo("validateOrder") }
    ]
  }
});
```

#### Acceptance Criteria - Python SDK (Priority 2)

21. WHEN Python developer defines workflow THEN they SHALL use context managers (`with` statement)
22. WHEN Python developer references step THEN they SHALL use function object (not string)
23. WHEN Python developer uses type hints THEN `mypy` SHALL verify step signatures
24. WHEN Python developer writes condition THEN lambda SHALL receive typed parameter
25. WHEN Python developer uses IDE THEN PyCharm/VSCode SHALL autocomplete step attributes
26. WHEN Python developer runs `pytest` THEN local execution SHALL work without containers

**Example:**
```python
order_flow = WorkflowBuilder("order-flow")

with order_flow.timeline() as tl:
    tl.step(validate_order)
    tl.step(charge_payment)
    tl.step(send_notification)

with order_flow.diverge(on=charge_payment) as div:
    div.pattern(PaymentError.Timeout).then(retry(max_attempts=3))
    div.pattern(PaymentError.InsufficientFunds).then(failed())

with order_flow.branch(on=validate_order) as br:
    br.condition(lambda order: order.amount > 10000).then(skip_to(manual_review))
    br.condition(lambda order: order.fraud_score > 0.9).then(back_to(validate_order))

def validate_order(input: OrderInput) -> Order: ...
def charge_payment(ctx: Context, order: Order) -> Payment: ...
def send_notification(ctx: Context, payment: Payment) -> None: ...
```

#### Acceptance Criteria - Execution Modes

27. WHEN developer runs workflow in Local Mode THEN execution SHALL happen in-process
28. WHEN developer runs workflow in Local Mode THEN no external infrastructure SHALL be required
29. WHEN developer runs workflow in Local Mode THEN debugger SHALL work normally
30. WHEN developer switches to Distributed Mode THEN same workflow code SHALL work without changes
31. WHEN workflow runs in Distributed Mode THEN Core BEAM SHALL orchestrate execution
32. WHEN workflow runs in Distributed Mode THEN worker SHALL execute step functions
33. WHEN workflow runs in Distributed Mode THEN results SHALL be sent back via gRPC

**Local Mode:**
```kotlin
val executor = LocalExecutor()
val result = executor.execute(orderFlow, OrderInput(...))
// Runs in same process, instant feedback, breakpoints work
```

**Distributed Mode:**
```kotlin
val executor = DistributedExecutor(
    coreUrl = "grpc://cerebelum.prod:9090"
)
val result = executor.execute(orderFlow, OrderInput(...))
// Worker registers with Core, polls for tasks, executes steps
```

#### Acceptance Criteria - Type Safety

34. WHEN developer defines step `step<A, B>(fn)` THEN function signature SHALL be `fn: (A) -> B` or `fn: (Context, A) -> B`
35. IF developer passes wrong signature THEN compiler SHALL error at compile-time
36. WHEN developer chains steps in timeline THEN compiler SHALL verify output type matches next input type
37. WHEN developer writes `skipTo(target)` THEN `target` SHALL be typed as StepRef (not string)
38. WHEN developer uses phantom types THEN runtime SHALL have zero overhead

**Type Verification Examples:**
```kotlin
// ✅ Correct
val step1 = step<Int, String>(::processInt)       // (Int) -> String
val step2 = step<String, Boolean>(::processString) // (String) -> Boolean

timeline { +step1; +step2 }  // ✅ String matches String

// ❌ Compile error
val step3 = step<Boolean, Double>(::processDouble)
timeline { +step1; +step3 }  // ❌ String doesn't match Boolean
```

#### Acceptance Criteria - Worker Architecture

39. WHEN worker starts THEN it SHALL register with Core BEAM via gRPC
40. WHEN worker registers THEN it SHALL send: worker_id, language, version, capabilities
41. WHEN worker is idle THEN it SHALL long-poll Core for tasks (30s timeout)
42. WHEN Core assigns task THEN worker SHALL execute step function
43. WHEN step completes THEN worker SHALL send result back to Core via gRPC
44. WHEN worker crashes THEN Core SHALL reassign task to another worker
45. WHEN worker is healthy THEN it SHALL send heartbeat every 10 seconds

**Worker Protocol:**
```protobuf
service WorkerService {
  rpc Register(RegisterRequest) returns (RegisterResponse);
  rpc PollForTask(PollRequest) returns (Task);
  rpc SubmitResult(TaskResult) returns (Ack);
  rpc Heartbeat(HeartbeatRequest) returns (HeartbeatResponse);
}
```

#### Acceptance Criteria - Serialization

46. WHEN step result is simple type THEN JSON SHALL be used by default
47. WHEN step result is complex object THEN JSON SHALL serialize all fields
48. IF developer annotates type with @ProtoSerializable THEN Protobuf SHALL be used
49. WHEN using Protobuf THEN serialization SHALL be 3x faster than JSON
50. WHEN using JSON THEN developer SHALL NOT need schema definition

**Serialization Strategy:**
```kotlin
// Default: JSON (zero config)
data class Order(val id: String, val amount: Double)
val result = execute(step, order)  // Serialized as JSON

// Opt-in: Protobuf (performance critical)
@ProtoSerializable
data class LargeDataset(val records: List<Record>)
val result = execute(step, dataset)  // Serialized as Protobuf
```

#### Acceptance Criteria - Error Handling

51. WHEN step throws exception THEN worker SHALL catch and send error to Core
52. WHEN Core receives error THEN it SHALL evaluate `diverge` patterns
53. IF error matches pattern THEN Core SHALL execute corresponding action
54. IF error doesn't match any pattern THEN workflow SHALL fail
55. WHEN workflow fails THEN all events SHALL be persisted to event log
56. WHEN developer inspects failed workflow THEN they SHALL see full stack trace

#### Acceptance Criteria - Performance

57. WHEN single worker handles 1K workflows/sec THEN CPU SHALL be <50%
58. WHEN 100 workers handle 100K workflows/sec THEN p99 latency SHALL be <150ms
59. WHEN using Local Mode THEN overhead SHALL be <1ms vs direct function call
60. WHEN using Distributed Mode THEN gRPC overhead SHALL be <10ms per step

#### Acceptance Criteria - Developer Experience

61. WHEN developer installs SDK THEN single command SHALL set up everything
62. WHEN developer runs example THEN it SHALL work without configuration
63. WHEN developer reads docs THEN examples SHALL be in their language
64. WHEN developer gets compile error THEN message SHALL be clear and actionable
65. WHEN developer debugs workflow THEN they SHALL see readable event log

**Installation:**
```bash
# Kotlin
./gradlew add cerebelum-sdk

# TypeScript
npm install @cerebelum/sdk

# Python
pip install cerebelum-sdk
```

#### Acceptance Criteria - Blueprint Serialization

66. WHEN workflow compiles THEN SDK SHALL generate Blueprint JSON
67. WHEN Blueprint is sent to Core THEN it SHALL contain: timeline, diverges, branches, metadata
68. WHEN Core receives Blueprint THEN it SHALL validate structure
69. WHEN Core validates Blueprint THEN it SHALL check: step references, action targets, cycle detection
70. IF Blueprint is invalid THEN Core SHALL return validation errors before execution

**Blueprint Structure:**
```json
{
  "id": "order-flow",
  "version": "1.0.0",
  "timeline": ["validate", "payment", "notify"],
  "diverges": {
    "payment": [
      {"pattern": {"type": "timeout"}, "action": {"type": "retry", "max_attempts": 3}}
    ]
  },
  "branches": {
    "validate": [
      {"condition": "amount > 10000", "action": {"type": "skip_to", "target": "manual_review"}}
    ]
  },
  "steps_metadata": {
    "validate": {"input_type": "OrderInput", "output_type": "Order"}
  }
}
```

#### Acceptance Criteria - Worker Pooling

71. WHEN multiple workers register THEN Core SHALL maintain worker pool
72. WHEN Core assigns task THEN it SHALL use pull-based model (workers poll)
73. WHEN worker A executes step1 THEN Core SHOULD assign step2 to same worker (sticky routing)
74. WHEN worker is busy THEN Core SHALL NOT assign new tasks to it
75. WHEN worker pool is empty THEN Core SHALL queue tasks until worker available

**Sticky Routing Benefits:**
- Cache locality: Worker reuses loaded classes/modules
- Connection reuse: Same gRPC stream
- Memory efficiency: State can be kept in worker memory

#### Acceptance Criteria - Fault Tolerance

76. WHEN worker misses 3 heartbeats THEN Core SHALL mark it as dead
77. WHEN worker is marked dead THEN Core SHALL reassign its tasks
78. WHEN task execution exceeds timeout THEN Core SHALL cancel and retry
79. WHEN task fails 3 times THEN Core SHALL move it to Dead Letter Queue (DLQ)
80. WHEN workflow is in DLQ THEN developer SHALL be able to retry manually

**Timeout Strategy:**
```kotlin
val step = step<Input, Output>(::process) {
    timeout = 30.seconds
    retries = 3
    backoff = exponential(initial = 1.second, max = 10.seconds)
}
```

#### Acceptance Criteria - Multi-Language Interop

81. WHEN workflow uses Kotlin SDK THEN steps CAN call TypeScript workers
82. WHEN step result is serialized THEN any language worker SHALL deserialize correctly
83. WHEN error occurs in Python step THEN Kotlin workflow SHALL handle via diverge
84. WHEN developer mixes languages THEN type safety SHALL be enforced at Blueprint level

**Cross-Language Example:**
```kotlin
// Kotlin workflow definition
val flow = workflow("hybrid-flow") {
    val step1 = step<Input, Middle>(::kotlinFunction)  // Kotlin worker
    val step2 = step<Middle, Output>(::tsFunction)     // TypeScript worker
    timeline { +step1; +step2 }
}
```

#### Acceptance Criteria - Testing

85. WHEN developer writes unit test THEN they SHALL use Local Mode
86. WHEN developer tests step function THEN they SHALL call it directly
87. WHEN developer tests full workflow THEN LocalExecutor SHALL provide instant feedback
88. WHEN developer writes integration test THEN they SHALL use TestWorker with Core
89. WHEN test fails THEN error message SHALL show exact step and input that failed

**Testing Examples:**
```kotlin
// Unit test: Test step function directly
@Test
fun `validateOrder rejects invalid input`() {
    val result = validateOrder(OrderInput(amount = -100))
    assertEquals(ValidationError.NegativeAmount, result)
}

// Integration test: Test full workflow locally
@Test
fun `orderFlow processes valid order`() {
    val executor = LocalExecutor()
    val result = executor.execute(orderFlow, validInput)
    assertTrue(result.isSuccess)
}
```

#### Acceptance Criteria - Observability

90. WHEN workflow executes THEN Core SHALL emit events: StepStarted, StepCompleted, StepFailed
91. WHEN developer queries workflow THEN they SHALL see current state and history
92. WHEN step fails THEN event SHALL include: error message, stack trace, input data
93. WHEN developer uses dashboard THEN they SHALL see: active workflows, queue depth, worker health

---

### Requirement 36: SDK Language Support Roadmap

**User Story:** As Cerebelum maintainer, I want a clear roadmap for SDK language support so that we prioritize based on ecosystem adoption and engineering effort.

#### Acceptance Criteria - Priority 1 Languages (MVP)

1. WHEN Cerebelum v1.0 launches THEN Kotlin SDK SHALL be production-ready
2. WHEN Cerebelum v1.0 launches THEN TypeScript SDK SHALL be production-ready
3. WHEN developer uses Kotlin/TypeScript SDK THEN all features SHALL be supported: timeline, diverge, branch, metadata
4. WHEN developer reports bug in Priority 1 SDK THEN fix SHALL be released within 1 week

**Rationale:**
- Kotlin: Android/JVM ecosystem, strong typing, coroutines
- TypeScript: Web/Node.js ecosystem, largest developer base

#### Acceptance Criteria - Priority 2 Languages (Post-MVP)

5. WHEN Cerebelum v1.1 launches THEN Python SDK SHALL be production-ready
6. WHEN Cerebelum v1.2 launches THEN Go SDK SHALL be production-ready
7. WHEN Priority 2 SDK is released THEN documentation SHALL include migration guide from Priority 1

**Rationale:**
- Python: ML/Data Science ecosystem, simple syntax
- Go: Backend services, performance-critical systems

#### Acceptance Criteria - Priority 3 Languages (Future)

8. WHEN community requests Swift SDK THEN team SHALL evaluate based on: demand, engineering effort, maintainability
9. WHEN Priority 3 SDK is developed THEN it MAY be community-maintained
10. WHEN community contributes SDK THEN it SHALL pass same test suite as official SDKs

**Potential Languages:**
- Swift: iOS ecosystem
- Rust: Systems programming, safety guarantees
- Ruby: Rails ecosystem
- PHP: Web ecosystem
- C#: .NET ecosystem

#### Acceptance Criteria - SDK Feature Parity

11. WHEN new feature is added to Core THEN Priority 1 SDKs SHALL support it within 2 releases
12. WHEN new feature is added to Core THEN Priority 2 SDKs SHALL support it within 4 releases
13. WHEN SDK lacks feature THEN documentation SHALL clearly state limitation

#### Acceptance Criteria - SDK Maintenance

14. WHEN Core releases new version THEN SDK compatibility SHALL be tested automatically
15. WHEN breaking change occurs in Core THEN SDKs SHALL release major version
16. WHEN SDK has security vulnerability THEN patch SHALL be released within 48 hours

#### Acceptance Criteria - Community SDKs

17. WHEN community wants to create SDK THEN template repository SHALL be available
18. WHEN community SDK passes certification THEN it SHALL be listed in official docs
19. WHEN community SDK is abandoned THEN it SHALL be marked as deprecated

**Certification Requirements:**
- Passes standard test suite (100+ tests)
- Documentation with examples
- CI/CD pipeline with automated tests
- Semantic versioning
- Changelog

#### Acceptance Criteria - SDK Generator

20. WHEN new language is prioritized THEN SDK generator SHALL scaffold basic structure
21. WHEN SDK generator runs THEN it SHALL create: project structure, Blueprint serializer, gRPC client, tests
22. WHEN SDK generator completes THEN 70% of SDK SHALL be ready (remaining 30% is language-specific ergonomics)

**Generator Output:**
```
cerebelum-sdk-<lang>/
├── src/
│   ├── workflow/          # Blueprint builder
│   ├── executor/          # Local + Distributed executors
│   ├── grpc/             # Generated gRPC stubs
│   └── serialization/    # JSON + Protobuf
├── tests/
│   ├── unit/
│   └── integration/
├── examples/
│   ├── local-mode.xxx
│   └── distributed-mode.xxx
├── docs/
│   └── README.md
└── build configuration
```

#### Acceptance Criteria - Language-Specific Ergonomics

23. WHEN SDK targets Kotlin THEN it SHALL use: extension functions, sealed classes, coroutines
24. WHEN SDK targets TypeScript THEN it SHALL use: discriminated unions, async/await, generics
25. WHEN SDK targets Python THEN it SHALL use: type hints, dataclasses, context managers
26. WHEN SDK targets Go THEN it SHALL use: interfaces, goroutines, error handling conventions
27. WHEN SDK targets Swift THEN it SHALL use: result builders, async/await, value types
28. WHEN SDK targets Rust THEN it SHALL use: traits, Result<T,E>, zero-cost abstractions

#### Acceptance Criteria - Version Compatibility Matrix

29. WHEN SDK version X is released THEN it SHALL document compatible Core versions
30. WHEN Core version Y is released THEN it SHALL document compatible SDK versions
31. WHEN incompatibility exists THEN error message SHALL guide developer to correct versions

**Compatibility Matrix Example:**
| Core Version | Kotlin SDK | TypeScript SDK | Python SDK | Go SDK |
|--------------|------------|----------------|------------|--------|
| 1.0.x        | 1.0.x      | 1.0.x          | -          | -      |
| 1.1.x        | 1.1.x      | 1.1.x          | 1.0.x      | -      |
| 1.2.x        | 1.2.x      | 1.2.x          | 1.1.x      | 1.0.x  |

#### Acceptance Criteria - Performance Benchmarks

32. WHEN SDK is released THEN benchmark suite SHALL measure: throughput, latency, memory usage
33. WHEN benchmark runs THEN it SHALL compare: Local Mode vs Distributed Mode vs baseline (direct function calls)
34. WHEN performance regresses >10% THEN release SHALL be blocked until fixed

**Benchmark Targets:**
- Local Mode overhead: <5% vs direct function call
- Distributed Mode throughput: >1K workflows/sec per worker
- Memory usage: <50MB per worker (idle)
- Startup time: <2s (worker registration)

---

## Summary

Cerebelum provides **18 comprehensive requirements** for multi-language workflow orchestration:

### Core Orchestration (Requirements 1-34)

1. **Workflow Management** (Req 1, 11, 34) - Definition, execution, graph-based state
2. **Deterministic System** (Req 2, 3, 4, 5) - Time, random, memoization, versioning
3. **Event Sourcing** (Req 6, 7) - Complete history, time travel debugging
4. **Architecture** (Req 8, 9, 10) - Clean Architecture, SOLID, testing
5. **Reliability** (Req 14, 18) - Checkpointing, error handling
6. **Persistence** (Req 16) - Database storage
7. **Performance** (Req 20) - Scalability, concurrency
8. **Developer Experience** (Req 21) - Tooling, setup

**Core Acceptance Criteria:** 128 testable requirements in EARS format

### Multi-Language SDKs (Requirements 35-36)

9. **SDK Support** (Req 35) - Kotlin, TypeScript, Python, Go and more
   - Native syntax per language (Compose-style for Kotlin, Builder for TypeScript, etc.)
   - Dual-mode execution (Local in-process + Distributed via gRPC)
   - Type-safe step references (no strings, IDE autocomplete)
   - Worker architecture with pull-based task distribution
   - Serialization (JSON default + Protobuf opt-in)
   - Fault tolerance (Heartbeat + Timeout + Retry + DLQ)

10. **SDK Roadmap** (Req 36) - Language prioritization and maintenance
    - Priority 1 (MVP): Kotlin, TypeScript
    - Priority 2 (Post-MVP): Python, Go
    - Priority 3 (Future): Swift, Rust, Ruby, PHP, C#
    - SDK generator for 70% automation
    - Community SDK certification program

**SDK Acceptance Criteria:** 127 testable requirements (93 + 34) in EARS format

### Totals

- **Total Requirements:** 18 (16 Core + 2 SDK)
- **Total Acceptance Criteria:** 255 (128 Core + 127 SDK)
- **Architectural Modes:** Code-First (Elixir) + SDK-Based (Multi-Language)
- **Execution Modes:** Local (in-process, dev/test) + Distributed (gRPC, production)

**No AI Dependencies:** This module is pure orchestration. AI features require `cerebelum-ai` module.

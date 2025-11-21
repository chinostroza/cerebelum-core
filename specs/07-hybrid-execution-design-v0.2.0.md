# Design Document - Hybrid Execution: Local + Distributed Steps (v0.2.0)

**Module:** cerebelum-core / python-sdk
**Target Version:** 0.2.0
**Status:** Proposal
**Authors:** Development Team
**Date:** 2025-11-21

## Overview

This document proposes **Hybrid Execution Mode** for Cerebelum workflows, enabling granular control over execution strategy at the **step level** rather than workflow level. This allows mixing local (in-process) and distributed (Core + Workers) execution within a single workflow.

### Current Limitation

Currently, execution mode is decided at the **workflow level**:

```python
# Option A: ALL steps execute locally
result = await workflow.execute(inputs, use_local=True)

# Option B: ALL steps execute distributed
result = await workflow.execute(inputs, use_local=False)
```

### Proposed Enhancement

Enable execution mode configuration at the **step level**:

```python
@step(executor="local")  # Fast validation
async def validate_input(context, inputs):
    return {"valid": True}

@step(executor="distributed")  # Heavy processing
async def transcode_video(context, inputs):
    return {"video_url": "..."}

@workflow
def video_pipeline(wf):
    wf.timeline(
        validate_input >>      # Executes LOCAL
        transcode_video >>     # Executes DISTRIBUTED
        finalize              # Inherits default
    )
```

## Motivation

### Real-World Use Cases

#### 1. **Performance Optimization**
Avoid network latency for lightweight operations:

```python
@workflow
def order_processing(wf):
    wf.timeline(
        validate_order,        # ⚡ LOCAL - 5ms validation
        check_inventory,       # 🌐 DISTRIBUTED - queries shared DB
        calculate_tax,         # ⚡ LOCAL - simple math
        process_payment,       # 🌐 DISTRIBUTED - external API
        finalize_order        # ⚡ LOCAL - write audit log
    )
```

**Without hybrid:** All steps pay network overhead (~50-100ms/step)
**With hybrid:** Only heavy steps use network → **60% latency reduction**

#### 2. **Security & Compliance**
Keep sensitive data local while leveraging distributed compute:

```python
@step(executor="local")  # 🔒 Credentials never leave process
async def authenticate_user(context, inputs):
    api_key = inputs["api_key"]  # Sensitive!
    # Validate locally
    return {"user_id": user_id}

@step(executor="distributed")  # 🌐 Safe to distribute
async def process_transaction(context, authenticate_user):
    user_id = authenticate_user["user_id"]
    # Heavy processing on workers
    return {"status": "completed"}
```

**Benefit:** PCI/HIPAA compliance - sensitive data stays in controlled environment.

#### 3. **Edge Computing + Cloud**
Local preprocessing on edge devices, heavy compute in cloud:

```python
@workflow
def iot_pipeline(wf):
    wf.timeline(
        read_sensor_data,      # 🏠 LOCAL (edge device)
        filter_noise,          # 🏠 LOCAL (edge)
        compress_data,         # 🏠 LOCAL (edge)
        >>
        upload_to_cloud,       # ☁️ DISTRIBUTED (cloud worker)
        run_ml_inference,      # ☁️ DISTRIBUTED (GPU cluster)
        >>
        update_local_cache     # 🏠 LOCAL (edge device)
    )
```

**Benefit:** Bandwidth savings - only send processed data to cloud.

#### 4. **Cost Optimization**
Avoid paying distributed infrastructure for trivial operations:

```python
@workflow
def video_processing(wf):
    wf.timeline(
        validate_input,        # ⚡ LOCAL - free
        extract_metadata,      # ⚡ LOCAL - free
        >>
        [
            generate_thumbnail,  # 🌐 DISTRIBUTED - $0.01/min
            transcode_4k,       # 🌐 DISTRIBUTED - $0.50/min
            extract_subtitles,  # 🌐 DISTRIBUTED - $0.10/min
        ]
        >>
        save_results          # ⚡ LOCAL - free
    )
```

**Benefit:** Pay only for expensive operations.

## Design Options

### Option 1: Decorator-Based Configuration (Recommended)

**Pros:**
- ✅ Clear and explicit
- ✅ Step-level granularity
- ✅ Easy to read and understand
- ✅ No breaking changes (optional parameter)

**Cons:**
- ⚠️ Requires updating all step decorators

```python
@step(executor="local")  # or "distributed" or "auto"
async def my_step(context, inputs):
    return {"result": "..."}
```

**Default behavior:** If not specified, inherit workflow default.

### Option 2: Workflow-Level Strategy Map

**Pros:**
- ✅ Centralized configuration
- ✅ No changes to step definitions
- ✅ Easy to override per environment

**Cons:**
- ⚠️ Less explicit (step definition doesn't show execution mode)
- ⚠️ Potential sync issues between definition and config

```python
@workflow(
    execution_strategy={
        "validate_input": "local",
        "transcode_video": "distributed",
        "default": "local"  # Fallback
    }
)
def my_workflow(wf):
    wf.timeline(...)
```

### Option 3: Composable Sub-Workflows

**Pros:**
- ✅ Maximum flexibility
- ✅ Logical grouping
- ✅ Reusable components

**Cons:**
- ⚠️ More complex API
- ⚠️ Overhead of multiple workflow executions

```python
@workflow(executor="local")
def preprocessing(wf):
    wf.timeline(validate >> clean >> transform)

@workflow(executor="distributed")
def heavy_processing(wf):
    wf.timeline(ml_inference >> video_encode)

@workflow
def main_workflow(wf):
    wf.timeline(
        preprocessing.as_step(),    # Executes LOCAL
        heavy_processing.as_step(), # Executes DISTRIBUTED
        finalize
    )
```

### Recommendation: **Option 1 + Option 2 Hybrid**

Combine both approaches for maximum flexibility:

1. **Default:** Decorator-based (`@step(executor="...")`) - explicit and clear
2. **Override:** Workflow-level strategy map - environment-specific tuning

```python
# Step definition (explicit)
@step(executor="distributed")  # Default in code
async def heavy_step(context, inputs):
    return {"result": "..."}

# Workflow execution (override)
result = await workflow.execute(
    inputs,
    execution_strategy={
        "heavy_step": "local"  # Override for testing
    }
)
```

## Implementation Design

### 1. Step Metadata Extension

Extend `StepMetadata` to include execution preference:

```python
@dataclass
class StepMetadata:
    name: str
    function: StepFunction
    depends_on: List[str]
    executor: str = "auto"  # "local" | "distributed" | "auto"
```

### 2. Executor Routing Logic

Create `HybridExecutor` that routes steps to appropriate executors:

```python
class HybridExecutor:
    def __init__(self, local_executor, distributed_executor, strategy=None):
        self.local_executor = local_executor
        self.distributed_executor = distributed_executor
        self.strategy = strategy or {}

    async def execute_step(self, step_meta, context, inputs):
        # Determine executor
        executor_type = self._resolve_executor(step_meta)

        if executor_type == "local":
            return await self.local_executor.execute_step(
                step_meta, context, inputs
            )
        else:
            return await self.distributed_executor.execute_step(
                step_meta, context, inputs
            )

    def _resolve_executor(self, step_meta):
        # Priority:
        # 1. Runtime strategy override
        if step_meta.name in self.strategy:
            return self.strategy[step_meta.name]

        # 2. Step decorator preference
        if step_meta.executor != "auto":
            return step_meta.executor

        # 3. Default
        return "local"
```

### 3. Core API Changes

#### Step Decorator

```python
def step(
    name: Optional[str] = None,
    executor: str = "auto"  # NEW parameter
) -> Callable:
    """
    Args:
        name: Optional step name
        executor: Execution preference
            - "local": Force local execution
            - "distributed": Force distributed execution
            - "auto": Let workflow decide (default)
    """
    def decorator(func: Callable) -> Callable:
        # Register with executor preference
        StepRegistry.register(
            name=step_name,
            function=wrapped_func,
            executor=executor  # Store preference
        )
        return wrapped_func
    return decorator
```

#### Workflow Execution

```python
async def execute(
    self,
    inputs: Dict[str, Any],
    executor: Optional[Executor] = None,
    use_local: bool = True,  # Backward compatible
    execution_strategy: Optional[Dict[str, str]] = None  # NEW
) -> ExecutionResult:
    """
    Args:
        execution_strategy: Step-level executor overrides
            {"step_name": "local" | "distributed"}
    """
    if execution_strategy:
        # Use HybridExecutor
        executor = HybridExecutor(
            local_executor=DSLLocalExecutor(),
            distributed_executor=DistributedExecutor(core_url),
            strategy=execution_strategy
        )
    elif executor is None:
        # Backward compatible behavior
        if use_local:
            executor = DSLLocalExecutor()
        else:
            executor = DistributedExecutor(core_url)

    return await executor.execute(self._built_definition, inputs)
```

### 4. State Management

**Challenge:** Distributed steps need to access results from local steps and vice versa.

**Solution:** Centralized execution state managed by orchestrator:

```python
class HybridExecutor:
    async def execute(self, workflow, inputs):
        # Centralized state
        execution_state = {"inputs": inputs}

        for step_name in workflow.timeline:
            step_meta = workflow.steps_metadata[step_name]

            # Resolve dependencies from centralized state
            step_inputs = self._resolve_dependencies(
                step_meta, execution_state
            )

            # Execute on appropriate executor
            result = await self.execute_step(
                step_meta, context, step_inputs
            )

            # Store result in centralized state
            execution_state[step_name] = result

        return execution_state
```

## Migration Strategy

### Phase 1: v0.2.0 (Core Implementation)
1. Add `executor` parameter to `@step` decorator
2. Implement `HybridExecutor`
3. Add `execution_strategy` to workflow execution
4. **Backward Compatible:** Existing code works without changes

### Phase 2: v0.2.1 (Optimization)
1. Smart executor selection ("auto" mode with heuristics)
2. Performance metrics collection
3. Cost-based optimization suggestions

### Phase 3: v0.3.0 (Advanced Features)
1. Dynamic executor switching based on load
2. Fallback mechanisms (distributed → local if Core unavailable)
3. Execution visualization showing executor boundaries

## Examples

### Example 1: E-commerce Order Processing

```python
@step(executor="local")  # Fast validation
async def validate_order(context, inputs):
    order = inputs["order"]
    if not order.get("items"):
        raise ValueError("Empty order")
    return order

@step(executor="distributed")  # Query shared inventory DB
async def check_inventory(context, validate_order):
    order = validate_order
    # Heavy DB operation across multiple warehouses
    return {"available": True, "warehouse_id": "WH-001"}

@step(executor="local")  # Simple calculation
async def calculate_tax(context, validate_order):
    order = validate_order
    subtotal = sum(item["price"] for item in order["items"])
    tax = subtotal * 0.1
    return {"tax": tax, "total": subtotal + tax}

@step(executor="distributed")  # External payment API
async def process_payment(context, calculate_tax):
    amount = calculate_tax["total"]
    # Call payment gateway (high latency)
    return {"payment_id": "PAY-XYZ", "status": "success"}

@step(executor="local")  # Local audit log
async def finalize_order(context, process_payment, check_inventory):
    # Write to local audit log (sensitive)
    return {"order_id": "ORD-123", "completed": True}

@workflow
def order_workflow(wf):
    wf.timeline(
        validate_order >>
        [check_inventory, calculate_tax] >>  # Parallel
        process_payment >>
        finalize_order
    )
```

**Execution Flow:**
```
LOCAL:        validate_order (5ms)
               ↓
PARALLEL:     check_inventory (DISTRIBUTED, 200ms)
              calculate_tax (LOCAL, 2ms)
               ↓
DISTRIBUTED:  process_payment (300ms)
               ↓
LOCAL:        finalize_order (3ms)

Total: ~510ms (vs ~1000ms all distributed)
```

### Example 2: Video Processing Pipeline

```python
@step(executor="local")
async def validate_video(context, inputs):
    """Quick metadata check - no need for worker"""
    file_path = inputs["file_path"]
    if not file_path.endswith((".mp4", ".mov")):
        raise ValueError("Invalid format")
    return {"file_path": file_path}

@step(executor="distributed")  # CPU intensive
async def generate_thumbnail(context, validate_video):
    """Requires ffmpeg on worker"""
    return {"thumbnail_url": "s3://..."}

@step(executor="distributed")  # GPU intensive
async def transcode_4k(context, validate_video):
    """Requires GPU worker"""
    return {"video_url": "s3://..."}

@step(executor="local")
async def save_metadata(context, generate_thumbnail, transcode_4k):
    """Write to local DB"""
    return {"saved": True}

@workflow
def video_pipeline(wf):
    wf.timeline(
        validate_video >>
        [generate_thumbnail, transcode_4k] >>  # Parallel on workers
        save_metadata
    )
```

## Performance Considerations

### Latency Analysis

**All Local:**
- Pros: No network overhead
- Cons: Limited by single process, can't scale

**All Distributed:**
- Pros: Scalable, parallel execution
- Cons: Network latency per step (~50-100ms)

**Hybrid:**
- Pros: Best of both worlds
- Cons: Complexity in state management

### Benchmark Estimate (10 steps workflow)

| Configuration | Latency | Scalability |
|---------------|---------|-------------|
| All Local | 50ms | Limited |
| All Distributed | 500ms | High |
| Hybrid (5+5) | 250ms | Medium |
| Hybrid Optimized (8 local + 2 distributed) | 150ms | Good |

## Security Considerations

1. **Data Leakage Prevention**
   - Sensitive steps marked `executor="local"`
   - Audit which data crosses executor boundary

2. **Trust Boundaries**
   - Local executor: Trusted process
   - Distributed executor: Semi-trusted (workers may be on shared infra)

3. **Compliance**
   - PCI-DSS: Payment processing local or on certified workers
   - HIPAA: PHI stays local until anonymized

## Telemetry & Observability

**Critical for hybrid execution:** Need visibility into which steps execute where, latencies, failures, and costs.

### Architecture: Structured Events

Use **OpenTelemetry** standard for compatibility with existing monitoring tools (Datadog, Honeycomb, Grafana, etc.).

#### Python SDK: Event Emission

```python
import time
from opentelemetry import trace, metrics

tracer = trace.get_tracer("cerebelum.workflow")
meter = metrics.get_meter("cerebelum.workflow")

# Metrics
step_duration = meter.create_histogram(
    "cerebelum.step.duration",
    unit="ms",
    description="Step execution duration"
)

step_counter = meter.create_counter(
    "cerebelum.step.executions",
    description="Number of step executions"
)

class HybridExecutor:
    async def execute_step(self, step_meta, context, inputs):
        start_time = time.time()
        executor_type = self._resolve_executor(step_meta)

        # Start span for tracing
        with tracer.start_as_current_span(
            f"step.{step_meta.name}",
            attributes={
                "cerebelum.workflow.id": context.workflow_id,
                "cerebelum.execution.id": context.execution_id,
                "cerebelum.step.name": step_meta.name,
                "cerebelum.executor.type": executor_type,  # "local" | "distributed"
            }
        ) as span:
            try:
                # Execute step
                result = await self._execute_on_executor(
                    step_meta, context, inputs, executor_type
                )

                # Record success
                duration_ms = (time.time() - start_time) * 1000
                step_duration.record(
                    duration_ms,
                    attributes={
                        "step_name": step_meta.name,
                        "executor": executor_type,
                        "status": "success"
                    }
                )
                step_counter.add(1, attributes={
                    "step_name": step_meta.name,
                    "executor": executor_type,
                    "status": "success"
                })

                span.set_attribute("cerebelum.step.status", "success")
                span.set_attribute("cerebelum.step.duration_ms", duration_ms)

                return result

            except Exception as e:
                # Record failure
                duration_ms = (time.time() - start_time) * 1000
                step_duration.record(
                    duration_ms,
                    attributes={
                        "step_name": step_meta.name,
                        "executor": executor_type,
                        "status": "error"
                    }
                )
                step_counter.add(1, attributes={
                    "step_name": step_meta.name,
                    "executor": executor_type,
                    "status": "error",
                    "error_type": type(e).__name__
                })

                span.set_status(trace.Status(trace.StatusCode.ERROR))
                span.record_exception(e)

                raise
```

### Key Metrics

#### 1. **Step Execution Metrics**

| Metric | Type | Labels | Purpose |
|--------|------|--------|---------|
| `cerebelum.step.duration` | Histogram | `step_name`, `executor`, `status` | Latency analysis |
| `cerebelum.step.executions` | Counter | `step_name`, `executor`, `status` | Success/failure rates |
| `cerebelum.step.input_size_bytes` | Histogram | `step_name`, `executor` | Data transfer costs |
| `cerebelum.step.output_size_bytes` | Histogram | `step_name`, `executor` | Data transfer costs |

#### 2. **Executor Metrics**

| Metric | Type | Labels | Purpose |
|--------|------|--------|---------|
| `cerebelum.executor.queue_depth` | Gauge | `executor_type` | Distributed backlog |
| `cerebelum.executor.active_steps` | Gauge | `executor_type` | Concurrency |
| `cerebelum.executor.network_latency_ms` | Histogram | `operation` | gRPC overhead |

#### 3. **Workflow Metrics**

| Metric | Type | Labels | Purpose |
|--------|------|--------|---------|
| `cerebelum.workflow.duration` | Histogram | `workflow_name`, `status` | End-to-end time |
| `cerebelum.workflow.steps_local` | Histogram | `workflow_name` | Local vs distributed ratio |
| `cerebelum.workflow.steps_distributed` | Histogram | `workflow_name` | Local vs distributed ratio |
| `cerebelum.workflow.cost_estimate` | Counter | `workflow_name` | Based on distributed step count |

### Distributed Traces

**Goal:** See full execution path across local and distributed boundaries.

#### Example Trace (Jaeger/Zipkin format):

```
Trace ID: abc123

Span 1: workflow.execute [PARENT]
├─ Span 2: step.validate_order [LOCAL]        50ms
├─ Span 3: step.check_inventory [DISTRIBUTED] 200ms
│  ├─ Span 3.1: grpc.submit                   20ms
│  ├─ Span 3.2: worker.execute               150ms
│  └─ Span 3.3: grpc.poll                     30ms
├─ Span 4: step.calculate_tax [LOCAL]          5ms
└─ Span 5: step.process_payment [DISTRIBUTED] 300ms
   ├─ Span 5.1: grpc.submit                   25ms
   ├─ Span 5.2: worker.execute               250ms
   └─ Span 5.3: grpc.poll                     25ms
```

**Benefits:**
- ✅ See exactly where time is spent
- ✅ Identify slow steps (local or distributed)
- ✅ Debug distributed failures
- ✅ Optimize executor placement decisions

### Logs: Structured JSON

Use structured logging for queryability:

```python
import structlog

logger = structlog.get_logger()

class HybridExecutor:
    async def execute_step(self, step_meta, context, inputs):
        logger.info(
            "step.start",
            execution_id=context.execution_id,
            step_name=step_meta.name,
            executor=executor_type,
            input_size=len(str(inputs))
        )

        # ... execute ...

        logger.info(
            "step.complete",
            execution_id=context.execution_id,
            step_name=step_meta.name,
            executor=executor_type,
            duration_ms=duration_ms,
            output_size=len(str(result))
        )
```

**Example log output:**
```json
{
  "event": "step.start",
  "timestamp": "2025-11-21T14:30:00.123Z",
  "execution_id": "abc-123",
  "workflow_id": "order_processing",
  "step_name": "check_inventory",
  "executor": "distributed",
  "input_size": 256
}

{
  "event": "step.complete",
  "timestamp": "2025-11-21T14:30:00.323Z",
  "execution_id": "abc-123",
  "workflow_id": "order_processing",
  "step_name": "check_inventory",
  "executor": "distributed",
  "duration_ms": 200,
  "output_size": 128,
  "status": "success"
}
```

### Dashboard Visualization

#### Grafana Dashboard Example

**Panel 1: Execution Mode Distribution**
```
Pie chart: % steps local vs distributed
- Query: sum(cerebelum_step_executions) by (executor)
```

**Panel 2: Step Latency by Executor**
```
Histogram: Compare local vs distributed latencies
- Query: histogram_quantile(0.95, cerebelum_step_duration_bucket)
  by (executor)
```

**Panel 3: Workflow Timeline**
```
Gantt chart: Show step execution timeline
- Shows parallel execution
- Color-coded by executor (green=local, blue=distributed)
```

**Panel 4: Cost Estimation**
```
Counter: Estimated cost based on distributed steps
- Query: sum(cerebelum_workflow_cost_estimate)
- Alert if cost > threshold
```

**Panel 5: Error Rate**
```
Graph: Error rate per executor type
- Query: rate(cerebelum_step_executions{status="error"}) by (executor)
```

### Core (Elixir) Telemetry Extension

Extend existing Core telemetry to track hybrid execution:

```elixir
# In Cerebelum.Execution.Engine
def handle_cast({:execute_step, step_name}, state) do
  start_time = System.monotonic_time()

  # Detect if step is being executed by local SDK or worker
  executor_type = detect_executor_type(step_name, state)

  result = execute_step_logic(step_name, state)

  duration = System.monotonic_time() - start_time

  :telemetry.execute(
    [:cerebelum, :step, :execute],
    %{duration: duration},
    %{
      workflow_id: state.workflow_id,
      step_name: step_name,
      executor_type: executor_type,  # :local or :distributed
      status: elem(result, 0)
    }
  )

  # ... handle result ...
end
```

### Integration: Python SDK → Core Telemetry

**Challenge:** Python SDK local execution doesn't touch Core - no automatic telemetry.

**Solution 1: Optional Telemetry Sink**

```python
@workflow
def my_workflow(wf):
    wf.timeline(...)

# Enable telemetry export to Core
result = await my_workflow.execute(
    inputs,
    telemetry_sink="http://core:9090/telemetry"  # Optional
)
```

SDK sends batch telemetry events to Core after execution:

```python
POST /api/v1/telemetry/batch
{
  "execution_id": "abc-123",
  "events": [
    {"type": "step.start", "step": "validate", "executor": "local", "ts": "..."},
    {"type": "step.end", "step": "validate", "executor": "local", "duration_ms": 5},
    ...
  ]
}
```

**Solution 2: Local OTLP Exporter**

Use OpenTelemetry's standard OTLP protocol:

```python
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Configure exporter
exporter = OTLPSpanExporter(endpoint="localhost:4317")  # OTLP gRPC
provider = TracerProvider()
provider.add_span_processor(BatchSpanProcessor(exporter))

# Now all traces automatically go to Core/Collector
```

**Benefits:**
- ✅ Standard protocol
- ✅ Works with any OTLP collector (Core, Jaeger, Tempo)
- ✅ No custom integration needed

### Alerts & SLOs

#### Critical Alerts

1. **High Distributed Failure Rate**
   ```
   Alert: distributed_step_error_rate > 5%
   Action: Fallback to local or page on-call
   ```

2. **Excessive Latency**
   ```
   Alert: p95(step_duration{executor="distributed"}) > 1000ms
   Action: Scale workers or optimize steps
   ```

3. **Cost Threshold**
   ```
   Alert: workflow_cost_estimate > $10/hour
   Action: Review executor placement
   ```

#### SLO Examples

| SLO | Target | Measurement |
|-----|--------|-------------|
| Workflow P95 latency | < 500ms | `histogram_quantile(0.95, workflow_duration)` |
| Step success rate | > 99.9% | `sum(executions{status="success"}) / sum(executions)` |
| Local execution ratio | > 70% | For cost optimization |

### Developer Experience: CLI Telemetry

```bash
# Real-time telemetry during development
$ cerebelum dev --telemetry

Executing workflow: order_processing
  ✓ validate_order [LOCAL] 5ms
  ⏳ check_inventory [DISTRIBUTED] ...
  ✓ check_inventory [DISTRIBUTED] 203ms
  ✓ calculate_tax [LOCAL] 2ms
  ⏳ process_payment [DISTRIBUTED] ...
  ✓ process_payment [DISTRIBUTED] 315ms

Summary:
  Total: 525ms
  Local steps: 2 (7ms, 1.3%)
  Distributed steps: 2 (518ms, 98.7%)
  Cost estimate: $0.0012

💡 TIP: Consider moving calculate_tax to distributed for consistency
```

### Privacy & Compliance

**Sensitive Data in Telemetry:**

```python
# DON'T: Log sensitive data
logger.info("step.complete", credit_card=inputs["cc"])  # ❌

# DO: Hash or omit
logger.info(
    "step.complete",
    step_name="process_payment",
    input_hash=sha256(inputs["cc"])[:8],  # First 8 chars of hash
    input_size=len(str(inputs))
)
```

**PII Redaction:**
- Credit cards → `****1234`
- Emails → `u***@e***.com`
- API keys → `sk_***xyz`

### Implementation Phases

#### Phase 1 (v0.2.0): Basic Metrics
- Step duration, count, status
- Local vs distributed ratio
- Simple structured logs

#### Phase 2 (v0.2.1): Distributed Tracing
- OpenTelemetry integration
- Jaeger/Zipkin export
- Correlation across executor boundaries

#### Phase 3 (v0.3.0): Advanced Analytics
- Cost estimation
- Automatic optimization suggestions
- Anomaly detection (ML-based)

## Future Enhancements

### v0.3.0: Smart Executor Selection

```python
@step(executor="auto")  # Let Cerebelum decide
async def flexible_step(context, inputs):
    return {"result": "..."}

# Cerebelum analyzes:
# - Step execution time history
# - Current Core load
# - Network latency
# - Cost constraints
# → Chooses optimal executor
```

### v0.4.0: Executor Pools

```python
@step(executor="gpu-worker-pool")
async def ml_inference(context, inputs):
    # Routes to specialized GPU workers
    return {"prediction": "..."}

@step(executor="local-cpu-intensive")
async def data_processing(context, inputs):
    # Uses local process but dedicated CPU pool
    return {"processed": "..."}
```

## Open Questions

1. **State Serialization:** How to efficiently pass large results between local and distributed executors?
   - Option A: Always serialize (safe, slow)
   - Option B: Use shared storage (S3/Redis) for large objects
   - Option C: Memory-map for local→local (fast but complex)

2. **Failure Handling:** What happens if distributed step fails but local steps succeeded?
   - Should we rollback local side effects?
   - How to maintain consistency?

3. **Observability:** How to visualize hybrid execution in monitoring tools?
   - Different colors for local vs distributed steps?
   - Latency breakdown per executor type?

## References

- [01-requirements.md](./01-requirements.md) - Core requirements
- [02-design.md](./02-design.md) - System architecture
- [Python SDK DSL v1.2](../examples/python-sdk/CHANGELOG.md) - Current implementation

## Appendix A: API Reference

### Step Decorator

```python
@step(
    name: Optional[str] = None,
    executor: Literal["local", "distributed", "auto"] = "auto"
)
```

### Workflow Execute

```python
await workflow.execute(
    inputs: Dict[str, Any],
    executor: Optional[Executor] = None,
    use_local: bool = True,  # Deprecated in favor of execution_strategy
    execution_strategy: Optional[Dict[str, str]] = None
) -> ExecutionResult
```

### Execution Strategy Format

```python
execution_strategy = {
    "step_name": "local" | "distributed",
    "another_step": "local",
    "default": "distributed"  # Optional fallback
}
```

## Appendix B: Migration Checklist

- [ ] Update `StepMetadata` dataclass
- [ ] Implement `HybridExecutor` class
- [ ] Add `executor` parameter to `@step` decorator
- [ ] Add `execution_strategy` to workflow execution
- [ ] Update DSL documentation
- [ ] Add tutorial examples
- [ ] Performance benchmarks
- [ ] Security audit
- [ ] User acceptance testing

---

**Status:** This is a proposal document. Feedback and discussion welcome before implementation begins.

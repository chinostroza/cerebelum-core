# Cerebelum Python SDK - DSL Documentation

Comprehensive documentation for the Cerebelum Python Workflow DSL - a declarative syntax for building distributed workflows.

## 📚 Table of Contents

### Core Concepts
1. [**DSL Syntax Guide**](./dsl-syntax.md) - Complete DSL syntax reference
2. [**Workflow Patterns**](./workflow-patterns.md) - Common workflow patterns
3. [**Step Functions**](./step-functions.md) - Writing step functions
4. [**Control Flow**](./control-flow.md) - Timeline, Diverge, Branch

### Advanced Topics
5. [**Automatic Parallelism**](./parallelism.md) - Dependency-based parallel execution
6. [**Data Flow**](./data-flow.md) - How data flows between steps
7. [**Error Handling**](./error-handling.md) - Handling errors and retries

### Examples
8. [**Examples Directory**](./examples/README.md) - Complete workflow examples
   - Order Processing Workflow
   - User Onboarding Workflow
   - AI Agent Workflow

## 🎯 Quick Start Guide

Cerebelum Python DSL allows you to define workflows using:
- **`@workflow`** decorator for workflow definitions
- **`@step`** decorator for step functions
- **`>>`** operator for sequential composition
- **Automatic parallelism** based on dependencies

### Simple Example

```python
from cerebelum import workflow, step

@step
async def fetch_user(context, inputs):
    user_id = inputs["user_id"]
    return {"ok": {"id": user_id, "name": "John"}}

@step
async def send_email(context, fetch_user):
    user = fetch_user
    return {"ok": f"Email sent to {user['name']}"}

@workflow
def user_onboarding(wf):
    """Simple linear workflow"""
    wf.timeline(
        fetch_user >> send_email
    )
```

## 🔑 Key Concepts

### 1. Step Functions

Steps are async functions decorated with `@step`. They receive:
- `context`: Workflow execution context
- `inputs`: Initial workflow inputs (for first step)
- Previous step results as named parameters

```python
@step
async def my_step(context, previous_step_name):
    # Access result from previous_step_name
    data = previous_step_name

    # Do async work
    result = await some_async_operation(data)

    # Return with status
    return {"ok": result}  # or {"error": "message"}
```

### 2. Workflow Definition

Workflows are functions decorated with `@workflow` that receive a workflow builder (`wf`):

```python
@workflow
def my_workflow(wf):
    # Define timeline (sequential flow)
    wf.timeline(step1 >> step2 >> step3)

    # Define diverge (pattern matching)
    wf.diverge(from_step=step1, patterns={
        "timeout": retry_step,
        "error": error_handler
    })

    # Define branch (conditional)
    wf.branch(
        after=step2,
        on=lambda result: result["score"] > 0.8,
        when_true=high_priority_path,
        when_false=low_priority_path
    )
```

### 3. Control Flow Constructs

| Construct | Purpose | Syntax |
|-----------|---------|--------|
| **timeline** | Sequential execution | `wf.timeline(step1 >> step2 >> step3)` |
| **diverge** | Pattern matching on result | `wf.diverge(from_step=step1, patterns={...})` |
| **branch** | Conditional routing | `wf.branch(after=step2, on=lambda x: x > 10, ...)` |
| **parallel** | Automatic (same dependencies) | No syntax needed - automatic |

### 4. Automatic Parallelism

Steps with the **same dependencies** execute in parallel automatically:

```python
@step
async def send_email(context, order):
    return {"ok": "email_sent"}

@step
async def send_sms(context, order):
    return {"ok": "sms_sent"}

@step
async def update_inventory(context, order):
    return {"ok": "inventory_updated"}

# All 3 steps above have the SAME dependency (order)
# → They execute in PARALLEL automatically
```

## 🚀 Syntax Comparison with Elixir

### Elixir (Native)
```elixir
workflow do
  timeline do
    validate() |> process() |> notify()
  end

  diverge from: validate() do
    :timeout -> retry()
    {:error, _} -> fail()
  end

  branch after: process(), on: result do
    result > 0.8 -> high_priority()
    true -> low_priority()
  end
end
```

### Python (DSL)
```python
@workflow
def my_workflow(wf):
    wf.timeline(
        validate >> process >> notify
    )

    wf.diverge(from_step=validate, patterns={
        "timeout": retry,
        "error": fail
    })

    wf.branch(
        after=process,
        on=lambda r: r > 0.8,
        when_true=high_priority,
        when_false=low_priority
    )
```

## 📊 How It Works

```
User Code (Python DSL)
         ↓
SDK parses @workflow and @step decorators
         ↓
Builds WorkflowDefinition protobuf
         ↓
Sends to Cerebelum Core (Elixir) via gRPC
         ↓
Core orchestrates execution using BEAM processes
         ↓
Calls back to Python worker for step execution
         ↓
Results returned to Core for state management
```

## 🔧 Design Principles

1. **Declarative**: Describe WHAT to do, not HOW
2. **Type-Safe**: Python type hints for better IDE support
3. **Async-First**: All steps are async functions
4. **Functional**: Steps are pure functions (no side effects in workflow definition)
5. **Dependency-Driven**: Parallelism inferred from function signatures
6. **Similar to Elixir**: Consistent experience across languages

## 📖 Reading Guide

**For Python Developers:**
1. Start with [DSL Syntax Guide](./dsl-syntax.md)
2. Read [Step Functions](./step-functions.md)
3. Review [Examples](./examples/README.md)

**For Elixir Developers:**
1. Start with [DSL Syntax Guide](./dsl-syntax.md) to see Python equivalents
2. Review [Data Flow](./data-flow.md) to understand worker communication
3. Check [Examples](./examples/README.md)

**For System Architects:**
1. Read [Workflow Patterns](./workflow-patterns.md)
2. Study [Automatic Parallelism](./parallelism.md)
3. Review [Control Flow](./control-flow.md)

## 🎓 Next Steps

- [DSL Syntax Guide](./dsl-syntax.md) - Learn the complete syntax
- [Examples](./examples/README.md) - See real-world workflows
- [API Reference](./api-reference.md) - Complete API documentation

---

**Version:** 1.0
**Last Updated:** 2025-01-20
**Maintainer:** Cerebelum Team

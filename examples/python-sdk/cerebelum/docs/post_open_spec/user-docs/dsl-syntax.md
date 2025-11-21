# DSL Syntax Guide

Complete reference for the Cerebelum Python Workflow DSL syntax.

## Table of Contents

1. [Decorators](#decorators)
2. [Step Functions](#step-functions)
3. [Workflow Functions](#workflow-functions)
4. [Control Flow](#control-flow)
5. [Operators](#operators)
6. [Type System](#type-system)
7. [Complete Examples](#complete-examples)

---

## Decorators

### `@step`

Marks a function as a workflow step. The function must be async and return a result dictionary.

**Syntax:**
```python
@step
async def step_name(context, ...dependencies) -> dict:
    # Step logic here
    return {"ok": result}  # or {"error": "message"}
```

**Parameters:**
- Always receives `context` as first parameter
- Receives results from previous steps as named parameters
- Parameter names must match step function names

**Return Value:**
```python
# Success
{"ok": data}

# Error
{"error": "error_message"}
```

**Example:**
```python
@step
async def fetch_user(context, inputs):
    """First step - receives inputs"""
    user_id = inputs["user_id"]
    user = await db.get_user(user_id)
    return {"ok": user}

@step
async def validate_user(context, fetch_user):
    """Receives result from fetch_user"""
    user = fetch_user  # Unwrapped automatically

    if user["age"] < 18:
        return {"error": "user_too_young"}

    return {"ok": {**user, "validated": True}}
```

---

### `@workflow`

Marks a function as a workflow definition. The function receives a workflow builder object.

**Syntax:**
```python
@workflow
def workflow_name(wf):
    # Define workflow structure
    wf.timeline(...)
    wf.diverge(...)
    wf.branch(...)
```

**Parameter:**
- `wf`: Workflow builder object with methods:
  - `wf.timeline(composition)` - Define sequential flow
  - `wf.diverge(from_step, patterns)` - Define pattern matching
  - `wf.branch(after, on, when_true, when_false)` - Define conditional

**Example:**
```python
@workflow
def user_onboarding(wf):
    """User onboarding workflow"""

    wf.timeline(
        fetch_user >> validate_user >> send_welcome_email
    )

    wf.diverge(from_step=validate_user, patterns={
        "user_too_young": send_rejection_email,
        "invalid_data": request_data_correction
    })
```

---

## Step Functions

### Function Signature

Step functions follow this pattern:

```python
@step
async def step_name(
    context: Context,           # Always first
    inputs: dict = None,        # For first step only
    previous_step: Any = None,  # Results from dependencies
    another_step: Any = None    # More dependencies
) -> dict:
    """
    Step description

    Dependencies: previous_step, another_step
    Returns: {"ok": result} or {"error": message}
    """
    pass
```

### Context Object

The `context` parameter provides access to workflow execution information:

```python
@step
async def my_step(context, inputs):
    # Access workflow inputs
    user_id = context.inputs["user_id"]

    # Access execution metadata
    execution_id = context.execution_id
    workflow_name = context.workflow_name

    # Access step metadata
    step_name = context.step_name
    attempt = context.attempt  # For retries

    return {"ok": "processed"}
```

### Dependency Resolution

Dependencies are resolved by **parameter names**:

```python
@step
async def step_a(context, inputs):
    return {"ok": "result_a"}

@step
async def step_b(context, inputs):
    return {"ok": "result_b"}

@step
async def step_c(context, step_a, step_b):
    # step_a contains result from step_a
    # step_b contains result from step_b
    # Both are unwrapped (just the data, not {"ok": ...})

    combined = {
        "from_a": step_a,
        "from_b": step_b
    }
    return {"ok": combined}
```

### Optional Dependencies

Use `None` as default for optional dependencies:

```python
@step
async def notification(context, email_step=None, sms_step=None):
    """
    This step can run after either email_step OR sms_step
    or both, depending on which path was taken
    """

    if email_step:
        print(f"Email was sent: {email_step}")

    if sms_step:
        print(f"SMS was sent: {sms_step}")

    return {"ok": "notification_logged"}
```

---

## Workflow Functions

### `wf.timeline()`

Defines the main sequential execution path using the `>>` operator.

**Syntax:**
```python
wf.timeline(step1 >> step2 >> step3)
```

**Rules:**
- Steps execute in order from left to right
- Each step waits for the previous to complete
- Can chain any number of steps

**Example:**
```python
@workflow
def linear_workflow(wf):
    wf.timeline(
        fetch_data >>
        process_data >>
        validate_data >>
        save_data
    )
```

---

### `wf.diverge()`

Defines pattern matching on a step's result. Routes execution based on result status.

**Syntax:**
```python
wf.diverge(
    from_step=source_step,
    patterns={
        "pattern1": handler_step1,
        "pattern2": handler_step2,
        # ... more patterns
    }
)
```

**Parameters:**
- `from_step`: The step to match against (function reference, not string)
- `patterns`: Dictionary mapping result patterns to handler steps

**Pattern Matching:**
```python
# When source_step returns {"ok": "timeout"}
# Matches pattern "timeout"

# When source_step returns {"error": "invalid_data"}
# Matches pattern "invalid_data"

# When source_step returns {"ok": {...}}
# Matches pattern "ok" (if defined)
```

**Example:**
```python
@step
async def validate_order(context, inputs):
    order_id = inputs["order_id"]

    if order_id % 10 == 0:
        return {"ok": "timeout"}
    elif order_id % 3 == 0:
        return {"error": "payment_failed"}
    else:
        return {"ok": {"order_id": order_id, "status": "valid"}}

@step
async def retry_validation(context, validate_order):
    # Handle timeout
    return {"ok": "retried"}

@step
async def handle_payment_failure(context, validate_order):
    # Handle payment failure
    return {"ok": "payment_issue_logged"}

@step
async def process_order(context, validate_order):
    # Handle success case
    order = validate_order
    return {"ok": f"processing {order['order_id']}"}

@workflow
def order_workflow(wf):
    wf.timeline(
        validate_order >> process_order
    )

    # Pattern matching on validate_order result
    wf.diverge(from_step=validate_order, patterns={
        "timeout": retry_validation >> process_order,
        "payment_failed": handle_payment_failure
        # "ok" path is handled by main timeline
    })
```

---

### `wf.branch()`

Defines conditional routing based on a predicate function.

**Syntax:**
```python
wf.branch(
    after=source_step,
    on=lambda result: condition,
    when_true=true_path_step,
    when_false=false_path_step
)
```

**Parameters:**
- `after`: Step to evaluate (function reference)
- `on`: Predicate function that receives step result and returns boolean
- `when_true`: Step to execute if predicate returns True
- `when_false`: Step to execute if predicate returns False

**Example:**
```python
@step
async def calculate_score(context, user):
    score = user["points"] / user["total_possible"]
    return {"ok": {"user": user, "score": score}}

@step
async def high_priority_path(context, calculate_score):
    result = calculate_score
    return {"ok": f"High priority: {result['score']}"}

@step
async def low_priority_path(context, calculate_score):
    result = calculate_score
    return {"ok": f"Low priority: {result['score']}"}

@workflow
def scoring_workflow(wf):
    wf.timeline(
        fetch_user >> calculate_score
    )

    wf.branch(
        after=calculate_score,
        on=lambda result: result["score"] > 0.8,
        when_true=high_priority_path,
        when_false=low_priority_path
    )
```

---

## Operators

### `>>` (Sequential Composition)

Chains steps together for sequential execution.

**Syntax:**
```python
step1 >> step2 >> step3
```

**Semantics:**
- `step2` executes after `step1` completes
- `step3` executes after `step2` completes
- Data flows left to right

**Usage:**
```python
# In timeline
wf.timeline(a >> b >> c)

# In diverge patterns
wf.diverge(from_step=x, patterns={
    "retry": retry_step >> b >> c,
    "error": error_handler
})

# NOT used for branching or parallel
# (those use wf.branch() and automatic parallelism)
```

---

## Type System

### Return Types

All steps must return a dictionary with either `"ok"` or `"error"` key:

```python
# Success - value can be any JSON-serializable type
return {"ok": value}

# Examples:
return {"ok": None}
return {"ok": 42}
return {"ok": "success"}
return {"ok": [1, 2, 3]}
return {"ok": {"user_id": 123, "name": "John"}}

# Error - message should be a string
return {"error": "error_message"}

# Examples:
return {"error": "user_not_found"}
return {"error": "invalid_input"}
return {"error": "timeout_exceeded"}
```

### Type Hints (Recommended)

Use Python type hints for better IDE support:

```python
from typing import Dict, Any
from cerebelum import step, Context

@step
async def typed_step(
    context: Context,
    inputs: Dict[str, Any]
) -> Dict[str, Any]:
    user_id: int = inputs["user_id"]
    user: Dict[str, Any] = await fetch_user_from_db(user_id)

    return {"ok": user}
```

---

## Complete Examples

### Example 1: Linear Workflow

```python
from cerebelum import workflow, step

@step
async def fetch_data(context, inputs):
    data_id = inputs["id"]
    data = await fetch_from_api(data_id)
    return {"ok": data}

@step
async def transform_data(context, fetch_data):
    data = fetch_data
    transformed = {k.upper(): v for k, v in data.items()}
    return {"ok": transformed}

@step
async def save_data(context, transform_data):
    data = transform_data
    await save_to_db(data)
    return {"ok": "saved"}

@workflow
def etl_workflow(wf):
    """Simple ETL pipeline"""
    wf.timeline(
        fetch_data >> transform_data >> save_data
    )
```

### Example 2: Workflow with Diverge

```python
@step
async def validate_input(context, inputs):
    value = inputs["value"]

    if value < 0:
        return {"error": "negative_value"}
    elif value > 100:
        return {"error": "value_too_large"}
    else:
        return {"ok": value}

@step
async def handle_negative(context, validate_input):
    return {"ok": "used_default_0"}

@step
async def handle_too_large(context, validate_input):
    return {"ok": "clamped_to_100"}

@step
async def process_value(context, validate_input):
    value = validate_input
    result = value * 2
    return {"ok": result}

@workflow
def validation_workflow(wf):
    wf.timeline(
        validate_input >> process_value
    )

    wf.diverge(from_step=validate_input, patterns={
        "negative_value": handle_negative >> process_value,
        "value_too_large": handle_too_large >> process_value
    })
```

### Example 3: Workflow with Branch

```python
@step
async def check_user_type(context, inputs):
    user_type = inputs["user_type"]
    return {"ok": user_type}

@step
async def premium_flow(context, check_user_type):
    return {"ok": "premium_processing"}

@step
async def standard_flow(context, check_user_type):
    return {"ok": "standard_processing"}

@workflow
def user_type_workflow(wf):
    wf.timeline(check_user_type)

    wf.branch(
        after=check_user_type,
        on=lambda user_type: user_type == "premium",
        when_true=premium_flow,
        when_false=standard_flow
    )
```

### Example 4: Automatic Parallel Execution

```python
@step
async def fetch_order(context, inputs):
    order_id = inputs["order_id"]
    return {"ok": {"order_id": order_id, "total": 100}}

@step
async def send_email(context, fetch_order):
    """Parallel step 1"""
    order = fetch_order
    await send_email_notification(order)
    return {"ok": "email_sent"}

@step
async def send_sms(context, fetch_order):
    """Parallel step 2 - same dependency as send_email"""
    order = fetch_order
    await send_sms_notification(order)
    return {"ok": "sms_sent"}

@step
async def update_inventory(context, fetch_order):
    """Parallel step 3 - same dependency as send_email and send_sms"""
    order = fetch_order
    await update_inventory_system(order)
    return {"ok": "inventory_updated"}

@step
async def finalize(context, send_email, send_sms, update_inventory):
    """Waits for all 3 parallel steps to complete"""
    return {"ok": "all_done"}

@workflow
def notification_workflow(wf):
    """
    Execution flow:

    fetch_order
         ↓
    ┌────┼────┬──────────────┐
    │    │    │              │
    email sms inventory    (parallel - same dependency)
    │    │    │
    └────┼────┴──────────────┘
         ↓
    finalize (waits for all)
    """
    wf.timeline(fetch_order)

    # No need to declare parallel execution
    # send_email, send_sms, update_inventory all depend on fetch_order
    # → They execute in parallel automatically

    # finalize depends on all three
    # → Waits for all to complete before executing
```

### Example 5: Complex Workflow

```python
@step
async def validate_order(context, inputs):
    order_id = inputs["order_id"]

    if order_id % 10 == 0:
        return {"ok": "timeout"}
    elif order_id % 3 == 0:
        return {"error": "payment_failed"}
    else:
        return {"ok": {"order_id": order_id, "amount": order_id * 10}}

@step
async def retry_validation(context, validate_order):
    return {"ok": {"order_id": 999, "amount": 500}}

@step
async def handle_payment_failure(context, validate_order):
    return {"ok": "payment_failure_logged"}

@step
async def calculate_priority(context, validate_order):
    order = validate_order
    score = 0.9 if order["amount"] > 800 else 0.5
    return {"ok": {**order, "priority_score": score}}

@step
async def high_priority_processing(context, calculate_priority):
    return {"ok": "expedited"}

@step
async def low_priority_processing(context, calculate_priority):
    return {"ok": "standard"}

@step
async def send_confirmation(context, high_priority_processing, low_priority_processing):
    """Executes after either high or low priority path"""
    return {"ok": "confirmation_sent"}

@workflow
def complex_order_workflow(wf):
    """
    Complete order processing with:
    - Validation with retry
    - Error handling
    - Priority-based routing
    - Final confirmation
    """

    # Main timeline
    wf.timeline(
        validate_order >> calculate_priority
    )

    # Handle validation errors
    wf.diverge(from_step=validate_order, patterns={
        "timeout": retry_validation >> calculate_priority,
        "payment_failed": handle_payment_failure
    })

    # Route based on priority
    wf.branch(
        after=calculate_priority,
        on=lambda order: order["priority_score"] > 0.8,
        when_true=high_priority_processing,
        when_false=low_priority_processing
    )

    # send_confirmation depends on both paths
    # → Executes after whichever path was taken
```

---

## Summary

**Core Syntax:**
- `@step` - Decorator for step functions
- `@workflow` - Decorator for workflow functions
- `>>` - Sequential composition operator
- `wf.timeline()` - Define main execution path
- `wf.diverge()` - Pattern matching on results
- `wf.branch()` - Conditional routing

**Key Principles:**
1. Steps are async functions that return `{"ok": ...}` or `{"error": ...}`
2. Dependencies are resolved by parameter names
3. Parallelism is automatic based on shared dependencies
4. Control flow is declarative and separate from step logic

---

**Next:** [Workflow Patterns](./workflow-patterns.md) | [Step Functions Deep Dive](./step-functions.md)

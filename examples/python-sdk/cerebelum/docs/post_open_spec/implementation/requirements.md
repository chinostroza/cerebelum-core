# Requirements Document - Cerebelum Python DSL

## Introduction

This document specifies the requirements for implementing a new declarative DSL (Domain-Specific Language) for the Cerebelum Python SDK. The DSL SHALL enable developers to define workflows using a syntax similar to Elixir's native DSL, while maintaining Python idioms and async patterns.

### Scope

The implementation SHALL cover:
- Decorators for workflow and step definition (`@workflow`, `@step`)
- Sequential composition operator (`>>`)
- Workflow builder with control flow methods (`timeline`, `diverge`, `branch`)
- Automatic parallelism based on dependency analysis
- Data flow between steps via parameter names
- Integration with existing gRPC-based Cerebelum Core

### Out of Scope

- Changes to Cerebelum Core (Elixir)
- Changes to protobuf definitions
- Backward compatibility with old builder API (breaking change accepted)

---

## Requirements

### Requirement 1: Step Decorator

**User Story:** As a developer, I want to define workflow steps using a `@step` decorator so that I can mark async functions as executable workflow units.

#### Acceptance Criteria

1. WHEN developer decorates an async function with `@step` THEN the function SHALL be registered as a workflow step
2. IF decorated function is not async THEN system SHALL raise `TypeError` with message "Step functions must be async"
3. WHEN step executes THEN it SHALL receive `context` as first parameter
4. WHEN step has dependencies THEN it SHALL receive previous step results as named parameters
5. WHERE step is first in timeline THEN it SHALL receive `inputs` parameter containing workflow input data
6. WHEN step completes THEN it SHALL return dictionary with `"ok"` or `"error"` key
7. IF return value is not a dict with `"ok"` or `"error"` THEN system SHALL raise `ValueError`

**Example:**
```python
@step
async def my_step(context, inputs):
    """First step receives inputs"""
    result = await process(inputs["data"])
    return {"ok": result}  # Must return {"ok": ...} or {"error": ...}
```

---

### Requirement 2: Workflow Decorator

**User Story:** As a developer, I want to define workflows using a `@workflow` decorator so that I can compose steps into executable workflows.

#### Acceptance Criteria

1. WHEN developer decorates a function with `@workflow` THEN the function SHALL be registered as a workflow definition
2. WHEN workflow function executes THEN it SHALL receive workflow builder object as parameter
3. WHEN workflow is called with `.execute(inputs)` THEN it SHALL trigger workflow execution via gRPC
4. IF workflow function is async THEN system SHALL raise `TypeError` with message "Workflow functions must not be async"
5. WHEN workflow definition completes THEN all control flow SHALL be captured in WorkflowDefinition protobuf

**Example:**
```python
@workflow
def my_workflow(wf):
    """Workflow definition receives builder"""
    wf.timeline(step1 >> step2)
```

---

### Requirement 3: Sequential Composition Operator

**User Story:** As a developer, I want to use the `>>` operator to chain steps so that I can express sequential execution clearly.

#### Acceptance Criteria

1. WHEN steps are composed with `>>` operator THEN system SHALL execute them left-to-right
2. WHEN `step1 >> step2` is evaluated THEN system SHALL create composition object
3. WHERE composition is used in `timeline()` THEN steps SHALL execute in sequence
4. WHERE composition is used in `diverge()` patterns THEN steps SHALL execute in sequence after pattern match
5. IF non-step object is used with `>>` THEN system SHALL raise `TypeError`

**Example:**
```python
wf.timeline(fetch >> validate >> process >> save)  # Left-to-right execution
```

---

### Requirement 4: Timeline Declaration

**User Story:** As a developer, I want to declare the main execution path using `wf.timeline()` so that I can define the primary workflow sequence.

#### Acceptance Criteria

1. WHEN `wf.timeline(composition)` is called THEN system SHALL register composition as main execution path
2. WHEN timeline contains `step1 >> step2 >> step3` THEN execution SHALL be `step1` → `step2` → `step3`
3. IF timeline is called multiple times THEN system SHALL raise `ValueError` with message "timeline() can only be called once"
4. WHEN timeline is not called THEN workflow SHALL have empty main path (valid for diverge-only workflows)
5. WHERE step in timeline has no dependencies THEN it executes immediately

**Example:**
```python
@workflow
def my_workflow(wf):
    wf.timeline(step_a >> step_b >> step_c)
```

---

### Requirement 5: Diverge (Pattern Matching)

**User Story:** As a developer, I want to use `wf.diverge()` to route execution based on step results so that I can handle different outcomes.

#### Acceptance Criteria

1. WHEN `wf.diverge(from_step=X, patterns={...})` is called THEN system SHALL register pattern matching on step X
2. WHEN step X returns `{"ok": "pattern1"}` THEN system SHALL execute handler for `"pattern1"`
3. WHEN step X returns `{"error": "pattern2"}` THEN system SHALL execute handler for `"pattern2"`
4. IF result does not match any pattern THEN system SHALL use default behavior (continue main timeline)
5. WHERE pattern value is a step THEN that single step SHALL execute
6. WHERE pattern value is composition (`a >> b`) THEN entire composition SHALL execute
7. IF `from_step` is not a valid step function THEN system SHALL raise `ValueError`
8. WHEN multiple diverges target same step THEN system SHALL raise `ValueError`

**Example:**
```python
wf.diverge(from_step=validate, patterns={
    "timeout": retry_step >> validate,  # Composition allowed
    "error": error_handler,              # Single step allowed
    "ok": process_step                   # Match on success
})
```

---

### Requirement 6: Branch (Conditional Routing)

**User Story:** As a developer, I want to use `wf.branch()` to route based on conditions so that I can implement if/else logic.

#### Acceptance Criteria

1. WHEN `wf.branch(after=X, on=predicate, when_true=Y, when_false=Z)` is called THEN system SHALL register conditional routing
2. WHEN predicate function is called THEN it SHALL receive unwrapped result from step X
3. IF predicate returns `True` THEN `when_true` step SHALL execute
4. IF predicate returns `False` THEN `when_false` step SHALL execute
5. IF predicate raises exception THEN system SHALL treat as `False` and log warning
6. WHERE predicate is not callable THEN system SHALL raise `TypeError`
7. IF `after` step is not valid THEN system SHALL raise `ValueError`
8. WHEN multiple branches target same step THEN system SHALL raise `ValueError`

**Example:**
```python
wf.branch(
    after=calculate_score,
    on=lambda result: result["score"] > 0.8,
    when_true=high_priority,
    when_false=low_priority
)
```

---

### Requirement 7: Automatic Dependency Resolution

**User Story:** As a developer, I want dependencies to be inferred from function parameters so that I don't need to manually declare them.

#### Acceptance Criteria

1. WHEN step function has parameter named `step_x` THEN system SHALL create dependency on step `step_x`
2. WHEN step function executes THEN parameter `step_x` SHALL contain unwrapped result from `step_x`
3. IF result was `{"ok": data}` THEN parameter SHALL contain `data`
4. IF result was `{"error": msg}` THEN parameter SHALL contain `msg` (for error handlers)
5. WHERE parameter has default value `None` THEN dependency is optional
6. WHEN parameter name doesn't match any step THEN system SHALL raise `ValueError` at definition time
7. IF circular dependency is detected THEN system SHALL raise `ValueError` with cycle description

**Example:**
```python
@step
async def combine(context, fetch_user, fetch_order):
    """Depends on both fetch_user and fetch_order"""
    # fetch_user contains unwrapped result from fetch_user step
    # fetch_order contains unwrapped result from fetch_order step
    return {"ok": {"user": fetch_user, "order": fetch_order}}
```

---

### Requirement 8: Automatic Parallelism

**User Story:** As a developer, I want steps with the same dependencies to execute in parallel automatically so that I don't need explicit parallel syntax.

#### Acceptance Criteria

1. WHEN steps A and B have identical dependency sets THEN system SHALL execute them in parallel
2. WHEN step C depends on both A and B THEN C SHALL wait for both to complete
3. WHERE steps have different dependencies THEN they SHALL NOT execute in parallel
4. WHEN analyzing dependencies THEN system SHALL consider:
   - Direct dependencies (parameters)
   - Diverge/branch paths
   - Timeline position
5. IF parallel execution fails for one step THEN other parallel steps SHALL continue
6. WHEN all parallel steps complete THEN dependent step SHALL receive all results

**Example:**
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

# All three have same dependency (order)
# → Execute in PARALLEL automatically

@step
async def finalize(context, send_email, send_sms, update_inventory):
    """Waits for all three to complete"""
    return {"ok": "done"}
```

---

### Requirement 9: Context Object

**User Story:** As a developer, I want access to execution context in steps so that I can access metadata and shared state.

#### Acceptance Criteria

1. WHEN step executes THEN context SHALL contain:
   - `context.inputs` - Original workflow input data
   - `context.execution_id` - Unique execution ID
   - `context.workflow_name` - Name of workflow
   - `context.step_name` - Name of current step
   - `context.attempt` - Retry attempt number (1-indexed)
2. WHERE context is accessed THEN all fields SHALL be read-only
3. IF step tries to modify context THEN system SHALL raise `AttributeError`

**Example:**
```python
@step
async def my_step(context, inputs):
    user_id = context.inputs["user_id"]
    execution_id = context.execution_id
    attempt = context.attempt

    print(f"Execution {execution_id}, attempt {attempt}")
    return {"ok": "processed"}
```

---

### Requirement 10: Error Handling

**User Story:** As a developer, I want clear error messages when workflow definition is invalid so that I can debug quickly.

#### Acceptance Criteria

1. WHEN circular dependency exists THEN system SHALL raise `ValueError` listing the cycle
2. WHEN step references non-existent dependency THEN system SHALL raise `ValueError` with step name
3. WHEN step function is not async THEN system SHALL raise `TypeError` immediately
4. WHEN return value is invalid THEN system SHALL raise `ValueError` with expected format
5. WHERE syntax error in workflow definition THEN system SHALL raise with line number
6. WHEN gRPC connection fails THEN system SHALL raise `ConnectionError` with retry suggestion

**Example Errors:**
```
ValueError: Circular dependency detected: step_a -> step_b -> step_c -> step_a
ValueError: Step 'process_data' depends on 'fetch_user' which does not exist
TypeError: Step functions must be async. 'my_step' is not async.
```

---

### Requirement 11: Type Hints Support

**User Story:** As a developer, I want to use Python type hints so that my IDE can provide autocomplete and type checking.

#### Acceptance Criteria

1. WHEN SDK provides types THEN it SHALL export:
   - `Context` type for context parameter
   - `StepResult` type for return values
   - `WorkflowBuilder` type for wf parameter
2. WHERE types are used THEN mypy/pyright SHALL validate correctly
3. WHEN invalid type is used THEN type checker SHALL show error

**Example:**
```python
from cerebelum import step, workflow, Context, StepResult

@step
async def typed_step(
    context: Context,
    inputs: dict[str, Any]
) -> StepResult:
    return {"ok": "result"}

@workflow
def typed_workflow(wf: WorkflowBuilder) -> None:
    wf.timeline(typed_step)
```

---

### Requirement 12: Workflow Execution

**User Story:** As a developer, I want to execute workflows using `.execute()` method so that I can trigger workflow runs.

#### Acceptance Criteria

1. WHEN workflow is called with `.execute(inputs)` THEN system SHALL:
   - Build WorkflowDefinition protobuf
   - Send to Core via gRPC
   - Return execution handle
2. WHEN execution starts THEN return value SHALL contain execution ID
3. IF inputs are invalid THEN system SHALL raise `ValueError` before gRPC call
4. WHERE Core is not running THEN system SHALL raise `ConnectionError`
5. WHEN execution completes THEN developer can query status via execution ID

**Example:**
```python
execution = await my_workflow.execute({"user_id": 123})
print(f"Execution started: {execution.id}")

# Poll for results
status = await execution.get_status()
print(f"State: {status.state}")
print(f"Results: {status.results}")
```

---

### Requirement 13: Workflow Validation

**User Story:** As a developer, I want my workflow to be validated at definition time so that I can catch errors before execution.

#### Acceptance Criteria

1. WHEN workflow definition completes (after @workflow function runs) THEN system SHALL automatically validate the workflow structure
2. WHEN validation detects error THEN system SHALL raise exception with clear description before `.execute()` is called
3. WHEN developer calls `.validate()` explicitly THEN system SHALL run all validation checks and return detailed report
4. WHERE validation succeeds THEN `.execute()` SHALL proceed without re-validation
5. IF validation fails THEN error message SHALL include:
   - Which validation rule failed
   - Step name(s) involved
   - Suggestion for fix

#### Validation Checks

The system SHALL validate:

1. **Timeline Completeness**
   - WHEN timeline contains steps THEN all steps SHALL be decorated with @step
   - IF timeline references undefined step THEN raise `ValueError` with step name

2. **Dependency Integrity**
   - WHEN step has parameter dependency THEN referenced step SHALL exist
   - IF step depends on non-existent step THEN raise `ValueError` listing available steps
   - WHEN analyzing dependencies THEN circular dependencies SHALL be detected
   - IF circular dependency exists THEN raise `ValueError` with cycle path

3. **Diverge Validation**
   - WHEN diverge rule is defined THEN `from_step` SHALL be a valid step
   - WHEN diverge patterns are defined THEN all target steps SHALL exist
   - IF diverge target is composition THEN all steps in composition SHALL exist
   - WHEN multiple diverges reference same step THEN raise `ValueError`

4. **Branch Validation**
   - WHEN branch rule is defined THEN `after` step SHALL exist
   - WHEN branch defines `when_true`/`when_false` THEN both steps SHALL exist
   - IF predicate is not callable THEN raise `TypeError`
   - WHEN multiple branches reference same step THEN raise `ValueError`

5. **Parameter Signature Validation**
   - WHEN step defines dependencies THEN parameter names SHALL match step names
   - IF parameter name doesn't match any step AND is not 'context'/'inputs' THEN raise `ValueError`
   - WHERE parameter has no default value THEN dependency is required
   - WHEN step is first in timeline BUT has no 'inputs' parameter THEN raise `ValueError`

6. **Return Value Contract**
   - WHEN step is called THEN return value SHALL be validated at runtime
   - IF return value is not `{"ok": ...}` or `{"error": ...}` THEN raise `ValueError`
   - WHERE return value is validated THEN provide clear error message with step name

7. **Execution Readiness**
   - WHEN workflow has no timeline AND no diverge rules THEN raise `ValueError` (empty workflow)
   - WHEN workflow has diverge-only paths THEN ensure all paths eventually terminate
   - IF workflow has unreachable steps THEN warn developer (optional)

**Example:**
```python
@step
async def step_a(context, inputs):
    return {"ok": "a"}

@step
async def step_b(context, step_x):  # step_x doesn't exist!
    return {"ok": "b"}

@workflow
def invalid_workflow(wf):
    wf.timeline(step_a >> step_b)

# Validation happens automatically after workflow definition
# Raises: ValueError: Step 'step_b' depends on 'step_x' which does not exist.
# Available steps: ['step_a', 'step_b']
# Suggestion: Check that 'step_x' is decorated with @step or rename parameter to match existing step.

# Explicit validation (optional)
try:
    invalid_workflow.validate()
except ValueError as e:
    print(f"Validation failed: {e}")
    # Can inspect detailed report
    print(e.validation_report)
```

**Validation Report Structure:**
```python
{
    "valid": False,
    "errors": [
        {
            "type": "DependencyError",
            "step": "step_b",
            "message": "Depends on 'step_x' which does not exist",
            "available_steps": ["step_a", "step_b"],
            "suggestion": "Check that 'step_x' is decorated with @step"
        }
    ],
    "warnings": [
        {
            "type": "UnreachableStep",
            "step": "orphan_step",
            "message": "Step is not reachable from timeline or diverge/branch rules"
        }
    ]
}
```

---

## Non-Functional Requirements

### NFR-1: Performance

1. Workflow definition SHALL complete in < 100ms for workflows with < 100 steps
2. Dependency analysis SHALL be O(n log n) where n is number of steps
3. Protobuf serialization SHALL complete in < 50ms

### NFR-2: Compatibility

1. SDK SHALL work with Python 3.9+
2. SDK SHALL work with existing Cerebelum Core (no Core changes required)
3. SDK SHALL use existing protobuf definitions

### NFR-3: Developer Experience

1. Error messages SHALL include step name and line number when possible
2. Type hints SHALL provide IDE autocomplete
3. Documentation SHALL include examples for all features

---

## Summary

This requirements document specifies:
- ✅ Decorators (`@step`, `@workflow`)
- ✅ Sequential composition (`>>`)
- ✅ Control flow (`timeline`, `diverge`, `branch`)
- ✅ Automatic dependency resolution
- ✅ Automatic parallelism
- ✅ Context object
- ✅ Error handling
- ✅ Type hints
- ✅ Workflow execution
- ✅ **Workflow validation** (early error detection)

All requirements use clear acceptance criteria to enable validation during implementation and testing.

---

**Next Phase:** Design Document (technical architecture)

#!/usr/bin/env python3
"""Smoke test for Phase 6 implementation - Error Handling and Polish."""

import asyncio
from cerebelum import (
    step,
    workflow,
    Context,
    StepRegistry,
    WorkflowRegistry,
)
from cerebelum.dsl import (
    DSLError,
    StepDefinitionError,
    WorkflowDefinitionError,
    DependencyError,
    StepExecutionError,
)


async def run_tests():
    """Run all Phase 6 tests."""

    print("=" * 70)
    print("PHASE 6: ERROR HANDLING AND POLISH - SMOKE TEST")
    print("=" * 70)
    print()

    # Test 1: StepDefinitionError - non-async function
    print("=" * 70)
    print("Test 1: StepDefinitionError - non-async function")
    print("=" * 70)

    try:
        @step
        def non_async_step(context, inputs):
            return {"ok": "should_fail"}
        print(f"  ✗ ERROR: Should have raised StepDefinitionError")
        assert False
    except StepDefinitionError as e:
        print(f"  ✓ Raised StepDefinitionError")
        print(f"  - Step name: {e.step_name}")
        print(f"  - Message: {e.message}")
        assert e.step_name == "non_async_step"
        assert "async" in e.message.lower()
    print()

    # Test 2: StepDefinitionError - missing context parameter
    print("=" * 70)
    print("Test 2: StepDefinitionError - missing context parameter")
    print("=" * 70)

    try:
        @step
        async def no_context_step(inputs):
            return {"ok": "should_fail"}
        print(f"  ✗ ERROR: Should have raised StepDefinitionError")
        assert False
    except StepDefinitionError as e:
        print(f"  ✓ Raised StepDefinitionError")
        print(f"  - Step name: {e.step_name}")
        print(f"  - Message: {e.message}")
        assert e.step_name == "no_context_step"
        assert "context" in e.message.lower()
    print()

    # Test 3: WorkflowDefinitionError - empty timeline
    print("=" * 70)
    print("Test 3: WorkflowDefinitionError - empty timeline")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    try:
        @workflow
        def empty_workflow(wf):
            pass  # No timeline!

        # Trigger validation
        empty_workflow.validate()
        print(f"  ✗ ERROR: Should have raised WorkflowDefinitionError")
        assert False
    except WorkflowDefinitionError as e:
        print(f"  ✓ Raised WorkflowDefinitionError")
        print(f"  - Workflow name: {e.workflow_name}")
        print(f"  - Errors count: {len(e.errors)}")
        print(f"  - First error: {e.errors[0][:60]}...")
        assert e.workflow_name == "empty_workflow"
        assert len(e.errors) > 0
        assert "timeline" in e.errors[0].lower()
    print()

    # Test 4: WorkflowDefinitionError - circular dependency
    print("=" * 70)
    print("Test 4: WorkflowDefinitionError - circular dependency")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def cycle_a(context: Context, cycle_c: dict):
        return {"ok": "a"}

    @step
    async def cycle_b(context: Context, cycle_a: dict):
        return {"ok": "b"}

    @step
    async def cycle_c(context: Context, cycle_b: dict):
        return {"ok": "c"}

    try:
        @workflow
        def circular_workflow(wf):
            wf.timeline([cycle_a, cycle_b, cycle_c])

        # Trigger validation
        circular_workflow.validate()
        print(f"  ✗ ERROR: Should have raised WorkflowDefinitionError")
        assert False
    except WorkflowDefinitionError as e:
        print(f"  ✓ Raised WorkflowDefinitionError")
        print(f"  - Workflow name: {e.workflow_name}")
        print(f"  - Errors: {e.errors}")
        assert "circular" in str(e).lower() or "cycle" in str(e).lower()
    print()

    # Test 5: DependencyError - missing dependency
    print("=" * 70)
    print("Test 5: DependencyError - missing dependency at execution")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    from cerebelum.dsl.execution import DSLExecutionAdapter
    from cerebelum.types import ExecutionContext

    @step
    async def needs_missing_dep(context: Context, missing_step: dict):
        return {"ok": "should_not_reach"}

    try:
        # Try to execute without the dependency in execution_state
        exec_ctx = ExecutionContext(
            execution_id="test123",
            workflow_id="test_wf",
            step_name="needs_missing_dep",
        )

        await DSLExecutionAdapter.execute_step(
            step=needs_missing_dep,
            exec_context=exec_ctx,
            execution_state={},  # Empty - no dependencies
            workflow_inputs={"test": "data"}
        )
        print(f"  ✗ ERROR: Should have raised DependencyError")
        assert False
    except DependencyError as e:
        print(f"  ✓ Raised DependencyError")
        print(f"  - Step name: {e.step_name}")
        print(f"  - Dependency: {e.dependency}")
        print(f"  - Reason: {e.reason}")
        assert e.step_name == "needs_missing_dep"
        assert e.dependency == "missing_step"
    print()

    # Test 6: StepExecutionError - runtime exception
    print("=" * 70)
    print("Test 6: StepExecutionError - runtime exception")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def failing_step(context: Context, inputs: dict):
        raise ValueError("Something went wrong!")

    @workflow
    def error_workflow(wf):
        wf.timeline(failing_step)

    try:
        result = await error_workflow.execute({"test": "data"})
        print(f"  ✗ ERROR: Should have raised StepExecutionError")
        assert False
    except StepExecutionError as e:
        print(f"  ✓ Raised StepExecutionError")
        print(f"  - Step name: {e.step_name}")
        print(f"  - Message: {e.message}")
        print(f"  - Original error type: {type(e.original_error).__name__}")
        print(f"  - Execution ID: {e.execution_id}")
        assert e.step_name == "failing_step"
        assert isinstance(e.original_error, ValueError)
        assert e.execution_id is not None
    print()

    # Test 7: Improved error messages
    print("=" * 70)
    print("Test 7: Error message quality")
    print("=" * 70)

    # Test StepDefinitionError message quality
    try:
        @step
        def bad_step():
            pass
    except StepDefinitionError as e:
        print(f"✓ StepDefinitionError message quality:")
        print(f"  {str(e)}")
        # Just check that the message is informative
        assert len(str(e)) > 50  # Should have a descriptive message
        assert "async" in str(e).lower()
    print()

    # Test 8: Async workflow error
    print("=" * 70)
    print("Test 8: Async workflow definition error")
    print("=" * 70)

    try:
        @workflow
        async def async_workflow_bad(wf):
            wf.timeline([])
        print(f"  ✗ ERROR: Should have raised StepDefinitionError")
        assert False
    except StepDefinitionError as e:
        print(f"  ✓ Raised StepDefinitionError")
        print(f"  - Message: {e.message}")
        assert "async" in e.message.lower()
        assert "not" in e.message.lower() or "remove" in e.message.lower()
    print()

    # Test 9: Exception hierarchy
    print("=" * 70)
    print("Test 9: Exception hierarchy")
    print("=" * 70)

    # All should inherit from DSLError
    assert issubclass(StepDefinitionError, DSLError)
    assert issubclass(WorkflowDefinitionError, DSLError)
    assert issubclass(DependencyError, DSLError)
    assert issubclass(StepExecutionError, DSLError)

    print(f"✓ All custom exceptions inherit from DSLError")
    print(f"  - StepDefinitionError: {issubclass(StepDefinitionError, DSLError)}")
    print(f"  - WorkflowDefinitionError: {issubclass(WorkflowDefinitionError, DSLError)}")
    print(f"  - DependencyError: {issubclass(DependencyError, DSLError)}")
    print(f"  - StepExecutionError: {issubclass(StepExecutionError, DSLError)}")
    print()

    # Test 10: Catching DSLError
    print("=" * 70)
    print("Test 10: Catching base DSLError")
    print("=" * 70)

    caught = False
    try:
        @step
        def another_bad_step():
            pass
    except DSLError:
        caught = True
        print(f"  ✓ Successfully caught StepDefinitionError as DSLError")

    assert caught
    print()

    # Summary
    print("=" * 70)
    print("PHASE 6 SMOKE TEST SUMMARY")
    print("=" * 70)
    print("✅ All tests passed!")
    print()
    print("Implemented features:")
    print("  ✓ Custom exception types (DSLError hierarchy)")
    print("  ✓ StepDefinitionError with helpful messages")
    print("  ✓ WorkflowDefinitionError with error list")
    print("  ✓ DependencyError with step and dependency info")
    print("  ✓ StepExecutionError with original error wrapping")
    print("  ✓ Improved error messages with examples")
    print("  ✓ Exception hierarchy for easy catching")
    print("  ✓ Execution context in errors")
    print()
    print("DSL Implementation Complete!")
    print("=" * 70)


if __name__ == "__main__":
    asyncio.run(run_tests())

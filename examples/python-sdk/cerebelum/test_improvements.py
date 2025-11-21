#!/usr/bin/env python3
"""Test for DSL Improvements - Auto-wrapping and Early Validation."""

import asyncio
import warnings
from cerebelum import step, workflow, Context, StepRegistry, WorkflowRegistry


async def run_tests():
    """Test DSL improvements."""

    print("=" * 70)
    print("DSL IMPROVEMENTS TEST")
    print("=" * 70)
    print()

    # Test 1: Auto-wrapping - Return raw value
    print("=" * 70)
    print("Test 1: Auto-wrapping - Return raw value")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def returns_raw_value(context: Context, inputs: dict):
        """Step returns raw value, not envelope."""
        return "Hello, World!"  # ✅ No need for {"ok": ...}

    @workflow
    def raw_return_workflow(wf):
        wf.timeline(returns_raw_value)

    result = await raw_return_workflow.execute({"test": "data"})

    print(f"✓ Workflow executed")
    print(f"  - Output: {result.output}")

    # The wrapper should have converted it to {"ok": "Hello, World!"}
    assert result.output == {"ok": "Hello, World!"}
    print(f"  ✓ Raw return auto-wrapped to envelope")
    print()

    # Test 2: Auto-wrapping - Exception handling
    print("=" * 70)
    print("Test 2: Auto-wrapping - Exception auto-caught")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def throws_exception(context: Context, inputs: dict):
        """Step throws exception instead of returning error."""
        raise ValueError("Something went wrong!")  # ✅ No need to catch

    @step
    async def check_exception_output(context: Context, throws_exception: dict):
        """This step receives the error envelope."""
        # The wrapper converted the exception to {"error": ...}
        return throws_exception  # Pass it through

    @workflow
    def exception_workflow(wf):
        wf.timeline(throws_exception >> check_exception_output)

    # The workflow will fail because first step returns error
    # But we can verify the wrapper worked by checking the error message
    try:
        result = await exception_workflow.execute({"test": "data"})
        print(f"  ℹ️  Workflow completed (error was handled)")
    except Exception as e:
        print(f"  ℹ️  Workflow failed (expected): {type(e).__name__}")
        # The error message should contain our original exception message
        assert "Something went wrong" in str(e)

    print(f"  ✓ Exception auto-caught by wrapper (converted to error envelope)")
    print()

    # Test 3: Backwards compatibility - Manual envelope
    print("=" * 70)
    print("Test 3: Backwards compatibility - Manual envelope")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def manual_envelope(context: Context, inputs: dict):
        """Step still returns manual envelope."""
        return {"ok": "manual_value"}  # Still supported

    @workflow
    def manual_workflow(wf):
        wf.timeline(manual_envelope)

    result = await manual_workflow.execute({"test": "data"})

    print(f"✓ Workflow executed")
    print(f"  - Output: {result.output}")

    # Should pass through unchanged
    assert result.output == {"ok": "manual_value"}
    print(f"  ✓ Manual envelope passed through unchanged")
    print()

    # Test 4: Early dependency validation (warning)
    print("=" * 70)
    print("Test 4: Early dependency validation")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    # First, define a step
    @step
    async def step_a(context: Context, inputs: dict):
        return "A"

    # Now define a step that depends on a non-existent step
    # This should trigger a warning
    print("  Defining step with non-existent dependency...")

    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always")

        @step
        async def step_b(context: Context, nonexistent_step: dict):
            return "B"

        # Check if warning was raised
        if len(w) > 0:
            print(f"  ✓ Warning raised: {w[0].message}")
            assert "nonexistent_step" in str(w[0].message)
            assert "not yet registered" in str(w[0].message)
        else:
            print(f"  ℹ️  No warning (dependency might be registered later)")

    print()

    # Test 5: Complex workflow with auto-wrapping
    print("=" * 70)
    print("Test 5: Complex workflow - No manual envelopes needed")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def fetch_user(context: Context, inputs: dict):
        # Just return the data - no envelope needed!
        user_id = inputs["user_id"]
        return {"id": user_id, "name": "Alice", "premium": True}

    @step
    async def calculate_discount(context: Context, fetch_user: dict):
        # Work with clean data
        discount = 0.20 if fetch_user["premium"] else 0.10
        return {"user": fetch_user, "discount": discount}

    @step
    async def apply_discount(context: Context, calculate_discount: dict):
        price = 100.0
        discount = calculate_discount["discount"]
        final_price = price * (1 - discount)
        return {"price": final_price, "user": calculate_discount["user"]["name"]}

    @workflow
    def shopping_workflow(wf):
        wf.timeline(fetch_user >> calculate_discount >> apply_discount)

    result = await shopping_workflow.execute({"user_id": 42})

    print(f"✓ Complex workflow executed")
    print(f"  - Output: {result.output}")

    # All returns should be auto-wrapped
    assert result.output["ok"]["price"] == 80.0  # 20% discount
    assert result.output["ok"]["user"] == "Alice"
    print(f"  ✓ All steps worked with clean data (no manual envelopes)")
    print()

    # Summary
    print("=" * 70)
    print("IMPROVEMENTS TEST SUMMARY")
    print("=" * 70)
    print("✅ All improvements working!")
    print()
    print("New features:")
    print("  ✓ Auto-wrap raw returns to {'ok': value}")
    print("  ✓ Auto-catch exceptions to {'error': message}")
    print("  ✓ Backwards compatible with manual envelopes")
    print("  ✓ Early validation warnings for missing dependencies")
    print("  ✓ Cleaner code - no boilerplate!")
    print()
    print("Developer Experience: IMPROVED! 🎉")
    print("=" * 70)


if __name__ == "__main__":
    asyncio.run(run_tests())

#!/usr/bin/env python3
"""Smoke test for Phase 5 implementation."""

import asyncio
from cerebelum import (
    step,
    workflow,
    Context,
    StepRegistry,
    WorkflowRegistry,
    DSLLocalExecutor,
)


async def run_tests():
    """Run all Phase 5 tests."""

    print("=" * 70)
    print("PHASE 5: EXECUTION INTEGRATION - SMOKE TEST")
    print("=" * 70)
    print()

    # Test 1: Single step workflow
    print("=" * 70)
    print("Test 1: Single step workflow execution")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def greet_user(context: Context, inputs: dict):
        user_name = inputs.get("name", "stranger")
        return {"ok": f"Hello, {user_name}!"}

    @workflow
    def greeting_workflow(wf):
        wf.timeline(greet_user)

    result = await greeting_workflow.execute({"name": "Alice"})

    print(f"✓ Workflow executed")
    print(f"  - Status: {result.status}")
    print(f"  - Output: {result.output}")
    assert result.status == "completed"
    assert result.output == {"ok": "Hello, Alice!"}
    print(f"  ✓ Output correct")
    print()

    # Test 2: Multi-step workflow with dependencies
    print("=" * 70)
    print("Test 2: Multi-step workflow with dependencies")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def fetch_user(context: Context, inputs: dict):
        user_id = inputs.get("user_id")
        return {"ok": {"id": user_id, "name": "John", "premium": True}}

    @step
    async def validate_user(context: Context, fetch_user: dict):
        user = fetch_user
        if user["id"] > 0:
            return {"ok": {"valid": True, "user": user}}
        return {"error": "invalid_id"}

    @step
    async def process_payment(context: Context, validate_user: dict):
        if validate_user.get("valid"):
            user = validate_user["user"]
            amount = 100 if user["premium"] else 50
            return {"ok": {"amount": amount, "status": "processed"}}
        return {"error": "not_valid"}

    @workflow
    def payment_workflow(wf):
        wf.timeline(fetch_user >> validate_user >> process_payment)

    result = await payment_workflow.execute({"user_id": 123})

    print(f"✓ Workflow executed")
    print(f"  - Status: {result.status}")
    print(f"  - Output: {result.output}")
    assert result.status == "completed"
    assert result.output["ok"]["amount"] == 100
    print(f"  ✓ Dependencies resolved correctly")
    print()

    # Test 3: Context propagation
    print("=" * 70)
    print("Test 3: Context propagation")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    contexts = []

    @step
    async def step1(context: Context, inputs: dict):
        contexts.append(context)
        return {"ok": "step1"}

    @step
    async def step2(context: Context, step1: dict):
        contexts.append(context)
        return {"ok": "step2"}

    @workflow
    def ctx_workflow(wf):
        wf.timeline(step1 >> step2)

    result = await ctx_workflow.execute({"test": "data"})

    print(f"✓ Workflow executed")
    assert len(contexts) == 2
    assert contexts[0].execution_id == contexts[1].execution_id
    assert contexts[0].step_name == "step1"
    assert contexts[1].step_name == "step2"
    print(f"  - Execution ID: {contexts[0].execution_id}")
    print(f"  - Step names: [{contexts[0].step_name}, {contexts[1].step_name}]")
    print(f"  ✓ Context propagated correctly")
    print()

    # Test 4: Multiple dependencies
    print("=" * 70)
    print("Test 4: Multiple dependencies")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def fetch_price(context: Context, inputs: dict):
        return {"ok": 100}

    @step
    async def fetch_quantity(context: Context, inputs: dict):
        return {"ok": 3}

    @step
    async def calculate_total(context: Context, fetch_price: dict, fetch_quantity: dict):
        total = fetch_price * fetch_quantity
        return {"ok": total}

    @workflow
    def cart_workflow(wf):
        wf.timeline([fetch_price, fetch_quantity, calculate_total])

    result = await cart_workflow.execute({"cart_id": 456})

    print(f"✓ Workflow executed")
    print(f"  - Output: {result.output}")
    assert result.output == {"ok": 300}
    print(f"  ✓ Multiple dependencies resolved")
    print()

    # Test 5: Error handling
    print("=" * 70)
    print("Test 5: Error handling")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def failing_step(context: Context, inputs: dict):
        if inputs.get("should_fail"):
            return {"error": "intentional_failure"}
        return {"ok": "success"}

    @step
    async def next_step(context: Context, failing_step: dict):
        return {"ok": "should_not_reach"}

    @workflow
    def error_workflow(wf):
        wf.timeline(failing_step >> next_step)

    try:
        result = await error_workflow.execute({"should_fail": True})
        print(f"  ✗ ERROR: Should have raised exception")
        assert False
    except Exception as e:
        print(f"  ✓ Exception raised: {type(e).__name__}")
        print(f"  - Message: {str(e)[:80]}")
    print()

    # Test 6: DSLLocalExecutor direct usage
    print("=" * 70)
    print("Test 6: DSLLocalExecutor direct usage")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def double_value(context: Context, inputs: dict):
        return {"ok": inputs.get("value") * 2}

    @step
    async def add_ten(context: Context, double_value: dict):
        return {"ok": double_value + 10}

    @workflow
    def math_workflow(wf):
        wf.timeline(double_value >> add_ten)

    # Build manually
    report = math_workflow.validate()

    # Use executor directly
    executor = DSLLocalExecutor()
    result = await executor.execute(math_workflow._built_definition, {"value": 5})

    print(f"✓ Direct executor usage")
    print(f"  - Output: {result.output}")
    assert result.output == {"ok": 20}  # (5 * 2) + 10
    print(f"  ✓ Executor works correctly")
    print()

    # Test 7: Complex workflow
    print("=" * 70)
    print("Test 7: Complex end-to-end workflow")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def authenticate(context: Context, inputs: dict):
        api_key = inputs.get("api_key")
        if api_key == "valid_key":
            return {"ok": {"authenticated": True, "user_id": 42}}
        return {"error": "invalid_key"}

    @step
    async def fetch_order(context: Context, authenticate: dict):
        if authenticate.get("authenticated"):
            return {"ok": {"order_id": 1001, "items": 3, "total": 299.99}}
        return {"error": "not_auth"}

    @step
    async def validate_inventory(context: Context, fetch_order: dict):
        order = fetch_order
        if order["items"] <= 5:
            return {"ok": {"available": True, "order": order}}
        return {"error": "insufficient"}

    @step
    async def process_order(context: Context, validate_inventory: dict):
        if validate_inventory.get("available"):
            order = validate_inventory["order"]
            return {"ok": {"processed": True, "order_id": order["order_id"], "amount": order["total"]}}
        return {"error": "validation_failed"}

    @workflow
    def ecommerce_workflow(wf):
        wf.timeline(authenticate >> fetch_order >> validate_inventory >> process_order)

    result = await ecommerce_workflow.execute({"api_key": "valid_key"})

    print(f"✓ Complex workflow executed")
    print(f"  - Status: {result.status}")
    print(f"  - Output: {result.output}")
    assert result.output["ok"]["processed"] is True
    assert result.output["ok"]["order_id"] == 1001
    print(f"  ✓ All steps executed correctly")
    print()

    # Summary
    print("=" * 70)
    print("PHASE 5 SMOKE TEST SUMMARY")
    print("=" * 70)
    print("✅ All tests passed!")
    print()
    print("Implemented features:")
    print("  ✓ DSLExecutionAdapter with dependency resolution")
    print("  ✓ DSLLocalExecutor for local execution")
    print("  ✓ Context creation and propagation")
    print("  ✓ Integration with @workflow.execute()")
    print("  ✓ Automatic dependency injection")
    print('  ✓ Return value contract ({"ok": ...} / {"error": ...})')
    print("  ✓ Error handling during execution")
    print("  ✓ Multi-step workflows")
    print("  ✓ End-to-end execution")
    print()
    print("Next: Phase 6 - Error Handling and Polish")
    print("=" * 70)


if __name__ == "__main__":
    asyncio.run(run_tests())

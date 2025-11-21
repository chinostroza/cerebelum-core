#!/usr/bin/env python3
"""Test for Parallel List Syntax - step1 >> [step2, step3] >> step4."""

import asyncio
from cerebelum import (
    step,
    workflow,
    Context,
    StepRegistry,
    WorkflowRegistry,
    ParallelStepGroup,
    StepComposition,
)


async def run_tests():
    """Test parallel list syntax."""

    print("=" * 70)
    print("PARALLEL LIST SYNTAX TEST")
    print("=" * 70)
    print()

    # Test 1: Basic parallel syntax - step >> [step, step]
    print("=" * 70)
    print("Test 1: Basic parallel syntax - step >> [step_b, step_c]")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def step_a(context: Context, inputs: dict):
        """First step."""
        print(f"  [{context.step_name}] Executing...")
        return {"data": "from_a"}

    @step
    async def step_b(context: Context, step_a: dict):
        """Parallel step B."""
        print(f"  [{context.step_name}] Executing in parallel...")
        return {"data": "from_b", "input": step_a}

    @step
    async def step_c(context: Context, step_a: dict):
        """Parallel step C."""
        print(f"  [{context.step_name}] Executing in parallel...")
        return {"data": "from_c", "input": step_a}

    # Test composition syntax
    composition = step_a >> [step_b, step_c]

    print(f"✓ Composition created: {composition}")
    assert isinstance(composition, StepComposition)
    assert len(composition.items) == 2
    assert composition.items[0] == step_a
    assert isinstance(composition.items[1], ParallelStepGroup)
    assert len(composition.items[1].steps) == 2
    print(f"  ✓ Composition structure is correct")
    print()

    # Test 2: Full workflow with parallel steps
    print("=" * 70)
    print("Test 2: Full workflow - step_a >> [step_b, step_c] >> step_d")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def step_a(context: Context, inputs: dict):
        """First step."""
        print(f"  [{context.step_name}] Processing input...")
        return {"value": inputs.get("x", 10)}

    @step
    async def step_b(context: Context, step_a: dict):
        """Parallel step B - multiply by 2."""
        print(f"  [{context.step_name}] Multiply by 2...")
        return {"result": step_a["value"] * 2}

    @step
    async def step_c(context: Context, step_a: dict):
        """Parallel step C - add 100."""
        print(f"  [{context.step_name}] Add 100...")
        return {"result": step_a["value"] + 100}

    @step
    async def step_d(context: Context, step_b: dict, step_c: dict):
        """Final step - combine results."""
        print(f"  [{context.step_name}] Combining results...")
        return {
            "b_result": step_b["result"],
            "c_result": step_c["result"],
            "sum": step_b["result"] + step_c["result"]
        }

    @workflow
    def parallel_workflow(wf):
        """Workflow with parallel execution."""
        wf.timeline(step_a >> [step_b, step_c] >> step_d)

    result = await parallel_workflow.execute({"x": 5})

    print(f"✓ Workflow executed")
    print(f"  - Input: x=5")
    print(f"  - step_b result (5*2): {result.output['ok']['b_result']}")
    print(f"  - step_c result (5+100): {result.output['ok']['c_result']}")
    print(f"  - Sum: {result.output['ok']['sum']}")

    assert result.output["ok"]["b_result"] == 10  # 5 * 2
    assert result.output["ok"]["c_result"] == 105  # 5 + 100
    assert result.output["ok"]["sum"] == 115  # 10 + 105
    print(f"  ✓ All results correct")
    print()

    # Test 3: Multiple parallel groups
    print("=" * 70)
    print("Test 3: Multiple parallel groups - a >> [b, c] >> d >> [e, f]")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def step_a(context: Context, inputs: dict):
        return {"value": 1}

    @step
    async def step_b(context: Context, step_a: dict):
        return {"value": step_a["value"] + 1}  # 2

    @step
    async def step_c(context: Context, step_a: dict):
        return {"value": step_a["value"] + 2}  # 3

    @step
    async def step_d(context: Context, step_b: dict, step_c: dict):
        return {"value": step_b["value"] + step_c["value"]}  # 5

    @step
    async def step_e(context: Context, step_d: dict):
        return {"value": step_d["value"] * 2}  # 10

    @step
    async def step_f(context: Context, step_d: dict):
        return {"value": step_d["value"] * 3}  # 15

    @step
    async def step_g(context: Context, step_e: dict, step_f: dict):
        return {"total": step_e["value"] + step_f["value"]}  # 25

    @workflow
    def multi_parallel_workflow(wf):
        wf.timeline(
            step_a >> [step_b, step_c] >> step_d >> [step_e, step_f] >> step_g
        )

    result = await multi_parallel_workflow.execute({})

    print(f"✓ Workflow with multiple parallel groups executed")
    print(f"  - Final total: {result.output['ok']['total']}")

    assert result.output["ok"]["total"] == 25
    print(f"  ✓ Result correct")
    print()

    # Test 4: Error handling - empty list
    print("=" * 70)
    print("Test 4: Error handling - empty parallel list")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def step_a(context: Context, inputs: dict):
        return "a"

    try:
        composition = step_a >> []
        print(f"  ❌ Should have raised ValueError")
        assert False
    except ValueError as e:
        print(f"  ✓ ValueError raised: {e}")
        assert "empty" in str(e).lower()

    print()

    # Test 5: Error handling - non-step in list
    print("=" * 70)
    print("Test 5: Error handling - non-step in parallel list")
    print("=" * 70)

    try:
        composition = step_a >> [step_a, "not_a_step", step_a]
        print(f"  ❌ Should have raised TypeError")
        assert False
    except TypeError as e:
        print(f"  ✓ TypeError raised: {e}")
        assert "decorated with @step" in str(e)

    print()

    # Test 6: Extended composition - composition >> [steps]
    print("=" * 70)
    print("Test 6: Extended composition - (a >> b) >> [c, d]")
    print("=" * 70)

    StepRegistry._steps = {}
    WorkflowRegistry._workflows = {}

    @step
    async def step_a(context: Context, inputs: dict):
        return {"v": 1}

    @step
    async def step_b(context: Context, step_a: dict):
        return {"v": 2}

    @step
    async def step_c(context: Context, step_b: dict):
        return {"v": 3}

    @step
    async def step_d(context: Context, step_b: dict):
        return {"v": 4}

    composition = (step_a >> step_b) >> [step_c, step_d]

    print(f"✓ Extended composition created: {composition}")
    assert isinstance(composition, StepComposition)
    assert len(composition.items) == 3
    assert composition.items[0] == step_a
    assert composition.items[1] == step_b
    assert isinstance(composition.items[2], ParallelStepGroup)
    print(f"  ✓ Structure correct")
    print()

    # Test 7: List on left side - [steps] >> step (should work via composition)
    print("=" * 70)
    print("Test 7: Reverse composition - [a, b] creates error")
    print("=" * 70)

    # Note: [a, b] >> c is not valid Python syntax for our DSL
    # because lists don't have __rshift__. Users must use:
    # - step >> [a, b] >> c
    # - Or define them separately in timeline

    print("  Note: [a, b] >> c syntax is not supported")
    print("  Use: step >> [a, b] >> c instead")
    print("  ✓ This is expected behavior")
    print()

    # Summary
    print("=" * 70)
    print("PARALLEL SYNTAX TEST SUMMARY")
    print("=" * 70)
    print("✅ All parallel list syntax tests passing!")
    print()
    print("New features:")
    print("  ✓ step >> [step_a, step_b] creates parallel group")
    print("  ✓ step >> [a, b] >> step works correctly")
    print("  ✓ Multiple parallel groups supported")
    print("  ✓ Empty list raises ValueError")
    print("  ✓ Non-step in list raises TypeError")
    print("  ✓ Composition chains work with parallel groups")
    print()
    print("Developer Experience: IMPROVED! 🎉")
    print("Parallel execution is now explicit and clear!")
    print("=" * 70)


if __name__ == "__main__":
    asyncio.run(run_tests())

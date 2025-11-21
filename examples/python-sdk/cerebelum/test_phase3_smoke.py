#!/usr/bin/env python3
"""Smoke test for Phase 3 implementation.

This script tests the workflow builder and validation:
- WorkflowBuilder with timeline(), diverge(), branch() methods
- WorkflowValidator with 7 validation checks
- Integration with @workflow decorator
- Error handling for invalid workflows
- Validation at definition time
"""

from cerebelum import (
    step,
    workflow,
    Context,
    StepRegistry,
    WorkflowRegistry,
)
from cerebelum.dsl import (
    WorkflowBuilder,
    WorkflowValidator,
    ValidationReport,
    DivergeRule,
    BranchRule,
)

# Clear registries for clean test
StepRegistry._steps = {}
WorkflowRegistry._workflows = {}

print("=" * 70)
print("PHASE 3: WORKFLOW BUILDER AND VALIDATION - SMOKE TEST")
print("=" * 70)
print()


# Test 1: WorkflowBuilder with timeline()
print("=" * 70)
print("Test 1: WorkflowBuilder - timeline() method")
print("=" * 70)

@step
async def step1(context: Context, inputs: dict):
    return {"ok": "step1"}

@step
async def step2(context: Context, step1: dict):
    return {"ok": "step2"}

@step
async def step3(context: Context, step2: dict):
    return {"ok": "step3"}

builder = WorkflowBuilder("test_workflow")
builder.timeline(step1 >> step2 >> step3)

timeline = builder.get_timeline()
print(f"✓ Created timeline with {len(timeline)} steps")
print(f"  - Steps: {[s.name for s in timeline]}")
assert len(timeline) == 3
assert timeline[0].name == "step1"
assert timeline[1].name == "step2"
assert timeline[2].name == "step3"
print()


# Test 2: WorkflowBuilder - timeline() with list
print("=" * 70)
print("Test 2: WorkflowBuilder - timeline() with list")
print("=" * 70)

builder2 = WorkflowBuilder("test_workflow2")
builder2.timeline([step1, step2, step3])

timeline2 = builder2.get_timeline()
print(f"✓ Created timeline with list: {[s.name for s in timeline2]}")
assert len(timeline2) == 3
print()


# Test 3: WorkflowBuilder - diverge() method
print("=" * 70)
print("Test 3: WorkflowBuilder - diverge() method")
print("=" * 70)

@step
async def check_user(context: Context, inputs: dict):
    return {"ok": "premium"}

@step
async def premium_flow(context: Context, check_user: dict):
    return {"ok": "premium_result"}

@step
async def standard_flow(context: Context, check_user: dict):
    return {"ok": "standard_result"}

builder3 = WorkflowBuilder("test_workflow3")
builder3.timeline(check_user)
builder3.diverge(check_user, {
    "premium": premium_flow,
    "standard": standard_flow
})

diverge_rules = builder3.get_diverge_rules()
print(f"✓ Created diverge rule")
print(f"  - From step: {diverge_rules[0].from_step.name}")
print(f"  - Patterns: {list(diverge_rules[0].patterns.keys())}")
assert len(diverge_rules) == 1
assert diverge_rules[0].from_step.name == "check_user"
assert "premium" in diverge_rules[0].patterns
assert "standard" in diverge_rules[0].patterns
print()


# Test 4: WorkflowBuilder - branch() method
print("=" * 70)
print("Test 4: WorkflowBuilder - branch() method")
print("=" * 70)

@step
async def check_inventory(context: Context, inputs: dict):
    return {"ok": {"in_stock": True}}

@step
async def process_order(context: Context, check_inventory: dict):
    return {"ok": "order_processed"}

@step
async def backorder(context: Context, check_inventory: dict):
    return {"ok": "backordered"}

builder4 = WorkflowBuilder("test_workflow4")
builder4.timeline(check_inventory)
builder4.branch(
    after=check_inventory,
    condition=lambda out: out.get("in_stock", False),
    when_true=process_order,
    when_false=backorder
)

branch_rules = builder4.get_branch_rules()
print(f"✓ Created branch rule")
print(f"  - After step: {branch_rules[0].after.name}")
print(f"  - When true: {branch_rules[0].when_true.name}")
print(f"  - When false: {branch_rules[0].when_false.name}")
assert len(branch_rules) == 1
assert branch_rules[0].after.name == "check_inventory"
assert branch_rules[0].when_true.name == "process_order"
assert branch_rules[0].when_false.name == "backorder"
print()


# Test 5: WorkflowValidator - valid workflow
print("=" * 70)
print("Test 5: WorkflowValidator - valid workflow")
print("=" * 70)

validator = WorkflowValidator(
    workflow_name="valid_workflow",
    timeline=[step1, step2, step3],
    diverge_rules=[],
    branch_rules=[]
)

report = validator.validate()
print(f"✓ Validation result: is_valid={report.is_valid}")
print(f"  - Errors: {len(report.errors)}")
print(f"  - Warnings: {len(report.warnings)}")
assert report.is_valid
print()


# Test 6: WorkflowValidator - empty timeline error
print("=" * 70)
print("Test 6: WorkflowValidator - empty timeline error")
print("=" * 70)

validator2 = WorkflowValidator(
    workflow_name="empty_workflow",
    timeline=[],
    diverge_rules=[],
    branch_rules=[]
)

report2 = validator2.validate()
print(f"✓ Validation result: is_valid={report2.is_valid}")
print(f"  - Errors: {report2.errors}")
assert not report2.is_valid
assert len(report2.errors) > 0
assert "empty timeline" in report2.errors[0].lower()
print()


# Test 7: WorkflowValidator - circular dependency error
print("=" * 70)
print("Test 7: WorkflowValidator - circular dependency error")
print("=" * 70)

# Clear registry
StepRegistry._steps = {}

@step
async def cycle_a(context: Context, cycle_c: dict):
    return {"ok": "a"}

@step
async def cycle_b(context: Context, cycle_a: dict):
    return {"ok": "b"}

@step
async def cycle_c(context: Context, cycle_b: dict):
    return {"ok": "c"}

validator3 = WorkflowValidator(
    workflow_name="circular_workflow",
    timeline=[cycle_a, cycle_b, cycle_c],
    diverge_rules=[],
    branch_rules=[]
)

report3 = validator3.validate()
print(f"✓ Validation result: is_valid={report3.is_valid}")
print(f"  - Errors: {report3.errors}")
assert not report3.is_valid
assert len(report3.errors) > 0
assert "circular dependency" in report3.errors[0].lower()
print()


# Test 8: @workflow decorator integration
print("=" * 70)
print("Test 8: @workflow decorator integration")
print("=" * 70)

# Clear registries
StepRegistry._steps = {}
WorkflowRegistry._workflows = {}

@step
async def fetch_data(context: Context, inputs: dict):
    return {"ok": "data"}

@step
async def process_data(context: Context, fetch_data: dict):
    return {"ok": "processed"}

@workflow
def simple_workflow(wf):
    """Simple workflow using DSL."""
    wf.timeline(fetch_data >> process_data)

print(f"✓ Created workflow: {simple_workflow.name}")
print(f"  - Registered: {WorkflowRegistry.get('simple_workflow') is not None}")

# Validate the workflow explicitly
report4 = simple_workflow.validate()
print(f"✓ Validation result: is_valid={report4.is_valid}")
print(f"  - Errors: {len(report4.errors)}")
print(f"  - Warnings: {len(report4.warnings)}")
assert report4.is_valid
print()


# Test 9: @workflow decorator with validation error
print("=" * 70)
print("Test 9: @workflow decorator with validation error")
print("=" * 70)

# Clear registries
StepRegistry._steps = {}
WorkflowRegistry._workflows = {}

try:
    @workflow
    def invalid_workflow(wf):
        """Invalid workflow - empty timeline."""
        pass  # No timeline defined!

    # This should raise WorkflowDefinitionError when we try to validate/execute
    report5 = invalid_workflow.validate()
    print(f"  ✗ ERROR: Should have raised WorkflowDefinitionError for empty timeline!")
    assert False
except Exception as e:
    print(f"  ✓ Correctly raised {type(e).__name__}: {str(e)[:80]}...")
    assert "empty timeline" in str(e).lower() or "timeline" in str(e).lower()
print()


# Test 10: WorkflowValidator - diverge rule validation
print("=" * 70)
print("Test 10: WorkflowValidator - diverge rule validation")
print("=" * 70)

# Clear registries
StepRegistry._steps = {}

@step
async def step_a(context: Context, inputs: dict):
    return {"ok": "a"}

@step
async def step_b(context: Context, step_a: dict):
    return {"ok": "b"}

@step
async def step_c(context: Context, step_a: dict):
    return {"ok": "c"}

# Invalid: from_step not in timeline
diverge_rule = DivergeRule(
    from_step=step_b,  # step_b not in timeline
    patterns={"x": step_c}
)

validator4 = WorkflowValidator(
    workflow_name="invalid_diverge",
    timeline=[step_a],  # Only step_a in timeline
    diverge_rules=[diverge_rule],
    branch_rules=[]
)

report6 = validator4.validate()
print(f"✓ Validation result: is_valid={report6.is_valid}")
print(f"  - Errors: {report6.errors}")
assert not report6.is_valid
assert "not found in timeline" in report6.errors[0]
print()


# Test 11: WorkflowValidator - branch rule validation
print("=" * 70)
print("Test 11: WorkflowValidator - branch rule validation")
print("=" * 70)

# Invalid: after step not in timeline
branch_rule = BranchRule(
    after=step_b,  # step_b not in timeline
    condition=lambda x: True,
    when_true=step_c,
    when_false=step_a
)

validator5 = WorkflowValidator(
    workflow_name="invalid_branch",
    timeline=[step_a],  # Only step_a in timeline
    diverge_rules=[],
    branch_rules=[branch_rule]
)

report7 = validator5.validate()
print(f"✓ Validation result: is_valid={report7.is_valid}")
print(f"  - Errors: {report7.errors}")
assert not report7.is_valid
assert "not found in timeline" in report7.errors[0]
print()


# Test 12: WorkflowValidator - parameter signature validation
print("=" * 70)
print("Test 12: WorkflowValidator - parameter signature validation")
print("=" * 70)

# Clear registries
StepRegistry._steps = {}

@step
async def valid_step_sig(context: Context, inputs: dict):
    return {"ok": "valid"}

@step
async def invalid_dep(context: Context, nonexistent_step: dict):
    return {"ok": "invalid"}

validator6 = WorkflowValidator(
    workflow_name="invalid_signature",
    timeline=[valid_step_sig, invalid_dep],
    diverge_rules=[],
    branch_rules=[]
)

report8 = validator6.validate()
print(f"✓ Validation result: is_valid={report8.is_valid}")
print(f"  - Errors: {report8.errors}")
assert not report8.is_valid
# Should detect that nonexistent_step doesn't exist
print()


# Test 13: ValidationReport add_error and add_warning
print("=" * 70)
print("Test 13: ValidationReport methods")
print("=" * 70)

report9 = ValidationReport()
assert report9.is_valid  # No errors initially

report9.add_error("Test error 1")
report9.add_error("Test error 2")
report9.add_warning("Test warning 1")

print(f"✓ ValidationReport:")
print(f"  - Errors: {len(report9.errors)}")
print(f"  - Warnings: {len(report9.warnings)}")
print(f"  - is_valid: {report9.is_valid}")

assert len(report9.errors) == 2
assert len(report9.warnings) == 1
assert not report9.is_valid  # Has errors
print()


# Test 14: Complex workflow with timeline, diverge, and branch
print("=" * 70)
print("Test 14: Complex workflow with all constructs")
print("=" * 70)

# Clear registries
StepRegistry._steps = {}
WorkflowRegistry._workflows = {}

@step
async def init_order(context: Context, inputs: dict):
    return {"ok": {"user_type": "premium", "in_stock": True}}

@step
async def validate_order(context: Context, init_order: dict):
    return {"ok": "validated"}

@step
async def premium_pricing(context: Context, validate_order: dict):
    return {"ok": "premium_price"}

@step
async def standard_pricing(context: Context, validate_order: dict):
    return {"ok": "standard_price"}

@step
async def ship_immediately(context: Context, validate_order: dict):
    return {"ok": "shipped"}

@step
async def schedule_backorder(context: Context, validate_order: dict):
    return {"ok": "scheduled"}

@workflow
def complex_workflow(wf):
    """Complex workflow with timeline, diverge, and branch."""
    wf.timeline(init_order >> validate_order)
    wf.diverge(validate_order, {
        "premium": premium_pricing,
        "standard": standard_pricing
    })
    wf.branch(
        after=validate_order,
        condition=lambda out: out.get("in_stock", False),
        when_true=ship_immediately,
        when_false=schedule_backorder
    )

print(f"✓ Created complex workflow: {complex_workflow.name}")

# Validate
report10 = complex_workflow.validate()
print(f"✓ Validation result: is_valid={report10.is_valid}")
print(f"  - Errors: {len(report10.errors)}")
print(f"  - Warnings: {len(report10.warnings)}")

if report10.warnings:
    print(f"  - Warnings details:")
    for warning in report10.warnings:
        print(f"    • {warning}")

# Should be valid (warnings are ok)
assert report10.is_valid
print()


# Summary
print("=" * 70)
print("PHASE 3 SMOKE TEST SUMMARY")
print("=" * 70)
print("✅ All tests passed!")
print()
print("Implemented features:")
print("  ✓ WorkflowBuilder with timeline(), diverge(), branch()")
print("  ✓ DivergeRule and BranchRule classes")
print("  ✓ WorkflowValidator with 7 validation checks:")
print("    1. Timeline completeness")
print("    2. Dependency integrity (missing deps, cycles)")
print("    3. Diverge rule validation")
print("    4. Branch rule validation")
print("    5. Parameter signature validation")
print("    6. Execution readiness")
print("    7. Unreachable step detection")
print("  ✓ ValidationReport with errors and warnings")
print("  ✓ Integration with @workflow decorator")
print("  ✓ Automatic validation at build time")
print("  ✓ Error handling for invalid workflows")
print()
print("Next: Phase 4 - Protobuf Serialization")
print("=" * 70)

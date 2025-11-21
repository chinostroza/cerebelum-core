#!/usr/bin/env python3
"""Smoke test for Phase 4 implementation.

This script tests the serialization functionality:
- DSLSerializer converting DSL to WorkflowDefinition
- Timeline serialization
- Diverge rule serialization
- Branch rule serialization
- Integration with BlueprintSerializer
- JSON serialization
- Workflow hash computation
"""

import json
from cerebelum import (
    step,
    workflow,
    Context,
    StepRegistry,
    WorkflowRegistry,
    DSLSerializer,
    BlueprintSerializer,
)
from cerebelum.dsl import (
    WorkflowBuilder,
)

# Clear registries for clean test
StepRegistry._steps = {}
WorkflowRegistry._workflows = {}

print("=" * 70)
print("PHASE 4: SERIALIZATION - SMOKE TEST")
print("=" * 70)
print()


# Test 1: Basic timeline serialization
print("=" * 70)
print("Test 1: Basic timeline serialization")
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

# Convert to WorkflowDefinition
definition = DSLSerializer.to_workflow_definition("test_workflow", builder)

print(f"✓ Converted to WorkflowDefinition")
print(f"  - ID: {definition.id}")
print(f"  - Timeline: {definition.timeline}")
print(f"  - Steps metadata count: {len(definition.steps_metadata)}")

assert definition.id == "test_workflow"
assert definition.timeline == ["step1", "step2", "step3"]
assert len(definition.steps_metadata) == 3
assert "step1" in definition.steps_metadata
assert "step2" in definition.steps_metadata
assert "step3" in definition.steps_metadata

# Check dependencies (DSL StepMetadata uses 'dependencies', not 'depends_on')
assert definition.steps_metadata["step1"].dependencies == []
assert definition.steps_metadata["step2"].dependencies == ["step1"]
assert definition.steps_metadata["step3"].dependencies == ["step2"]
print(f"  ✓ Dependencies correctly extracted")
print()


# Test 2: JSON serialization
print("=" * 70)
print("Test 2: JSON serialization")
print("=" * 70)

json_str = DSLSerializer.serialize_to_json("test_workflow", builder)
print(f"✓ Serialized to JSON ({len(json_str)} bytes)")

# Parse JSON to verify structure
blueprint = json.loads(json_str)
print(f"  - Workflow module: {blueprint['workflow_module']}")
print(f"  - Language: {blueprint['language']}")
print(f"  - Version (hash): {blueprint['version'][:16]}...")

assert blueprint["workflow_module"] == "test_workflow"
assert blueprint["language"] == "python"
assert "definition" in blueprint
assert "timeline" in blueprint["definition"]
assert len(blueprint["definition"]["timeline"]) == 3
print(f"  ✓ JSON structure is correct")
print()


# Test 3: Dictionary serialization
print("=" * 70)
print("Test 3: Dictionary serialization")
print("=" * 70)

blueprint_dict = DSLSerializer.serialize_to_dict("test_workflow", builder)
print(f"✓ Serialized to dict")
print(f"  - Keys: {list(blueprint_dict.keys())}")
print(f"  - Timeline length: {len(blueprint_dict['definition']['timeline'])}")

assert "workflow_module" in blueprint_dict
assert "definition" in blueprint_dict
assert "version" in blueprint_dict
assert blueprint_dict["definition"]["timeline"][0]["name"] == "step1"
print(f"  ✓ Dictionary structure is correct")
print()


# Test 4: Diverge rule serialization
print("=" * 70)
print("Test 4: Diverge rule serialization")
print("=" * 70)

# Clear registry
StepRegistry._steps = {}

@step
async def check_user(context: Context, inputs: dict):
    return {"ok": "premium"}

@step
async def premium_flow(context: Context, check_user: dict):
    return {"ok": "premium_result"}

@step
async def standard_flow(context: Context, check_user: dict):
    return {"ok": "standard_result"}

builder2 = WorkflowBuilder("diverge_workflow")
builder2.timeline(check_user)
builder2.diverge(check_user, {
    "premium": premium_flow,
    "standard": standard_flow
})

definition2 = DSLSerializer.to_workflow_definition("diverge_workflow", builder2)

print(f"✓ Converted workflow with diverge rule")
print(f"  - Diverge rules count: {len(definition2.diverge_rules)}")

assert len(definition2.diverge_rules) == 1
diverge_rule = definition2.diverge_rules[0]
print(f"  - From step: {diverge_rule.from_step}")
print(f"  - Patterns count: {len(diverge_rule.patterns)}")

assert diverge_rule.from_step == "check_user"
assert len(diverge_rule.patterns) == 2

# Check patterns
pattern_keys = [p.pattern for p in diverge_rule.patterns]
pattern_targets = [p.target for p in diverge_rule.patterns]
print(f"  - Pattern keys: {pattern_keys}")
print(f"  - Pattern targets: {pattern_targets}")

assert "premium" in pattern_keys
assert "standard" in pattern_keys
assert "premium_flow" in pattern_targets
assert "standard_flow" in pattern_targets
print(f"  ✓ Diverge rule serialized correctly")
print()


# Test 5: Branch rule serialization
print("=" * 70)
print("Test 5: Branch rule serialization")
print("=" * 70)

# Clear registry
StepRegistry._steps = {}

@step
async def check_inventory(context: Context, inputs: dict):
    return {"ok": {"in_stock": True}}

@step
async def process_order(context: Context, check_inventory: dict):
    return {"ok": "order_processed"}

@step
async def backorder(context: Context, check_inventory: dict):
    return {"ok": "backordered"}

builder3 = WorkflowBuilder("branch_workflow")
builder3.timeline(check_inventory)
builder3.branch(
    after=check_inventory,
    condition=lambda out: out.get("in_stock", False),
    when_true=process_order,
    when_false=backorder
)

definition3 = DSLSerializer.to_workflow_definition("branch_workflow", builder3)

print(f"✓ Converted workflow with branch rule")
print(f"  - Branch rules count: {len(definition3.branch_rules)}")

assert len(definition3.branch_rules) == 1
branch_rule = definition3.branch_rules[0]
print(f"  - From step: {branch_rule.from_step}")
print(f"  - Branches count: {len(branch_rule.branches)}")

assert branch_rule.from_step == "check_inventory"
assert len(branch_rule.branches) == 2

# Check branches
print(f"  - Branch 0 target: {branch_rule.branches[0].action.target_step}")
print(f"  - Branch 1 target: {branch_rule.branches[1].action.target_step}")

assert branch_rule.branches[0].action.target_step == "process_order"
assert branch_rule.branches[1].action.target_step == "backorder"
print(f"  ✓ Branch rule serialized correctly")
print()


# Test 6: Complex workflow serialization
print("=" * 70)
print("Test 6: Complex workflow with all constructs")
print("=" * 70)

# Clear registry
StepRegistry._steps = {}

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

builder4 = WorkflowBuilder("complex_workflow")
builder4.timeline(init_order >> validate_order)
builder4.diverge(validate_order, {
    "premium": premium_pricing,
    "standard": standard_pricing
})
builder4.branch(
    after=validate_order,
    condition=lambda out: out.get("in_stock", False),
    when_true=ship_immediately,
    when_false=schedule_backorder
)

definition4 = DSLSerializer.to_workflow_definition("complex_workflow", builder4)

print(f"✓ Converted complex workflow")
print(f"  - Timeline length: {len(definition4.timeline)}")
print(f"  - Steps metadata count: {len(definition4.steps_metadata)}")
print(f"  - Diverge rules: {len(definition4.diverge_rules)}")
print(f"  - Branch rules: {len(definition4.branch_rules)}")

assert len(definition4.timeline) == 2
assert len(definition4.steps_metadata) == 6  # All steps collected
assert len(definition4.diverge_rules) == 1
assert len(definition4.branch_rules) == 1

# Verify all steps are in metadata
expected_steps = ["init_order", "validate_order", "premium_pricing",
                  "standard_pricing", "ship_immediately", "schedule_backorder"]
for step_name in expected_steps:
    assert step_name in definition4.steps_metadata, f"Missing step: {step_name}"

print(f"  ✓ All steps collected: {list(definition4.steps_metadata.keys())}")
print()


# Test 7: Integration with @workflow decorator
print("=" * 70)
print("Test 7: Integration with @workflow decorator")
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

# Trigger build (which also serializes)
report = simple_workflow.validate()
print(f"✓ Workflow built and validated")

# Check that _built_definition is a WorkflowDefinition
assert simple_workflow._built_definition is not None
assert hasattr(simple_workflow._built_definition, "timeline")
assert hasattr(simple_workflow._built_definition, "steps_metadata")
print(f"  - Built definition type: {type(simple_workflow._built_definition).__name__}")
print(f"  - Timeline: {simple_workflow._built_definition.timeline}")
print(f"  ✓ WorkflowDefinition created automatically")
print()


# Test 8: Hash computation for versioning
print("=" * 70)
print("Test 8: Workflow hash computation")
print("=" * 70)

hash1 = BlueprintSerializer.compute_hash(definition)
hash2 = BlueprintSerializer.compute_hash(definition)
print(f"✓ Computed hashes")
print(f"  - Hash 1: {hash1[:32]}...")
print(f"  - Hash 2: {hash2[:32]}...")

assert hash1 == hash2, "Hash should be deterministic"
print(f"  ✓ Hash is deterministic")

# Different workflow should have different hash
hash3 = BlueprintSerializer.compute_hash(definition2)
print(f"  - Hash 3 (different workflow): {hash3[:32]}...")
assert hash1 != hash3, "Different workflows should have different hashes"
print(f"  ✓ Different workflows have different hashes")
print()


# Test 9: JSON roundtrip
print("=" * 70)
print("Test 9: JSON serialization roundtrip")
print("=" * 70)

# Serialize to JSON
json_str = BlueprintSerializer.to_json(definition)
print(f"✓ Serialized to JSON")

# Deserialize
blueprint_dict = BlueprintSerializer.from_json(json_str)
print(f"✓ Deserialized from JSON")
print(f"  - Workflow module: {blueprint_dict['workflow_module']}")
print(f"  - Timeline length: {len(blueprint_dict['definition']['timeline'])}")

assert blueprint_dict["workflow_module"] == "test_workflow"
assert len(blueprint_dict["definition"]["timeline"]) == 3
print(f"  ✓ Roundtrip successful")
print()


# Test 10: Step composition in diverge
print("=" * 70)
print("Test 10: Step composition in diverge patterns")
print("=" * 70)

# Clear registry
StepRegistry._steps = {}

@step
async def step_a(context: Context, inputs: dict):
    return {"ok": "a"}

@step
async def step_b(context: Context, step_a: dict):
    return {"ok": "b"}

@step
async def step_c(context: Context, step_b: dict):
    return {"ok": "c"}

@step
async def step_d(context: Context, step_a: dict):
    return {"ok": "d"}

builder5 = WorkflowBuilder("composition_workflow")
builder5.timeline(step_a)
builder5.diverge(step_a, {
    "path1": step_b >> step_c,  # Composition
    "path2": step_d  # Single step
})

definition5 = DSLSerializer.to_workflow_definition("composition_workflow", builder5)

print(f"✓ Converted workflow with composition in diverge")
print(f"  - Timeline: {definition5.timeline}")
print(f"  - Steps metadata: {list(definition5.steps_metadata.keys())}")

# All steps should be collected
assert len(definition5.steps_metadata) == 4
assert "step_a" in definition5.steps_metadata
assert "step_b" in definition5.steps_metadata
assert "step_c" in definition5.steps_metadata
assert "step_d" in definition5.steps_metadata

# Diverge rule should point to first step of composition
diverge = definition5.diverge_rules[0]
targets = [p.target for p in diverge.patterns]
print(f"  - Diverge targets: {targets}")
assert "step_b" in targets  # First step of composition
assert "step_d" in targets
print(f"  ✓ Composition handled correctly")
print()


# Summary
print("=" * 70)
print("PHASE 4 SMOKE TEST SUMMARY")
print("=" * 70)
print("✅ All tests passed!")
print()
print("Implemented features:")
print("  ✓ DSLSerializer.to_workflow_definition()")
print("  ✓ Timeline serialization with dependency extraction")
print("  ✓ Diverge rule serialization")
print("  ✓ Branch rule serialization (with lambda functions)")
print("  ✓ Step composition handling in diverge patterns")
print("  ✓ Integration with BlueprintSerializer")
print("  ✓ JSON serialization and deserialization")
print("  ✓ Workflow hash computation for versioning")
print("  ✓ Automatic serialization in @workflow decorator")
print("  ✓ Complex workflows with all constructs")
print()
print("Next: Phase 5 - Execution Integration")
print("=" * 70)

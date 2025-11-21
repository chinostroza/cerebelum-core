#!/usr/bin/env python3
"""Smoke test for Phase 2 implementation.

This script tests the dependency analysis functionality:
- DependencyGraph construction
- Cycle detection using DFS
- Topological sort using Kahn's algorithm
- Parallel group detection
- Integration with Phase 1 (@step decorators)
- Error handling for missing and circular dependencies
"""

from cerebelum import (
    step,
    Context,
    StepRegistry,
)
from cerebelum.dsl import (
    DependencyAnalyzer,
    DependencyGraph,
    DependencyNode,
)

# Clear registry for clean test
StepRegistry._steps = {}

print("=" * 70)
print("PHASE 2: DEPENDENCY ANALYSIS - SMOKE TEST")
print("=" * 70)
print()


# Test 1: Basic dependency graph construction
print("=" * 70)
print("Test 1: Basic DependencyGraph construction")
print("=" * 70)

@step
async def step_a(context: Context, inputs: dict):
    return {"ok": "a_result"}

@step
async def step_b(context: Context, step_a: dict):
    return {"ok": "b_result"}

@step
async def step_c(context: Context, step_b: dict):
    return {"ok": "c_result"}

graph = DependencyGraph()
graph.add_step(step_a)
graph.add_step(step_b)
graph.add_step(step_c)
graph.build_edges()

print(f"✓ Created graph with {len(graph.nodes)} nodes")
print(f"  - step_a dependencies: {graph.nodes['step_a'].dependencies}")
print(f"  - step_b dependencies: {graph.nodes['step_b'].dependencies}")
print(f"  - step_c dependencies: {graph.nodes['step_c'].dependencies}")
print(f"  - step_a dependents: {graph.nodes['step_a'].dependents}")
print(f"  - step_b dependents: {graph.nodes['step_b'].dependents}")
print()


# Test 2: Topological sort (linear chain)
print("=" * 70)
print("Test 2: Topological sort (linear chain: a -> b -> c)")
print("=" * 70)

sorted_steps = graph.topological_sort()
print(f"✓ Topological order: {sorted_steps}")

# Verify order
expected = ['step_a', 'step_b', 'step_c']
assert sorted_steps == expected, f"Expected {expected}, got {sorted_steps}"
print(f"  ✓ Order is correct (dependencies come before dependents)")
print()


# Test 3: Parallel execution detection
print("=" * 70)
print("Test 3: Parallel group detection")
print("=" * 70)

# Clear registry
StepRegistry._steps = {}

@step
async def order(context: Context, inputs: dict):
    return {"ok": "order_data"}

@step
async def send_email(context: Context, order: dict):
    return {"ok": "email_sent"}

@step
async def send_sms(context: Context, order: dict):
    return {"ok": "sms_sent"}

@step
async def update_inventory(context: Context, order: dict):
    return {"ok": "inventory_updated"}

@step
async def generate_report(context: Context, send_email: dict, send_sms: dict, update_inventory: dict):
    return {"ok": "report_generated"}

graph2 = DependencyGraph()
graph2.add_step(order)
graph2.add_step(send_email)
graph2.add_step(send_sms)
graph2.add_step(update_inventory)
graph2.add_step(generate_report)
graph2.build_edges()

parallel_groups = graph2.find_parallel_groups()
print(f"✓ Found {len(parallel_groups)} parallel group(s)")
for i, group in enumerate(parallel_groups, 1):
    print(f"  - Group {i}: {group}")

# Verify parallel group
expected_parallel = {'send_email', 'send_sms', 'update_inventory'}
assert len(parallel_groups) == 1, f"Expected 1 parallel group, got {len(parallel_groups)}"
assert parallel_groups[0] == expected_parallel, f"Expected {expected_parallel}, got {parallel_groups[0]}"
print(f"  ✓ Correctly identified parallel steps (all depend only on 'order')")
print()


# Test 4: Topological sort with parallelism
print("=" * 70)
print("Test 4: Topological sort with parallel groups")
print("=" * 70)

sorted_steps2 = graph2.topological_sort()
print(f"✓ Topological order: {sorted_steps2}")

# Verify order constraints
assert sorted_steps2[0] == 'order', "order should be first"
assert sorted_steps2[-1] == 'generate_report', "generate_report should be last"
# The middle three can be in any order (they're parallel)
middle = sorted_steps2[1:4]
assert set(middle) == expected_parallel, f"Middle steps should be {expected_parallel}"
print(f"  ✓ Order respects dependencies")
print(f"  ✓ Parallel steps can execute in any order")
print()


# Test 5: Cycle detection
print("=" * 70)
print("Test 5: Cycle detection")
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

graph3 = DependencyGraph()
graph3.add_step(cycle_a)
graph3.add_step(cycle_b)
graph3.add_step(cycle_c)
graph3.build_edges()

cycle = graph3.detect_cycles()
print(f"✓ Cycle detected: {cycle}")
assert cycle is not None, "Should detect cycle"
assert len(cycle) == 4, f"Cycle should have 4 elements (3 steps + return to start), got {len(cycle)}"
assert cycle[0] == cycle[-1], "Cycle should start and end with same step"
print(f"  ✓ Cycle: {' -> '.join(cycle)}")
print()


# Test 6: Topological sort fails on cycle
print("=" * 70)
print("Test 6: Topological sort raises error on cycle")
print("=" * 70)

try:
    graph3.topological_sort()
    print("  ✗ ERROR: Should have raised ValueError for circular dependency!")
    assert False, "Should have raised ValueError"
except ValueError as e:
    print(f"  ✓ Correctly raised ValueError: {e}")
print()


# Test 7: Missing dependency detection
print("=" * 70)
print("Test 7: Missing dependency detection")
print("=" * 70)

# Clear registry
StepRegistry._steps = {}

@step
async def valid_step(context: Context, inputs: dict):
    return {"ok": "valid"}

@step
async def invalid_step(context: Context, missing_step: dict):
    return {"ok": "invalid"}

graph4 = DependencyGraph()
graph4.add_step(valid_step)
graph4.add_step(invalid_step)

try:
    graph4.build_edges()
    print("  ✗ ERROR: Should have raised ValueError for missing dependency!")
    assert False, "Should have raised ValueError"
except ValueError as e:
    print(f"  ✓ Correctly raised ValueError: {e}")
    assert "missing_step" in str(e), "Error should mention missing step"
    assert "invalid_step" in str(e), "Error should mention step with missing dependency"
print()


# Test 8: DependencyAnalyzer.analyze()
print("=" * 70)
print("Test 8: DependencyAnalyzer.analyze()")
print("=" * 70)

# Clear registry
StepRegistry._steps = {}

@step
async def fetch_user(context: Context, inputs: dict):
    return {"ok": "user_data"}

@step
async def validate_user(context: Context, fetch_user: dict):
    return {"ok": "validated"}

@step
async def process_payment(context: Context, validate_user: dict):
    return {"ok": "payment_processed"}

timeline = [fetch_user, validate_user, process_payment]
graph5 = DependencyAnalyzer.analyze(timeline=timeline)

print(f"✓ DependencyAnalyzer created graph with {len(graph5.nodes)} nodes")
print(f"  - Nodes: {list(graph5.nodes.keys())}")

sorted_steps3 = graph5.topological_sort()
print(f"✓ Topological order: {sorted_steps3}")
assert sorted_steps3 == ['fetch_user', 'validate_user', 'process_payment']
print(f"  ✓ Order is correct")
print()


# Test 9: No cycles in acyclic graph
print("=" * 70)
print("Test 9: Cycle detection returns None for acyclic graph")
print("=" * 70)

cycle5 = graph5.detect_cycles()
print(f"✓ Cycle detection result: {cycle5}")
assert cycle5 is None, "Should return None for acyclic graph"
print(f"  ✓ Correctly identified no cycles")
print()


# Test 10: Complex parallel detection
print("=" * 70)
print("Test 10: Complex parallel group detection")
print("=" * 70)

# Clear registry
StepRegistry._steps = {}

@step
async def init(context: Context, inputs: dict):
    return {"ok": "init"}

@step
async def parallel_1a(context: Context, init: dict):
    return {"ok": "p1a"}

@step
async def parallel_1b(context: Context, init: dict):
    return {"ok": "p1b"}

@step
async def parallel_2a(context: Context, parallel_1a: dict, parallel_1b: dict):
    return {"ok": "p2a"}

@step
async def parallel_2b(context: Context, parallel_1a: dict, parallel_1b: dict):
    return {"ok": "p2b"}

@step
async def final(context: Context, parallel_2a: dict, parallel_2b: dict):
    return {"ok": "final"}

graph6 = DependencyGraph()
for s in [init, parallel_1a, parallel_1b, parallel_2a, parallel_2b, final]:
    graph6.add_step(s)
graph6.build_edges()

parallel_groups6 = graph6.find_parallel_groups()
print(f"✓ Found {len(parallel_groups6)} parallel group(s)")
for i, group in enumerate(parallel_groups6, 1):
    print(f"  - Group {i}: {sorted(group)}")

# Verify two parallel groups
assert len(parallel_groups6) == 2, f"Expected 2 parallel groups, got {len(parallel_groups6)}"

# Group 1: parallel_1a, parallel_1b (both depend only on init)
group1 = {'parallel_1a', 'parallel_1b'}
# Group 2: parallel_2a, parallel_2b (both depend on parallel_1a and parallel_1b)
group2 = {'parallel_2a', 'parallel_2b'}

assert group1 in parallel_groups6, f"Expected group {group1}"
assert group2 in parallel_groups6, f"Expected group {group2}"
print(f"  ✓ Correctly identified two levels of parallelism")
print()


# Test 11: Topological sort determinism
print("=" * 70)
print("Test 11: Topological sort is deterministic")
print("=" * 70)

# Run topological sort multiple times
results = [graph6.topological_sort() for _ in range(5)]
print(f"✓ Ran topological sort 5 times")
print(f"  - Result: {results[0]}")

# All results should be identical
assert all(r == results[0] for r in results), "Results should be deterministic"
print(f"  ✓ All results are identical (deterministic)")
print()


# Summary
print("=" * 70)
print("PHASE 2 SMOKE TEST SUMMARY")
print("=" * 70)
print("✅ All tests passed!")
print()
print("Implemented features:")
print("  ✓ DependencyGraph construction")
print("  ✓ Cycle detection using DFS (O(V+E))")
print("  ✓ Topological sort using Kahn's algorithm (O(V+E))")
print("  ✓ Parallel group detection (O(V))")
print("  ✓ DependencyAnalyzer.analyze()")
print("  ✓ Error handling (missing dependencies, circular dependencies)")
print("  ✓ Deterministic topological ordering")
print("  ✓ Integration with Phase 1 (@step decorators)")
print()
print("Next: Phase 3 - Workflow Builder and Validation")
print("=" * 70)

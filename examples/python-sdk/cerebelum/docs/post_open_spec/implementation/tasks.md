# Implementation Tasks - Cerebelum Python DSL

## Document Information

**Version:** 1.0
**Status:** Ready for Implementation
**Last Updated:** 2025-11-20
**Based On:**
- Requirements Document v1.0
- Design Document v1.0

---

## Overview

This document provides a detailed breakdown of implementation tasks for the Cerebelum Python DSL. Tasks are organized by implementation phase and include specific deliverables, testing requirements, and requirement traceability.

**Total Estimated Tasks:** 93
**Implementation Phases:** 6

---

## Table of Contents

1. [Phase 1: Core Decorators and Composition](#phase-1-core-decorators-and-composition)
2. [Phase 2: Dependency Analysis](#phase-2-dependency-analysis)
3. [Phase 3: Workflow Builder and Validation](#phase-3-workflow-builder-and-validation)
4. [Phase 4: Protobuf Serialization](#phase-4-protobuf-serialization)
5. [Phase 5: Execution Integration](#phase-5-execution-integration)
6. [Phase 6: Error Handling and Polish](#phase-6-error-handling-and-polish)

---

## Phase 1: Core Decorators and Composition

**Goal:** Implement `@step` and `@workflow` decorators with composition operator

**Dependencies:** None

**Requirements Covered:** Req 1, Req 2, Req 3

### 1. Setup Project Structure

- [ ] 1.1 Create `cerebelum/dsl/` directory structure
  - **Deliverable:** Directory with `__init__.py`, `decorators.py`, `composition.py`, `context.py`, `registry.py`
  - **Tests:** Directory structure exists

- [ ] 1.2 Create `cerebelum/dsl/__init__.py` with imports
  - **Deliverable:** Empty `__init__.py` ready for exports
  - **Tests:** Module imports without errors

- [ ] 1.3 Update root `cerebelum/__init__.py` skeleton
  - **Deliverable:** Root init file with placeholder imports
  - **Tests:** Package imports correctly

### 2. Implement Step Metadata

- [ ] 2.1 Create `StepMetadata` dataclass in `decorators.py`
  - **Deliverable:** `StepMetadata` class with fields: `name`, `function`, `parameters`, `has_context`, `has_inputs`, `dependencies`
  - **Req:** Req 1 (Step Decorator)
  - **Tests:** Unit test for StepMetadata instantiation

- [ ] 2.2 Implement `__rshift__` method on `StepMetadata`
  - **Deliverable:** `>>` operator creates `StepComposition`
  - **Req:** Req 3 (Sequential Composition)
  - **Tests:** Test `step1 >> step2` creates composition

### 3. Implement StepComposition

- [ ] 3.1 Create `StepComposition` class in `composition.py`
  - **Deliverable:** `StepComposition` class with `steps` list
  - **Req:** Req 3 (Sequential Composition)
  - **Tests:** Unit test for StepComposition instantiation

- [ ] 3.2 Implement `__rshift__` on `StepComposition` for chaining
  - **Deliverable:** Chaining works: `a >> b >> c`
  - **Req:** Req 3
  - **Tests:** Test chaining 3+ steps

- [ ] 3.3 Add type checking for `>>` operator
  - **Deliverable:** Raise `TypeError` for invalid operands
  - **Req:** Req 3
  - **Tests:** Test error on invalid composition

### 4. Implement @step Decorator

- [ ] 4.1 Implement basic `step()` decorator function
  - **Deliverable:** Function that accepts async functions
  - **Req:** Req 1
  - **Tests:** Test decorator can be applied

- [ ] 4.2 Add async function validation
  - **Deliverable:** Raise `TypeError` if function is not async
  - **Req:** Req 1 (AC 2)
  - **Tests:** Test error for non-async function

- [ ] 4.3 Add context parameter validation
  - **Deliverable:** Check first param is 'context'
  - **Req:** Req 1 (AC 3)
  - **Tests:** Test error if context not first param

- [ ] 4.4 Extract function parameters using `inspect.signature`
  - **Deliverable:** Extract all parameter names
  - **Req:** Req 7 (Automatic Dependency Resolution)
  - **Tests:** Test parameter extraction

- [ ] 4.5 Identify dependencies (params excluding context/inputs)
  - **Deliverable:** `dependencies` list populated correctly
  - **Req:** Req 7 (AC 1)
  - **Tests:** Test dependency identification

- [ ] 4.6 Create and return `StepMetadata` instance
  - **Deliverable:** Decorated function returns `StepMetadata`
  - **Req:** Req 1
  - **Tests:** Test decorated function has metadata

- [ ] 4.7 Register step in `StepRegistry`
  - **Deliverable:** Step added to global registry
  - **Req:** Req 1
  - **Tests:** Test step appears in registry

### 5. Implement Step Registry

- [ ] 5.1 Create `StepRegistry` class in `registry.py`
  - **Deliverable:** Registry with `_steps` dict
  - **Tests:** Unit test for registry instantiation

- [ ] 5.2 Implement `register(step)` class method
  - **Deliverable:** Method to add steps to registry
  - **Tests:** Test step registration

- [ ] 5.3 Implement `get(name)` class method
  - **Deliverable:** Method to retrieve step by name
  - **Tests:** Test step retrieval

- [ ] 5.4 Implement `all()` class method
  - **Deliverable:** Method to get all steps
  - **Tests:** Test getting all steps

- [ ] 5.5 Implement `clear()` class method for testing
  - **Deliverable:** Method to reset registry
  - **Tests:** Test registry can be cleared

### 6. Implement @workflow Decorator

- [ ] 6.1 Create `WorkflowMetadata` class in `decorators.py`
  - **Deliverable:** Class with `name`, `definition_func`, `core_url` fields
  - **Req:** Req 2 (Workflow Decorator)
  - **Tests:** Unit test for WorkflowMetadata

- [ ] 6.2 Implement basic `workflow()` decorator function
  - **Deliverable:** Decorator that accepts regular functions
  - **Req:** Req 2
  - **Tests:** Test decorator can be applied

- [ ] 6.3 Add non-async validation
  - **Deliverable:** Raise `TypeError` if function is async
  - **Req:** Req 2 (AC 4)
  - **Tests:** Test error for async function

- [ ] 6.4 Support decorator with and without parameters
  - **Deliverable:** `@workflow` and `@workflow(core_url="...")` both work
  - **Req:** Req 2
  - **Tests:** Test both decorator forms

- [ ] 6.5 Implement `WorkflowMetadata.execute()` skeleton
  - **Deliverable:** Method signature defined (implementation later)
  - **Req:** Req 12 (Workflow Execution)
  - **Tests:** Method exists and can be called

- [ ] 6.6 Register workflow in `WorkflowRegistry`
  - **Deliverable:** Workflow added to global registry
  - **Tests:** Test workflow appears in registry

### 7. Implement Workflow Registry

- [ ] 7.1 Create `WorkflowRegistry` class in `registry.py`
  - **Deliverable:** Registry with `_workflows` dict
  - **Tests:** Unit test for registry

- [ ] 7.2 Implement registry methods (register, get, all, clear)
  - **Deliverable:** Same methods as StepRegistry
  - **Tests:** Test all registry operations

### 8. Implement Context Object

- [ ] 8.1 Create `Context` dataclass in `context.py`
  - **Deliverable:** Frozen dataclass with fields: `inputs`, `execution_id`, `workflow_name`, `step_name`, `attempt`
  - **Req:** Req 9 (Context Object)
  - **Tests:** Unit test for Context creation

- [ ] 8.2 Make Context read-only (frozen=True)
  - **Deliverable:** Cannot modify context after creation
  - **Req:** Req 9 (AC 2, 3)
  - **Tests:** Test `AttributeError` on modification

### 9. Phase 1 Testing

- [ ] 9.1 Write unit tests for `@step` decorator
  - **Deliverable:** Test coverage >90% for step decorator
  - **Tests:** 10+ test cases covering all requirements

- [ ] 9.2 Write unit tests for `@workflow` decorator
  - **Deliverable:** Test coverage >90% for workflow decorator
  - **Tests:** 8+ test cases

- [ ] 9.3 Write unit tests for `>>` operator
  - **Deliverable:** Test all composition scenarios
  - **Tests:** 6+ test cases

- [ ] 9.4 Write integration tests for decorator + registry
  - **Deliverable:** Test end-to-end decorator flow
  - **Tests:** 4+ integration tests

---

## Phase 2: Dependency Analysis

**Goal:** Implement dependency graph, cycle detection, and parallelism detection

**Dependencies:** Phase 1

**Requirements Covered:** Req 7, Req 8, Req 10

### 10. Implement Dependency Graph Data Structures

- [ ] 10.1 Create `DependencyNode` dataclass in `analyzer.py`
  - **Deliverable:** Dataclass with `step`, `dependencies`, `dependents` fields
  - **Req:** Req 7
  - **Tests:** Unit test for node creation

- [ ] 10.2 Create `DependencyGraph` class
  - **Deliverable:** Class with `nodes` dict
  - **Req:** Req 7
  - **Tests:** Unit test for graph creation

### 11. Implement Dependency Graph Operations

- [ ] 11.1 Implement `add_step(step)` method
  - **Deliverable:** Add step to graph nodes
  - **Req:** Req 7
  - **Tests:** Test step addition

- [ ] 11.2 Implement `build_edges()` method
  - **Deliverable:** Create edges based on dependencies
  - **Req:** Req 7 (AC 1)
  - **Tests:** Test edge creation

- [ ] 11.3 Add validation for missing dependencies
  - **Deliverable:** Raise `ValueError` if dependency doesn't exist
  - **Req:** Req 7 (AC 6), Req 10 (AC 2)
  - **Tests:** Test error for missing dependency

### 12. Implement Cycle Detection

- [ ] 12.1 Implement `detect_cycles()` using DFS
  - **Deliverable:** Method returns cycle path or None
  - **Req:** Req 7 (AC 7), Req 10 (AC 1)
  - **Tests:** Test cycle detection

- [ ] 12.2 Optimize DFS for performance (O(V+E))
  - **Deliverable:** Efficient cycle detection
  - **Req:** NFR-1 (Performance)
  - **Tests:** Benchmark with 100 steps

- [ ] 12.3 Format cycle error message
  - **Deliverable:** Clear cycle description: "a -> b -> c -> a"
  - **Req:** Req 10 (AC 1)
  - **Tests:** Test error message format

### 13. Implement Topological Sort

- [ ] 13.1 Implement `topological_sort()` using Kahn's algorithm
  - **Deliverable:** Return steps in dependency order
  - **Req:** Req 7
  - **Tests:** Test sort correctness

- [ ] 13.2 Check for cycles before sorting
  - **Deliverable:** Raise error if cycle detected
  - **Req:** Req 7 (AC 7)
  - **Tests:** Test error on cycle

- [ ] 13.3 Ensure deterministic ordering
  - **Deliverable:** Same input produces same output
  - **Req:** NFR-1
  - **Tests:** Test determinism

### 14. Implement Parallel Group Detection

- [ ] 14.1 Implement `find_parallel_groups()` method
  - **Deliverable:** Group steps by identical dependency sets
  - **Req:** Req 8 (Automatic Parallelism)
  - **Tests:** Test parallel grouping

- [ ] 14.2 Return only groups with 2+ steps
  - **Deliverable:** Filter single-step groups
  - **Req:** Req 8 (AC 1)
  - **Tests:** Test filtering

### 15. Implement Dependency Analyzer

- [ ] 15.1 Create `DependencyAnalyzer` class
  - **Deliverable:** Class with `analyze()` static method
  - **Req:** Req 7
  - **Tests:** Unit test for analyzer

- [ ] 15.2 Implement `analyze(timeline, diverge_rules, branch_rules)`
  - **Deliverable:** Build complete dependency graph
  - **Req:** Req 7, Req 8
  - **Tests:** Test with timeline only

- [ ] 15.3 Extract steps from diverge rule patterns
  - **Deliverable:** Include diverge targets in graph
  - **Req:** Req 5 (Diverge)
  - **Tests:** Test with diverge rules

- [ ] 15.4 Extract steps from branch rules
  - **Deliverable:** Include branch targets in graph
  - **Req:** Req 6 (Branch)
  - **Tests:** Test with branch rules

- [ ] 15.5 Validate graph completeness
  - **Deliverable:** All referenced steps exist
  - **Req:** Req 13 (Validation)
  - **Tests:** Test validation errors

### 16. Phase 2 Testing

- [ ] 16.1 Write unit tests for DependencyGraph
  - **Deliverable:** Test coverage >90%
  - **Tests:** 12+ test cases

- [ ] 16.2 Write unit tests for cycle detection
  - **Deliverable:** Test various cycle scenarios
  - **Tests:** 6+ test cases (simple, complex, self-loops)

- [ ] 16.3 Write unit tests for topological sort
  - **Deliverable:** Test ordering correctness
  - **Tests:** 8+ test cases

- [ ] 16.4 Write unit tests for parallel detection
  - **Deliverable:** Test grouping logic
  - **Tests:** 5+ test cases

- [ ] 16.5 Write performance benchmarks
  - **Deliverable:** Verify O(n log n) complexity
  - **Tests:** Benchmark with 50, 100, 200 steps

---

## Phase 3: Workflow Builder and Validation

**Goal:** Implement workflow builder API and comprehensive validation

**Dependencies:** Phase 1, Phase 2

**Requirements Covered:** Req 4, Req 5, Req 6, Req 13

### 17. Implement Workflow Builder Structure

- [ ] 17.1 Create `WorkflowBuilder` class in `builder.py`
  - **Deliverable:** Class with `workflow_id`, `_timeline`, `_diverge_rules`, `_branch_rules` fields
  - **Req:** Req 4 (Timeline)
  - **Tests:** Unit test for builder creation

- [ ] 17.2 Create `DivergeRule` dataclass
  - **Deliverable:** Dataclass with `from_step`, `patterns` fields
  - **Req:** Req 5 (Diverge)
  - **Tests:** Unit test for rule creation

- [ ] 17.3 Create `BranchRule` dataclass
  - **Deliverable:** Dataclass with `after`, `predicate`, `when_true`, `when_false` fields
  - **Req:** Req 6 (Branch)
  - **Tests:** Unit test for rule creation

### 18. Implement timeline() Method

- [ ] 18.1 Implement `timeline(composition)` method
  - **Deliverable:** Accept step or composition
  - **Req:** Req 4 (AC 1)
  - **Tests:** Test timeline registration

- [ ] 18.2 Add single-call validation
  - **Deliverable:** Raise `ValueError` if called twice
  - **Req:** Req 4 (AC 3)
  - **Tests:** Test error on multiple calls

- [ ] 18.3 Extract steps from composition
  - **Deliverable:** Helper method `_extract_steps()`
  - **Req:** Req 4
  - **Tests:** Test step extraction

### 19. Implement diverge() Method

- [ ] 19.1 Implement `diverge(from_step, patterns)` method
  - **Deliverable:** Register diverge rule
  - **Req:** Req 5 (AC 1)
  - **Tests:** Test diverge registration

- [ ] 19.2 Validate from_step is StepMetadata
  - **Deliverable:** Raise `TypeError` for invalid step
  - **Req:** Req 5 (AC 7)
  - **Tests:** Test type validation

- [ ] 19.3 Check for duplicate diverges
  - **Deliverable:** Raise `ValueError` for duplicate
  - **Req:** Req 5 (AC 8), Req 13
  - **Tests:** Test duplicate detection

- [ ] 19.4 Validate pattern targets exist
  - **Deliverable:** Check all pattern steps are valid
  - **Req:** Req 13
  - **Tests:** Test pattern validation

### 20. Implement branch() Method

- [ ] 20.1 Implement `branch(after, on, when_true, when_false)` method
  - **Deliverable:** Register branch rule
  - **Req:** Req 6 (AC 1)
  - **Tests:** Test branch registration

- [ ] 20.2 Validate predicate is callable
  - **Deliverable:** Raise `TypeError` for non-callable
  - **Req:** Req 6 (AC 6), Req 13
  - **Tests:** Test callable validation

- [ ] 20.3 Check for duplicate branches
  - **Deliverable:** Raise `ValueError` for duplicate
  - **Req:** Req 6 (AC 8), Req 13
  - **Tests:** Test duplicate detection

- [ ] 20.4 Validate when_true/when_false steps exist
  - **Deliverable:** Check target steps are valid
  - **Req:** Req 13
  - **Tests:** Test target validation

### 21. Implement Validation Engine

- [ ] 21.1 Create `ValidationErrorType` enum in `validator.py`
  - **Deliverable:** Enum with all error types
  - **Req:** Req 13
  - **Tests:** Unit test for enum

- [ ] 21.2 Create `ValidationError` dataclass
  - **Deliverable:** Dataclass with `type`, `message`, `step`, `suggestion` fields
  - **Req:** Req 13 (AC 5)
  - **Tests:** Unit test for error creation

- [ ] 21.3 Create `ValidationWarning` dataclass
  - **Deliverable:** Dataclass for warnings
  - **Req:** Req 13
  - **Tests:** Unit test for warning creation

- [ ] 21.4 Create `ValidationReport` dataclass
  - **Deliverable:** Dataclass with `valid`, `errors`, `warnings` fields
  - **Req:** Req 13 (AC 3)
  - **Tests:** Unit test for report

- [ ] 21.5 Implement `ValidationReport.raise_if_invalid()`
  - **Deliverable:** Method to raise on errors
  - **Req:** Req 13 (AC 2)
  - **Tests:** Test exception raising

- [ ] 21.6 Implement `ValidationReport.to_dict()`
  - **Deliverable:** Convert report to dict
  - **Req:** Req 13
  - **Tests:** Test dict conversion

### 22. Implement WorkflowValidator

- [ ] 22.1 Create `WorkflowValidator` class
  - **Deliverable:** Class with `validate()` method
  - **Req:** Req 13 (AC 1)
  - **Tests:** Unit test for validator

- [ ] 22.2 Implement `_validate_timeline_completeness()`
  - **Deliverable:** Check all timeline steps are StepMetadata
  - **Req:** Req 13 (Timeline Completeness)
  - **Tests:** Test invalid timeline step

- [ ] 22.3 Implement `_validate_dependency_integrity()`
  - **Deliverable:** Check dependencies exist, detect cycles
  - **Req:** Req 13 (Dependency Integrity)
  - **Tests:** Test missing dep, test cycle

- [ ] 22.4 Implement `_validate_diverge_rules()`
  - **Deliverable:** Validate diverge from_step, patterns, duplicates
  - **Req:** Req 13 (Diverge Validation)
  - **Tests:** Test all diverge validations

- [ ] 22.5 Implement `_validate_branch_rules()`
  - **Deliverable:** Validate branch after, predicate, targets, duplicates
  - **Req:** Req 13 (Branch Validation)
  - **Tests:** Test all branch validations

- [ ] 22.6 Implement `_validate_parameter_signatures()`
  - **Deliverable:** Check params match steps, first step has inputs
  - **Req:** Req 13 (Parameter Signature)
  - **Tests:** Test param validation

- [ ] 22.7 Implement `_validate_execution_readiness()`
  - **Deliverable:** Check workflow not empty
  - **Req:** Req 13 (Execution Readiness)
  - **Tests:** Test empty workflow

- [ ] 22.8 Implement `_check_unreachable_steps()`
  - **Deliverable:** Warn about unreachable steps
  - **Req:** Req 13
  - **Tests:** Test unreachable detection

- [ ] 22.9 Implement helper methods (`_all_steps()`, `_extract_steps_from_target()`)
  - **Deliverable:** Utility methods for validation
  - **Req:** Req 13
  - **Tests:** Test helper methods

### 23. Implement WorkflowBuilder.build()

- [ ] 23.1 Extract all steps from timeline
  - **Deliverable:** Collect all steps
  - **Req:** Req 4
  - **Tests:** Test step extraction

- [ ] 23.2 Call DependencyAnalyzer.analyze()
  - **Deliverable:** Build dependency graph
  - **Req:** Req 7
  - **Tests:** Test graph building

- [ ] 23.3 Find parallel groups
  - **Deliverable:** Detect parallel execution opportunities
  - **Req:** Req 8
  - **Tests:** Test parallel detection

- [ ] 23.4 Create WorkflowDefinition
  - **Deliverable:** Build definition object
  - **Req:** Req 4, Req 5, Req 6
  - **Tests:** Test definition creation

- [ ] 23.5 Validate workflow automatically
  - **Deliverable:** Call WorkflowValidator
  - **Req:** Req 13 (AC 1)
  - **Tests:** Test validation execution

- [ ] 23.6 Raise if validation fails
  - **Deliverable:** Call `report.raise_if_invalid()`
  - **Req:** Req 13 (AC 2)
  - **Tests:** Test error on invalid workflow

- [ ] 23.7 Store validation report
  - **Deliverable:** Cache report in WorkflowDefinition
  - **Req:** Req 13 (AC 4)
  - **Tests:** Test report storage

### 24. Integrate Validation into WorkflowMetadata

- [ ] 24.1 Implement `WorkflowMetadata._build()` method
  - **Deliverable:** Build workflow using WorkflowBuilder
  - **Req:** Req 2
  - **Tests:** Test build process

- [ ] 24.2 Implement `WorkflowMetadata.validate()` method
  - **Deliverable:** Explicit validation method
  - **Req:** Req 13 (AC 3)
  - **Tests:** Test explicit validation

- [ ] 24.3 Update `WorkflowMetadata.execute()` to call build
  - **Deliverable:** Build (and validate) on first execute
  - **Req:** Req 12, Req 13
  - **Tests:** Test validation on execute

### 25. Phase 3 Testing

- [ ] 25.1 Write unit tests for WorkflowBuilder
  - **Deliverable:** Test coverage >90%
  - **Tests:** 15+ test cases

- [ ] 25.2 Write unit tests for timeline/diverge/branch methods
  - **Deliverable:** Test all builder methods
  - **Tests:** 12+ test cases

- [ ] 25.3 Write unit tests for WorkflowValidator
  - **Deliverable:** Test all validation checks
  - **Tests:** 20+ test cases (one per validation rule)

- [ ] 25.4 Write integration tests for build + validate
  - **Deliverable:** Test end-to-end workflow building
  - **Tests:** 8+ integration tests

- [ ] 25.5 Write tests for error message quality
  - **Deliverable:** Verify messages include step names, suggestions
  - **Tests:** 10+ message validation tests

---

## Phase 4: Protobuf Serialization

**Goal:** Serialize WorkflowDefinition to protobuf Blueprint

**Dependencies:** Phase 3

**Requirements Covered:** Req 12 (partial), NFR-2

### 26. Implement ProtobufSerializer Structure

- [ ] 26.1 Create `ProtobufSerializer` class in `serializer.py`
  - **Deliverable:** Class with `serialize()` static method
  - **Req:** NFR-2 (Compatibility)
  - **Tests:** Unit test for serializer

### 27. Implement Timeline Serialization

- [ ] 27.1 Implement `_serialize_timeline()` helper
  - **Deliverable:** Convert timeline to Step protobuf list
  - **Req:** Req 4
  - **Tests:** Test timeline serialization

- [ ] 27.2 Map step dependencies to `depends_on` field
  - **Deliverable:** Protobuf Step has correct dependencies
  - **Req:** Req 7
  - **Tests:** Test dependency mapping

### 28. Implement Diverge Rule Serialization

- [ ] 28.1 Implement `_serialize_diverge_rules()` helper
  - **Deliverable:** Convert diverge rules to protobuf
  - **Req:** Req 5
  - **Tests:** Test diverge serialization

- [ ] 28.2 Map patterns to PatternMatch protobuf
  - **Deliverable:** Protobuf patterns correct
  - **Req:** Req 5
  - **Tests:** Test pattern mapping

- [ ] 28.3 Handle composition targets in patterns
  - **Deliverable:** Extract first step from composition
  - **Req:** Req 5 (AC 6)
  - **Tests:** Test composition in diverge

### 29. Implement Branch Rule Serialization

- [ ] 29.1 Implement `_serialize_branch_rules()` helper
  - **Deliverable:** Convert branch rules to protobuf
  - **Req:** Req 6
  - **Tests:** Test branch serialization

- [ ] 29.2 Implement `_serialize_predicate()` helper
  - **Deliverable:** Extract lambda source code or store reference
  - **Req:** Req 6
  - **Tests:** Test predicate serialization

- [ ] 29.3 Map when_true/when_false to ConditionBranch
  - **Deliverable:** Protobuf branches correct
  - **Req:** Req 6
  - **Tests:** Test branch mapping

### 30. Implement Complete Serialization

- [ ] 30.1 Implement `serialize(definition)` method
  - **Deliverable:** Complete protobuf Blueprint
  - **Req:** Req 12
  - **Tests:** Test full serialization

- [ ] 30.2 Set Blueprint metadata (version, language)
  - **Deliverable:** Blueprint has correct metadata
  - **Req:** NFR-2
  - **Tests:** Test metadata fields

- [ ] 30.3 Validate protobuf structure
  - **Deliverable:** Protobuf is valid
  - **Req:** NFR-2
  - **Tests:** Test protobuf validation

### 31. Phase 4 Testing

- [ ] 31.1 Write unit tests for ProtobufSerializer
  - **Deliverable:** Test coverage >90%
  - **Tests:** 10+ test cases

- [ ] 31.2 Write tests for each serialization helper
  - **Deliverable:** Test all helpers
  - **Tests:** 8+ test cases

- [ ] 31.3 Write integration tests with existing protobufs
  - **Deliverable:** Verify compatibility with Core
  - **Req:** NFR-2 (AC 3)
  - **Tests:** 5+ compatibility tests

- [ ] 31.4 Write performance tests for serialization
  - **Deliverable:** Verify <50ms serialization
  - **Req:** NFR-1 (AC 3)
  - **Tests:** Benchmark serialization time

---

## Phase 5: Execution Integration

**Goal:** Integrate with DistributedExecutor and enable workflow execution

**Dependencies:** Phase 4

**Requirements Covered:** Req 12

### 32. Update DistributedExecutor

- [ ] 32.1 Update `execute()` to handle WorkflowDefinition
  - **Deliverable:** Accept WorkflowDefinition or workflow ID
  - **Req:** Req 12 (AC 1)
  - **Tests:** Test with both input types

- [ ] 32.2 Call ProtobufSerializer before gRPC
  - **Deliverable:** Serialize definition to Blueprint
  - **Req:** Req 12
  - **Tests:** Test serialization call

- [ ] 32.3 Submit Blueprint to Core via gRPC
  - **Deliverable:** gRPC call succeeds
  - **Req:** Req 12
  - **Tests:** Test gRPC submission

- [ ] 32.4 Return ExecutionResult with execution_id
  - **Deliverable:** Result contains execution ID
  - **Req:** Req 12 (AC 2)
  - **Tests:** Test result structure

### 33. Implement WorkflowMetadata.execute()

- [ ] 33.1 Build workflow on first execute (lazy building)
  - **Deliverable:** `_build()` called on first execute
  - **Req:** Req 12
  - **Tests:** Test lazy building

- [ ] 33.2 Create DistributedExecutor instance
  - **Deliverable:** Executor created with core_url
  - **Req:** Req 12
  - **Tests:** Test executor creation

- [ ] 33.3 Call executor.execute() with definition and inputs
  - **Deliverable:** Execution triggered
  - **Req:** Req 12 (AC 1)
  - **Tests:** Test execution call

- [ ] 33.4 Validate inputs before execution
  - **Deliverable:** Raise `ValueError` for invalid inputs
  - **Req:** Req 12 (AC 3)
  - **Tests:** Test input validation

- [ ] 33.5 Handle ConnectionError for Core not running
  - **Deliverable:** Clear error message
  - **Req:** Req 12 (AC 4), Req 10 (AC 6)
  - **Tests:** Test connection error

### 34. Implement Result Handling

- [ ] 34.1 Create `ExecutionResult` dataclass
  - **Deliverable:** Dataclass with `execution_id`, `status`, `output`, `started_at` fields
  - **Req:** Req 12
  - **Tests:** Unit test for result

- [ ] 34.2 Implement `get_status()` method (future)
  - **Deliverable:** Method stub for polling status
  - **Req:** Req 12 (AC 5)
  - **Tests:** Method exists

### 35. Phase 5 Testing

- [ ] 35.1 Write integration tests with mock gRPC server
  - **Deliverable:** Test execution flow without real Core
  - **Tests:** 6+ mock tests

- [ ] 35.2 Write integration tests with local Core
  - **Deliverable:** Test end-to-end execution
  - **Req:** Req 12
  - **Tests:** 4+ E2E tests

- [ ] 35.3 Write tests for error scenarios
  - **Deliverable:** Test connection errors, invalid inputs
  - **Tests:** 5+ error tests

---

## Phase 6: Error Handling and Polish

**Goal:** Improve error messages, add type hints, documentation, and performance

**Dependencies:** Phase 5

**Requirements Covered:** Req 10, Req 11, NFR-1, NFR-3

### 36. Improve Error Messages

- [ ] 36.1 Add step names to all error messages
  - **Deliverable:** Errors include `[step_name]` prefix
  - **Req:** Req 10 (AC 2), NFR-3 (AC 1)
  - **Tests:** Test all error message formats

- [ ] 36.2 Add suggestions to error messages
  - **Deliverable:** All errors have "Suggestion:" line
  - **Req:** Req 10, NFR-3
  - **Tests:** Test suggestion content

- [ ] 36.3 Extract line numbers using `inspect` module
  - **Deliverable:** Errors include "At: file.py:line"
  - **Req:** Req 10 (AC 5), NFR-3 (AC 1)
  - **Tests:** Test line number extraction

- [ ] 36.4 Format error messages consistently
  - **Deliverable:** All errors follow same format
  - **Req:** NFR-3
  - **Tests:** Test message consistency

### 37. Add Type Hints

- [ ] 37.1 Add type hints to all decorator functions
  - **Deliverable:** Full type coverage in `decorators.py`
  - **Req:** Req 11
  - **Tests:** mypy validation passes

- [ ] 37.2 Add type hints to WorkflowBuilder
  - **Deliverable:** Full type coverage in `builder.py`
  - **Req:** Req 11
  - **Tests:** mypy validation passes

- [ ] 37.3 Add type hints to DependencyAnalyzer
  - **Deliverable:** Full type coverage in `analyzer.py`
  - **Req:** Req 11
  - **Tests:** mypy validation passes

- [ ] 37.4 Add type hints to WorkflowValidator
  - **Deliverable:** Full type coverage in `validator.py`
  - **Req:** Req 11
  - **Tests:** mypy validation passes

- [ ] 37.5 Add type hints to ProtobufSerializer
  - **Deliverable:** Full type coverage in `serializer.py`
  - **Req:** Req 11
  - **Tests:** mypy validation passes

- [ ] 37.6 Create `types.py` with type aliases
  - **Deliverable:** Export `StepResult`, `Context`, etc.
  - **Req:** Req 11 (AC 1)
  - **Tests:** Types importable

- [ ] 37.7 Update public API exports with types
  - **Deliverable:** Root `__init__.py` exports all types
  - **Req:** Req 11
  - **Tests:** IDE autocomplete works

### 38. Add Documentation

- [ ] 38.1 Add docstrings to all public functions
  - **Deliverable:** Every public function has docstring
  - **Req:** NFR-3 (AC 3)
  - **Tests:** Documentation coverage >95%

- [ ] 38.2 Add docstrings to all classes
  - **Deliverable:** Every class has docstring
  - **Req:** NFR-3
  - **Tests:** Documentation coverage check

- [ ] 38.3 Add module-level docstrings
  - **Deliverable:** Every module has docstring
  - **Req:** NFR-3
  - **Tests:** Documentation coverage check

- [ ] 38.4 Add inline comments for complex logic
  - **Deliverable:** Complex algorithms have comments
  - **Req:** NFR-3
  - **Tests:** Code review

- [ ] 38.5 Write user guide examples
  - **Deliverable:** 5+ complete workflow examples
  - **Req:** NFR-3 (AC 3)
  - **Tests:** Examples execute successfully

### 39. Performance Optimization

- [ ] 39.1 Profile workflow definition time
  - **Deliverable:** Benchmark definition creation
  - **Req:** NFR-1 (AC 1)
  - **Tests:** <100ms for 100 steps

- [ ] 39.2 Optimize dependency analysis algorithm
  - **Deliverable:** Verify O(n log n) complexity
  - **Req:** NFR-1 (AC 2)
  - **Tests:** Benchmark scaling

- [ ] 39.3 Optimize protobuf serialization
  - **Deliverable:** Verify <50ms serialization
  - **Req:** NFR-1 (AC 3)
  - **Tests:** Benchmark serialization

- [ ] 39.4 Add caching where appropriate
  - **Deliverable:** Cache validation results
  - **Req:** NFR-1
  - **Tests:** Test cache correctness

### 40. Final Integration and Testing

- [ ] 40.1 Write comprehensive end-to-end tests
  - **Deliverable:** 10+ E2E workflow tests
  - **Tests:** Cover all major features

- [ ] 40.2 Write stress tests (large workflows)
  - **Deliverable:** Test with 100+ step workflows
  - **Req:** NFR-1
  - **Tests:** Performance benchmarks

- [ ] 40.3 Write compatibility tests with Core
  - **Deliverable:** Verify integration with Elixir Core
  - **Req:** NFR-2 (AC 2)
  - **Tests:** 5+ compatibility tests

- [ ] 40.4 Run full test suite with coverage
  - **Deliverable:** >90% test coverage overall
  - **Req:** Req 10
  - **Tests:** Coverage report

- [ ] 40.5 Fix all failing tests
  - **Deliverable:** 100% test pass rate
  - **Tests:** CI passes

### 41. Documentation and Examples

- [ ] 41.1 Create migration guide from old API
  - **Deliverable:** Migration document with examples
  - **Req:** NFR-3
  - **Tests:** Migration examples work

- [ ] 41.2 Create troubleshooting guide
  - **Deliverable:** Common errors and solutions
  - **Req:** NFR-3
  - **Tests:** Guide is clear

- [ ] 41.3 Update main README with new syntax
  - **Deliverable:** README shows new DSL
  - **Req:** NFR-3
  - **Tests:** README examples work

- [ ] 41.4 Create API reference documentation
  - **Deliverable:** Auto-generated docs from docstrings
  - **Req:** NFR-3
  - **Tests:** Docs build successfully

### 42. Code Quality and CI

- [ ] 42.1 Setup pre-commit hooks (formatting, linting)
  - **Deliverable:** Hooks configured
  - **Tests:** Hooks run on commit

- [ ] 42.2 Configure mypy for type checking
  - **Deliverable:** mypy config in pyproject.toml
  - **Req:** Req 11
  - **Tests:** mypy passes

- [ ] 42.3 Configure pytest with coverage
  - **Deliverable:** pytest.ini configured
  - **Tests:** Coverage report generated

- [ ] 42.4 Add CI pipeline (GitHub Actions)
  - **Deliverable:** CI runs tests on PR
  - **Tests:** CI pipeline works

- [ ] 42.5 Add code quality badges
  - **Deliverable:** Badges in README
  - **Tests:** Badges display correctly

---

## Summary

### Task Distribution by Phase

| Phase | Tasks | Estimated Effort |
|-------|-------|-----------------|
| Phase 1: Core Decorators | 9 groups (37 tasks) | 2-3 weeks |
| Phase 2: Dependency Analysis | 7 groups (21 tasks) | 1-2 weeks |
| Phase 3: Builder & Validation | 9 groups (29 tasks) | 2-3 weeks |
| Phase 4: Protobuf Serialization | 6 groups (11 tasks) | 1 week |
| Phase 5: Execution Integration | 4 groups (9 tasks) | 1 week |
| Phase 6: Polish & Documentation | 7 groups (19 tasks) | 1-2 weeks |
| **Total** | **42 groups (126 tasks)** | **8-14 weeks** |

### Requirements Coverage

All 13 requirements + 3 NFRs are covered:
- ✅ Req 1: Step Decorator
- ✅ Req 2: Workflow Decorator
- ✅ Req 3: Sequential Composition
- ✅ Req 4: Timeline Declaration
- ✅ Req 5: Diverge (Pattern Matching)
- ✅ Req 6: Branch (Conditional Routing)
- ✅ Req 7: Automatic Dependency Resolution
- ✅ Req 8: Automatic Parallelism
- ✅ Req 9: Context Object
- ✅ Req 10: Error Handling
- ✅ Req 11: Type Hints Support
- ✅ Req 12: Workflow Execution
- ✅ Req 13: Workflow Validation
- ✅ NFR-1: Performance
- ✅ NFR-2: Compatibility
- ✅ NFR-3: Developer Experience

### Testing Strategy

- **Unit Tests:** 80+ test files
- **Integration Tests:** 30+ scenarios
- **E2E Tests:** 15+ workflows
- **Performance Tests:** 10+ benchmarks
- **Coverage Target:** >90%

### Next Steps

1. Review and approve this task breakdown
2. Prioritize tasks if needed
3. Assign tasks to developers
4. Setup project tracking (GitHub Projects, Jira, etc.)
5. Begin Phase 1 implementation

---

**Document Status:** Ready for Implementation
**Reviewed By:** Team Lead
**Approved:** [Pending]
**Implementation Start Date:** [TBD]

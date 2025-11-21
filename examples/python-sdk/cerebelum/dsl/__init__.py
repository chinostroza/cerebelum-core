"""Cerebelum DSL - Domain-Specific Language for Workflow Definition.

This module provides a declarative DSL for defining workflows using Python
decorators, composition operators, and automatic dependency resolution.
"""

from .context import Context
from .decorators import step, workflow, StepMetadata, WorkflowMetadata
from .composition import StepComposition, ParallelStepGroup
from .registry import StepRegistry, WorkflowRegistry
from .analyzer import DependencyAnalyzer, DependencyGraph, DependencyNode
from .builder import WorkflowBuilder, DivergeRule, BranchRule
from .validator import WorkflowValidator, ValidationReport
from .serializer import DSLSerializer
from .execution import DSLExecutionAdapter, DSLLocalExecutor
from .exceptions import (
    DSLError,
    StepDefinitionError,
    WorkflowDefinitionError,
    DependencyError,
    StepExecutionError,
    StepTimeoutError,
    RetryExhaustedError,
    InvalidReturnValueError,
    SerializationError,
)

__all__ = [
    # Decorators
    "step",
    "workflow",
    # Metadata classes
    "StepMetadata",
    "WorkflowMetadata",
    # Composition
    "StepComposition",
    "ParallelStepGroup",
    # Context
    "Context",
    # Registries (for advanced use)
    "StepRegistry",
    "WorkflowRegistry",
    # Dependency Analysis (Phase 2)
    "DependencyAnalyzer",
    "DependencyGraph",
    "DependencyNode",
    # Workflow Builder and Validation (Phase 3)
    "WorkflowBuilder",
    "DivergeRule",
    "BranchRule",
    "WorkflowValidator",
    "ValidationReport",
    # Serialization (Phase 4)
    "DSLSerializer",
    # Execution (Phase 5)
    "DSLExecutionAdapter",
    "DSLLocalExecutor",
    # Exceptions (Phase 6)
    "DSLError",
    "StepDefinitionError",
    "WorkflowDefinitionError",
    "DependencyError",
    "StepExecutionError",
    "StepTimeoutError",
    "RetryExhaustedError",
    "InvalidReturnValueError",
    "SerializationError",
]

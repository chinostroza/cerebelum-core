"""Workflow builder for defining workflows."""
from __future__ import annotations

from typing import Any, Callable, Coroutine, Dict, List, Optional

from .types import (
    ActionType,
    BranchAction,
    BranchRule,
    ConditionBranch,
    DivergeRule,
    PatternMatch,
    StepFunction,
    StepMetadata,
    WorkflowDefinition,
)


class WorkflowBuilder:
    """Builder for creating workflow definitions.

    Example:
        workflow = (
            WorkflowBuilder("my_workflow")
            .timeline(["step1", "step2", "step3"])
            .step("step1", my_function)
            .step("step2", another_function)
            .diverge("step1")
                .when(":ok", target="step2")
                .when(":error", target="error_handler")
            .branch("step2")
                .if_("result > 10", skip_to="step3")
            .build()
        )
    """

    def __init__(self, workflow_id: str):
        """Initialize workflow builder.

        Args:
            workflow_id: Unique identifier for the workflow
        """
        self.id = workflow_id
        self._timeline: List[str] = []
        self._steps_metadata: Dict[str, StepMetadata] = {}
        self._diverge_rules: List[DivergeRule] = []
        self._branch_rules: List[BranchRule] = []
        self._inputs: Dict[str, Any] = {}
        self._current_diverge: Optional[DivergeBuilder] = None
        self._current_branch: Optional[BranchBuilder] = None

    def timeline(self, steps: List[str]) -> WorkflowBuilder:
        """Define the workflow timeline (step execution order).

        Args:
            steps: List of step names in execution order

        Returns:
            Self for method chaining
        """
        self._timeline = steps
        return self

    def step(
        self,
        name: str,
        function: StepFunction,
        depends_on: Optional[List[str]] = None,
    ) -> WorkflowBuilder:
        """Register a step function.

        Args:
            name: Step name
            function: Async function to execute
            depends_on: Optional list of step names this step depends on

        Returns:
            Self for method chaining
        """
        self._steps_metadata[name] = StepMetadata(
            name=name,
            function=function,
            depends_on=depends_on or [],
        )
        return self

    def diverge(self, on: str) -> DivergeBuilder:
        """Create a diverge rule (pattern matching on step result).

        Args:
            on: Step name to diverge from

        Returns:
            DivergeBuilder for adding patterns
        """
        self._current_diverge = DivergeBuilder(self, on)
        return self._current_diverge

    def branch(self, on: str) -> BranchBuilder:
        """Create a branch rule (conditional routing).

        Args:
            on: Step name to branch from

        Returns:
            BranchBuilder for adding conditions
        """
        self._current_branch = BranchBuilder(self, on)
        return self._current_branch

    def inputs(self, inputs_schema: Dict[str, Any]) -> WorkflowBuilder:
        """Define workflow input schema (optional).

        Args:
            inputs_schema: Schema for workflow inputs

        Returns:
            Self for method chaining
        """
        self._inputs = inputs_schema
        return self

    def build(self) -> WorkflowDefinition:
        """Build the final workflow definition.

        Returns:
            Complete workflow definition

        Raises:
            ValueError: If workflow is invalid
        """
        # Validate
        if not self._timeline:
            raise ValueError("Workflow must have a timeline")

        if not self._steps_metadata:
            raise ValueError("Workflow must have at least one step")

        # Check all timeline steps have metadata
        for step_name in self._timeline:
            if step_name not in self._steps_metadata:
                raise ValueError(f"Step '{step_name}' in timeline has no registered function")

        # Auto-generate depends_on for sequential timelines
        # If a step has no explicit dependencies and no diverge/branch rules pointing to it,
        # it depends on the previous step in the timeline
        self._auto_generate_dependencies()

        return WorkflowDefinition(
            id=self.id,
            timeline=self._timeline,
            steps_metadata=self._steps_metadata,
            diverge_rules=self._diverge_rules,
            branch_rules=self._branch_rules,
            inputs=self._inputs,
        )

    def _auto_generate_dependencies(self) -> None:
        """Automatically generate depends_on for sequential timeline steps.

        For steps without explicit dependencies:
        - First step has no dependencies (receives workflow input)
        - Subsequent steps depend on the previous step in the timeline

        This is skipped for steps that are:
        - Targets of diverge rules (pattern-based routing)
        - Targets of branch rules (conditional routing)
        """
        # Collect steps that are targets of diverge/branch rules
        # These should NOT get auto-dependencies
        diverge_targets = set()
        for rule in self._diverge_rules:
            for pattern in rule.patterns:
                diverge_targets.add(pattern.target)

        branch_targets = set()
        for rule in self._branch_rules:
            for branch in rule.branches:
                branch_targets.add(branch.action.target_step)

        special_targets = diverge_targets | branch_targets

        # Generate dependencies for sequential steps
        for i, step_name in enumerate(self._timeline):
            metadata = self._steps_metadata[step_name]

            # Skip if step already has explicit dependencies
            if metadata.depends_on:
                continue

            # Skip if step is a target of diverge/branch rule
            if step_name in special_targets:
                continue

            # First step has no dependencies (receives workflow input)
            if i == 0:
                metadata.depends_on = []
            else:
                # Subsequent steps depend on previous step in timeline
                previous_step = self._timeline[i - 1]
                metadata.depends_on = [previous_step]


class DivergeBuilder:
    """Builder for diverge rules (pattern matching)."""

    def __init__(self, workflow_builder: WorkflowBuilder, from_step: str):
        """Initialize diverge builder.

        Args:
            workflow_builder: Parent workflow builder
            from_step: Step to diverge from
        """
        self._workflow = workflow_builder
        self._rule = DivergeRule(from_step=from_step)

    def when(self, pattern: Any, target: str) -> DivergeBuilder:
        """Add a pattern match.

        Args:
            pattern: Pattern to match (e.g., ":ok", True, 42)
            target: Target step name

        Returns:
            Self for method chaining
        """
        # Convert Python values to pattern strings
        pattern_str = self._pattern_to_str(pattern)
        self._rule.patterns.append(PatternMatch(pattern=pattern_str, target=target))
        return self

    def _pattern_to_str(self, pattern: Any) -> str:
        """Convert Python pattern to string representation."""
        if isinstance(pattern, dict):
            # Serialize dict as JSON for pattern matching
            import json
            return json.dumps(pattern)
        elif isinstance(pattern, bool):
            return str(pattern)
        elif isinstance(pattern, (int, float)):
            return str(pattern)
        elif isinstance(pattern, str):
            # Atom-style pattern
            if pattern.startswith(":"):
                return pattern
            # String pattern
            return f'"{pattern}"'
        else:
            return str(pattern)

    # Return workflow builder for chaining
    def diverge(self, on: str) -> DivergeBuilder:
        """Start a new diverge rule.

        Args:
            on: Step name to diverge from

        Returns:
            New DivergeBuilder
        """
        self._workflow._diverge_rules.append(self._rule)
        return self._workflow.diverge(on)

    def branch(self, on: str) -> BranchBuilder:
        """Start a branch rule.

        Args:
            on: Step name to branch from

        Returns:
            BranchBuilder
        """
        self._workflow._diverge_rules.append(self._rule)
        return self._workflow.branch(on)

    def build(self) -> WorkflowDefinition:
        """Build the workflow.

        Returns:
            Complete workflow definition
        """
        self._workflow._diverge_rules.append(self._rule)
        return self._workflow.build()


class BranchBuilder:
    """Builder for branch rules (conditional routing)."""

    def __init__(self, workflow_builder: WorkflowBuilder, from_step: str):
        """Initialize branch builder.

        Args:
            workflow_builder: Parent workflow builder
            from_step: Step to branch from
        """
        self._workflow = workflow_builder
        self._rule = BranchRule(from_step=from_step)

    def if_(self, condition: str, skip_to: Optional[str] = None, back_to: Optional[str] = None) -> BranchBuilder:
        """Add a conditional branch.

        Args:
            condition: Condition expression (e.g., "result > 10")
            skip_to: Step to skip to if condition is true
            back_to: Step to go back to if condition is true

        Returns:
            Self for method chaining

        Raises:
            ValueError: If neither skip_to nor back_to is provided
        """
        if skip_to and back_to:
            raise ValueError("Cannot specify both skip_to and back_to")

        if not skip_to and not back_to:
            raise ValueError("Must specify either skip_to or back_to")

        if skip_to:
            action = BranchAction(type=ActionType.SKIP_TO, target_step=skip_to)
        else:
            action = BranchAction(type=ActionType.BACK_TO, target_step=back_to)  # type: ignore

        self._rule.branches.append(ConditionBranch(condition=condition, action=action))
        return self

    # Return workflow builder for chaining
    def diverge(self, on: str) -> DivergeBuilder:
        """Start a new diverge rule.

        Args:
            on: Step name to diverge from

        Returns:
            DivergeBuilder
        """
        self._workflow._branch_rules.append(self._rule)
        return self._workflow.diverge(on)

    def branch(self, on: str) -> BranchBuilder:
        """Start a new branch rule.

        Args:
            on: Step name to branch from

        Returns:
            New BranchBuilder
        """
        self._workflow._branch_rules.append(self._rule)
        return self._workflow.branch(on)

    def build(self) -> WorkflowDefinition:
        """Build the workflow.

        Returns:
            Complete workflow definition
        """
        self._workflow._branch_rules.append(self._rule)
        return self._workflow.build()

"""Workflow builder for constructing workflows with timeline, diverge, and branch rules.

Provides a fluent API for building workflows in the @workflow decorator.
"""

from dataclasses import dataclass, field
from typing import List, Dict, Callable, Optional, Union, TYPE_CHECKING

if TYPE_CHECKING:
    from .decorators import StepMetadata
    from .composition import StepComposition


@dataclass
class DivergeRule:
    """Pattern matching rule for diverge construct.

    Maps output values from a step to different execution paths.

    Attributes:
        from_step: The step whose output triggers pattern matching
        patterns: Dict mapping pattern values to target steps/compositions

    Example:
        >>> diverge_rule = DivergeRule(
        ...     from_step=validate_user,
        ...     patterns={
        ...         "premium": premium_flow,
        ...         "standard": standard_flow,
        ...         "error": handle_error
        ...     }
        ... )
    """
    from_step: "StepMetadata"
    patterns: Dict[str, Union["StepMetadata", "StepComposition"]]


@dataclass
class BranchRule:
    """Conditional branching rule.

    Routes execution based on a boolean condition function.

    Attributes:
        after: The step after which to evaluate the condition
        condition: Function that takes step output and returns bool
        when_true: Step to execute if condition is True
        when_false: Step to execute if condition is False

    Example:
        >>> branch_rule = BranchRule(
        ...     after=check_inventory,
        ...     condition=lambda output: output.get("in_stock", False),
        ...     when_true=process_order,
        ...     when_false=backorder
        ... )
    """
    after: "StepMetadata"
    condition: Callable[[dict], bool]
    when_true: "StepMetadata"
    when_false: "StepMetadata"


class WorkflowBuilder:
    """Builder for constructing workflows with declarative DSL.

    Provides a fluent API for defining:
    - timeline: Linear or parallel step execution
    - diverge: Pattern matching on step outputs
    - branch: Conditional routing

    This builder is passed to @workflow decorated functions.

    Example:
        >>> @workflow
        >>> def my_workflow(wf):
        ...     wf.timeline(step1 >> step2 >> step3)
        ...     wf.diverge(step2, {
        ...         "success": step4,
        ...         "error": handle_error
        ...     })
        ...     wf.branch(
        ...         after=step3,
        ...         condition=lambda out: out["valid"],
        ...         when_true=step5,
        ...         when_false=step6
        ...     )
    """

    def __init__(self, workflow_name: str):
        """Initialize workflow builder.

        Args:
            workflow_name: Name of the workflow being built
        """
        self.workflow_name = workflow_name
        # Timeline can contain StepMetadata OR ParallelStepGroup
        self._timeline: List[Union["StepMetadata", "ParallelStepGroup"]] = []
        self._diverge_rules: List[DivergeRule] = []
        self._branch_rules: List[BranchRule] = []

    def timeline(
        self,
        steps: Union["StepMetadata", "StepComposition", List["StepMetadata"]]
    ) -> "WorkflowBuilder":
        """Define the main execution timeline.

        Accepts:
        - Single step: timeline(step1)
        - Composition: timeline(step1 >> step2 >> step3)
        - Composition with parallel: timeline(step1 >> [step2, step3] >> step4)
        - List: timeline([step1, step2, step3])

        Args:
            steps: Step(s) to add to timeline

        Returns:
            Self for method chaining

        Example:
            >>> wf.timeline(fetch_user >> validate_user >> process_payment)
            >>> wf.timeline(step1 >> [step2, step3] >> step4)  # Parallel steps
        """
        from .decorators import StepMetadata
        from .composition import StepComposition, ParallelStepGroup

        if isinstance(steps, StepMetadata):
            # Single step
            if steps.name not in [self._get_step_name(s) for s in self._timeline]:
                self._timeline.append(steps)
        elif isinstance(steps, StepComposition):
            # Composition (step1 >> step2 or step1 >> [step2, step3])
            for item in steps.items:
                if isinstance(item, ParallelStepGroup):
                    # Parallel group - PRESERVE IT (don't flatten)
                    self._timeline.append(item)
                else:
                    # Regular step
                    if item.name not in [self._get_step_name(s) for s in self._timeline]:
                        self._timeline.append(item)
        elif isinstance(steps, list):
            # List of steps
            for step in steps:
                if isinstance(step, StepMetadata):
                    if step.name not in [self._get_step_name(s) for s in self._timeline]:
                        self._timeline.append(step)
                else:
                    raise TypeError(
                        f"timeline() expects StepMetadata, got {type(step).__name__}"
                    )
        else:
            raise TypeError(
                f"timeline() expects StepMetadata, StepComposition, or list, "
                f"got {type(steps).__name__}"
            )

        return self

    def _get_step_name(self, item: Union["StepMetadata", "ParallelStepGroup"]) -> str:
        """Helper to get name from step or parallel group.

        Args:
            item: StepMetadata or ParallelStepGroup

        Returns:
            Name of step, or concatenated names for parallel group
        """
        from .composition import ParallelStepGroup
        if isinstance(item, ParallelStepGroup):
            return "|".join(s.name for s in item.steps)
        return item.name

    def diverge(
        self,
        from_step: "StepMetadata",
        patterns: Dict[str, Union["StepMetadata", "StepComposition"]]
    ) -> "WorkflowBuilder":
        """Define pattern matching rule.

        Maps output values from a step to different execution paths.

        Args:
            from_step: Step whose output triggers pattern matching
            patterns: Dict mapping pattern values to target steps/compositions

        Returns:
            Self for method chaining

        Example:
            >>> wf.diverge(validate_user, {
            ...     "premium": premium_flow,
            ...     "standard": standard_flow,
            ...     "error": handle_error
            ... })
        """
        from .decorators import StepMetadata

        if not isinstance(from_step, StepMetadata):
            raise TypeError(
                f"diverge() expects StepMetadata for from_step, "
                f"got {type(from_step).__name__}"
            )

        if not isinstance(patterns, dict):
            raise TypeError(
                f"diverge() expects dict for patterns, "
                f"got {type(patterns).__name__}"
            )

        rule = DivergeRule(from_step=from_step, patterns=patterns)
        self._diverge_rules.append(rule)

        return self

    def branch(
        self,
        after: "StepMetadata",
        condition: Callable[[dict], bool],
        when_true: "StepMetadata",
        when_false: "StepMetadata"
    ) -> "WorkflowBuilder":
        """Define conditional branching rule.

        Routes execution based on a boolean condition function.

        Args:
            after: Step after which to evaluate condition
            condition: Function that takes step output and returns bool
            when_true: Step to execute if condition is True
            when_false: Step to execute if condition is False

        Returns:
            Self for method chaining

        Example:
            >>> wf.branch(
            ...     after=check_inventory,
            ...     condition=lambda out: out.get("in_stock", False),
            ...     when_true=process_order,
            ...     when_false=backorder
            ... )
        """
        from .decorators import StepMetadata

        if not isinstance(after, StepMetadata):
            raise TypeError(
                f"branch() expects StepMetadata for after, "
                f"got {type(after).__name__}"
            )

        if not callable(condition):
            raise TypeError(
                f"branch() expects callable for condition, "
                f"got {type(condition).__name__}"
            )

        if not isinstance(when_true, StepMetadata):
            raise TypeError(
                f"branch() expects StepMetadata for when_true, "
                f"got {type(when_true).__name__}"
            )

        if not isinstance(when_false, StepMetadata):
            raise TypeError(
                f"branch() expects StepMetadata for when_false, "
                f"got {type(when_false).__name__}"
            )

        rule = BranchRule(
            after=after,
            condition=condition,
            when_true=when_true,
            when_false=when_false
        )
        self._branch_rules.append(rule)

        return self

    def get_timeline(self) -> List[Union["StepMetadata", "ParallelStepGroup"]]:
        """Get the timeline steps (may include ParallelStepGroup).

        Returns:
            List of steps/groups in the timeline (preserves parallel structure)
        """
        return self._timeline

    def get_all_steps(self) -> List["StepMetadata"]:
        """Get all steps flattened (expands ParallelStepGroup).

        Returns:
            Flattened list of all StepMetadata instances
        """
        from .composition import ParallelStepGroup

        all_steps = []
        for item in self._timeline:
            if isinstance(item, ParallelStepGroup):
                all_steps.extend(item.steps)
            else:
                all_steps.append(item)
        return all_steps

    def get_diverge_rules(self) -> List[DivergeRule]:
        """Get the diverge rules.

        Returns:
            List of diverge rules
        """
        return self._diverge_rules

    def get_branch_rules(self) -> List[BranchRule]:
        """Get the branch rules.

        Returns:
            List of branch rules
        """
        return self._branch_rules

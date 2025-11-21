"""Step composition for sequential execution.

Enables chaining steps using the >> operator and list syntax for parallelism.
"""

from typing import List, Union, TYPE_CHECKING

if TYPE_CHECKING:
    from .decorators import StepMetadata


class ParallelStepGroup:
    """Represents a group of steps that execute in parallel.

    Created when using list syntax in timeline composition:
        step_a >> [step_b, step_c] >> step_d

    Attributes:
        steps: List of steps that should execute in parallel
    """

    def __init__(self, steps: List["StepMetadata"]):
        """Initialize parallel group.

        Args:
            steps: List of StepMetadata instances to execute in parallel

        Raises:
            ValueError: If steps list is empty
        """
        if not steps:
            raise ValueError("Parallel group cannot be empty")
        self.steps = steps

    def __repr__(self) -> str:
        """String representation."""
        step_names = ", ".join(step.name for step in self.steps)
        return f"ParallelStepGroup([{step_names}])"


class StepComposition:
    """Represents a chain of steps composed with >> operator.

    Can contain both individual steps and parallel groups:
        >>> a >> b >> c  # Sequential: [a, b, c]
        >>> a >> [b, c] >> d  # Sequential with parallel: [a, ParallelGroup([b, c]), d]

    Attributes:
        items: List of StepMetadata or ParallelStepGroup instances
    """

    def __init__(self, items: List[Union["StepMetadata", ParallelStepGroup]]):
        """Initialize composition with list of steps or parallel groups.

        Args:
            items: List of StepMetadata or ParallelStepGroup instances in execution order
        """
        self.items = items

    @property
    def steps(self) -> List[Union["StepMetadata", ParallelStepGroup]]:
        """Alias for backwards compatibility."""
        return self.items

    def __rshift__(self, other: object) -> "StepComposition":
        """Enable chaining: a >> b >> c or a >> [b, c] >> d.

        Args:
            other: StepMetadata, StepComposition, or list of StepMetadata (parallel)

        Returns:
            New StepComposition with combined items

        Raises:
            TypeError: If other is not a valid type
            ValueError: If list is empty

        Example:
            >>> composition = a >> b
            >>> extended = composition >> c  # Sequential
            >>> parallel = composition >> [d, e]  # Parallel group
        """
        from .decorators import StepMetadata

        if isinstance(other, StepMetadata):
            # Single step - add to sequence
            return StepComposition(self.items + [other])
        elif isinstance(other, StepComposition):
            # Another composition - merge
            return StepComposition(self.items + other.items)
        elif isinstance(other, list):
            # List of steps - create parallel group
            if not other:
                raise ValueError("Parallel step list cannot be empty")
            if not all(isinstance(s, StepMetadata) for s in other):
                raise TypeError(
                    "Parallel step list must contain only steps decorated with @step"
                )
            parallel_group = ParallelStepGroup(other)
            return StepComposition(self.items + [parallel_group])
        else:
            raise TypeError(
                f"Cannot compose StepComposition with {type(other).__name__}. "
                f"Right operand must be a step decorated with @step, "
                f"a StepComposition, or a list of steps."
            )

    def __repr__(self) -> str:
        """String representation of composition."""
        parts = []
        for item in self.items:
            if isinstance(item, ParallelStepGroup):
                # Format as [step1, step2]
                step_names = ", ".join(s.name for s in item.steps)
                parts.append(f"[{step_names}]")
            else:
                # Regular step
                parts.append(item.name)
        return f"StepComposition({' >> '.join(parts)})"

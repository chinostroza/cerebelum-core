"""Workflow validation engine.

Validates workflows at definition time to catch errors before execution.
Implements comprehensive validation including dependency integrity, cycle detection,
parameter signature checking, and unreachable step detection.
"""

from dataclasses import dataclass, field
from typing import List, Set, Dict, Optional, TYPE_CHECKING
import inspect

if TYPE_CHECKING:
    from .decorators import StepMetadata
    from .builder import DivergeRule, BranchRule


@dataclass
class ValidationReport:
    """Result of workflow validation.

    Attributes:
        errors: List of error messages (block execution)
        warnings: List of warning messages (don't block execution)
        is_valid: True if no errors exist

    Example:
        >>> report = validator.validate()
        >>> if not report.is_valid:
        ...     for error in report.errors:
        ...         print(f"ERROR: {error}")
        >>> for warning in report.warnings:
        ...     print(f"WARNING: {warning}")
    """
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)

    @property
    def is_valid(self) -> bool:
        """Check if validation passed (no errors).

        Returns:
            True if no errors exist, False otherwise
        """
        return len(self.errors) == 0

    def add_error(self, message: str) -> None:
        """Add an error message.

        Args:
            message: Error description
        """
        self.errors.append(message)

    def add_warning(self, message: str) -> None:
        """Add a warning message.

        Args:
            message: Warning description
        """
        self.warnings.append(message)


class WorkflowValidator:
    """Validates workflow definitions at build time.

    Performs comprehensive validation including:
    1. Timeline completeness (non-empty)
    2. Dependency integrity (no missing deps, no cycles)
    3. Diverge rule validation
    4. Branch rule validation
    5. Parameter signature validation
    6. Execution readiness
    7. Unreachable step detection

    Example:
        >>> validator = WorkflowValidator(
        ...     workflow_name="my_workflow",
        ...     timeline=[step1, step2],
        ...     diverge_rules=[],
        ...     branch_rules=[]
        ... )
        >>> report = validator.validate()
        >>> if not report.is_valid:
        ...     raise ValueError(f"Workflow validation failed: {report.errors}")
    """

    def __init__(
        self,
        workflow_name: str,
        timeline: List["StepMetadata"],
        diverge_rules: Optional[List["DivergeRule"]] = None,
        branch_rules: Optional[List["BranchRule"]] = None,
    ):
        """Initialize validator.

        Args:
            workflow_name: Name of the workflow
            timeline: Main timeline steps
            diverge_rules: Pattern matching rules
            branch_rules: Conditional routing rules
        """
        self.workflow_name = workflow_name
        self.timeline = timeline
        self.diverge_rules = diverge_rules or []
        self.branch_rules = branch_rules or []
        self.report = ValidationReport()

    def _get_timeline_names(self) -> Set[str]:
        """Get all step names from timeline (flatten parallel groups).

        Returns:
            Set of all step names in timeline
        """
        from .composition import ParallelStepGroup

        timeline_names = set()
        for item in self.timeline:
            if isinstance(item, ParallelStepGroup):
                timeline_names.update(step.name for step in item.steps)
            else:
                timeline_names.add(item.name)
        return timeline_names

    def _get_all_steps(self) -> List["StepMetadata"]:
        """Get all steps from timeline (flatten parallel groups).

        Returns:
            List of all StepMetadata instances
        """
        from .composition import ParallelStepGroup

        all_steps = []
        for item in self.timeline:
            if isinstance(item, ParallelStepGroup):
                all_steps.extend(item.steps)
            else:
                all_steps.append(item)
        return all_steps

    def validate(self) -> ValidationReport:
        """Run all validation checks.

        Returns:
            ValidationReport with errors and warnings
        """
        self._validate_timeline_completeness()
        self._validate_dependency_integrity()
        self._validate_diverge_rules()
        self._validate_branch_rules()
        self._validate_parameter_signatures()
        self._validate_execution_readiness()
        self._check_unreachable_steps()

        return self.report

    def _validate_timeline_completeness(self) -> None:
        """Validate that timeline is non-empty.

        Adds error if timeline is empty.
        """
        if not self.timeline:
            self.report.add_error(
                f"Workflow '{self.workflow_name}' has empty timeline. "
                f"Use wf.timeline() to define at least one step."
            )

    def _validate_dependency_integrity(self) -> None:
        """Validate dependency integrity (no missing deps, no cycles).

        Uses DependencyAnalyzer to check for:
        - Missing dependencies (step depends on non-existent step)
        - Circular dependencies (cycle detection)

        Adds errors for any issues found.
        """
        from .analyzer import DependencyAnalyzer

        try:
            # DependencyAnalyzer.analyze() will raise ValueError if:
            # - Missing dependencies
            # - Circular dependencies
            graph = DependencyAnalyzer.analyze(
                timeline=self.timeline,
                diverge_rules=self.diverge_rules,
                branch_rules=self.branch_rules,
            )
        except ValueError as e:
            self.report.add_error(str(e))

    def _validate_diverge_rules(self) -> None:
        """Validate diverge rules.

        Checks:
        1. from_step exists in timeline
        2. All pattern targets are valid StepMetadata or StepComposition
        3. Pattern keys are non-empty strings

        Adds errors for any issues found.
        """
        from .decorators import StepMetadata
        from .composition import StepComposition, ParallelStepGroup

        # Get all step names from timeline (flatten parallel groups)
        timeline_names = set()
        for item in self.timeline:
            if isinstance(item, ParallelStepGroup):
                timeline_names.update(step.name for step in item.steps)
            else:
                timeline_names.add(item.name)

        for i, rule in enumerate(self.diverge_rules, 1):
            # Check from_step exists in timeline
            if rule.from_step.name not in timeline_names:
                self.report.add_error(
                    f"Diverge rule {i}: from_step '{rule.from_step.name}' "
                    f"not found in timeline. Available steps: {list(timeline_names)}"
                )

            # Check patterns
            if not rule.patterns:
                self.report.add_error(
                    f"Diverge rule {i}: patterns dict is empty. "
                    f"Provide at least one pattern."
                )
                continue

            for pattern_key, pattern_value in rule.patterns.items():
                # Check pattern key is non-empty
                if not pattern_key or not isinstance(pattern_key, str):
                    self.report.add_error(
                        f"Diverge rule {i}: pattern key must be non-empty string, "
                        f"got {repr(pattern_key)}"
                    )

                # Check pattern value is valid
                if not isinstance(pattern_value, (StepMetadata, StepComposition)):
                    self.report.add_error(
                        f"Diverge rule {i}: pattern '{pattern_key}' has invalid value. "
                        f"Expected StepMetadata or StepComposition, "
                        f"got {type(pattern_value).__name__}"
                    )

    def _validate_branch_rules(self) -> None:
        """Validate branch rules.

        Checks:
        1. after step exists in timeline
        2. condition is callable
        3. when_true and when_false are valid StepMetadata

        Adds errors for any issues found.
        """
        from .decorators import StepMetadata

        timeline_names = self._get_timeline_names()

        for i, rule in enumerate(self.branch_rules, 1):
            # Check after step exists in timeline
            if rule.after.name not in timeline_names:
                self.report.add_error(
                    f"Branch rule {i}: after step '{rule.after.name}' "
                    f"not found in timeline. Available steps: {list(timeline_names)}"
                )

            # Check condition is callable
            if not callable(rule.condition):
                self.report.add_error(
                    f"Branch rule {i}: condition must be callable, "
                    f"got {type(rule.condition).__name__}"
                )

            # Check when_true is valid
            if not isinstance(rule.when_true, StepMetadata):
                self.report.add_error(
                    f"Branch rule {i}: when_true must be StepMetadata, "
                    f"got {type(rule.when_true).__name__}"
                )

            # Check when_false is valid
            if not isinstance(rule.when_false, StepMetadata):
                self.report.add_error(
                    f"Branch rule {i}: when_false must be StepMetadata, "
                    f"got {type(rule.when_false).__name__}"
                )

    def _validate_parameter_signatures(self) -> None:
        """Validate step parameter signatures.

        Checks:
        1. First parameter is 'context'
        2. Dependencies reference valid steps
        3. Return value contract (steps should return {"ok": ...} or {"error": ...})

        Note: Return value validation is runtime, so we only add warnings here.

        Adds errors/warnings for any issues found.
        """
        from .decorators import StepMetadata

        # Collect all step names across timeline, diverge, and branch
        all_steps: Dict[str, StepMetadata] = {}
        for step in self._get_all_steps():
            all_steps[step.name] = step

        # Add steps from diverge rules
        from .composition import StepComposition
        for rule in self.diverge_rules:
            for pattern_value in rule.patterns.values():
                if isinstance(pattern_value, StepComposition):
                    for step in pattern_value.steps:
                        all_steps[step.name] = step
                elif isinstance(pattern_value, StepMetadata):
                    all_steps[pattern_value.name] = pattern_value

        # Add steps from branch rules
        for rule in self.branch_rules:
            all_steps[rule.when_true.name] = rule.when_true
            all_steps[rule.when_false.name] = rule.when_false

        all_step_names = set(all_steps.keys())

        # Validate each step's parameters
        for step_name, step in all_steps.items():
            # Check first parameter is 'context'
            if step.parameters and step.parameters[0] != 'context':
                self.report.add_error(
                    f"Step '{step_name}': first parameter must be 'context', "
                    f"got '{step.parameters[0]}'"
                )

            # Check dependencies reference valid steps or 'inputs'
            for dep in step.dependencies:
                if dep not in all_step_names and dep != 'inputs':
                    self.report.add_error(
                        f"Step '{step_name}': depends on '{dep}' which does not exist. "
                        f"Available steps: {list(all_step_names)}"
                    )

            # Add warning about return value contract
            # (We can't validate this at definition time, only at runtime)
            # This is just a reminder in the docstring

    def _validate_execution_readiness(self) -> None:
        """Validate workflow is ready for execution.

        Checks:
        1. At least one step with 'inputs' parameter (entry point)
        2. All steps are async functions

        Adds errors for any issues found.
        """
        # Check for at least one entry point (step with 'inputs')
        has_entry_point = any(step.has_inputs for step in self._get_all_steps())

        if not has_entry_point:
            self.report.add_warning(
                f"Workflow '{self.workflow_name}' has no entry point. "
                f"At least one step should have 'inputs' parameter to receive workflow input."
            )

        # Check all steps are async
        for step in self._get_all_steps():
            if not inspect.iscoroutinefunction(step.function):
                self.report.add_error(
                    f"Step '{step.name}' is not async. "
                    f"All steps must be async functions."
                )

    def _check_unreachable_steps(self) -> None:
        """Detect unreachable steps (steps that can never execute).

        Uses dependency graph to find steps that:
        1. Are not in timeline
        2. Are not reachable from timeline via diverge/branch rules

        Adds warnings (not errors) for unreachable steps.
        """
        from .analyzer import DependencyAnalyzer
        from .composition import StepComposition

        # Collect all steps
        timeline_names = self._get_timeline_names()
        all_steps: Set[str] = set(timeline_names)

        # Add steps from diverge rules
        for rule in self.diverge_rules:
            for pattern_value in rule.patterns.values():
                if isinstance(pattern_value, StepComposition):
                    for step in pattern_value.steps:
                        all_steps.add(step.name)
                else:
                    all_steps.add(pattern_value.name)

        # Add steps from branch rules
        for rule in self.branch_rules:
            all_steps.add(rule.when_true.name)
            all_steps.add(rule.when_false.name)

        # Find steps that are not in timeline
        non_timeline_steps = all_steps - timeline_names

        # These are potentially unreachable unless they're targets of diverge/branch
        reachable_from_diverge = set()
        for rule in self.diverge_rules:
            if rule.from_step.name in timeline_names:
                for pattern_value in rule.patterns.values():
                    if isinstance(pattern_value, StepComposition):
                        for step in pattern_value.steps:
                            reachable_from_diverge.add(step.name)
                    else:
                        reachable_from_diverge.add(pattern_value.name)

        reachable_from_branch = set()
        for rule in self.branch_rules:
            if rule.after.name in timeline_names:
                reachable_from_branch.add(rule.when_true.name)
                reachable_from_branch.add(rule.when_false.name)

        reachable = timeline_names | reachable_from_diverge | reachable_from_branch

        # Unreachable steps
        unreachable = all_steps - reachable

        if unreachable:
            self.report.add_warning(
                f"Steps defined but potentially unreachable: {list(unreachable)}. "
                f"These steps are not in the timeline and not directly referenced "
                f"by diverge/branch rules from timeline steps."
            )

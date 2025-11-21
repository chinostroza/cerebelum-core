"""Serialization of DSL workflows to WorkflowDefinition format.

Converts new DSL structures (WorkflowBuilder, dsl.DivergeRule, dsl.BranchRule)
to legacy WorkflowDefinition format for compatibility with existing serialization
and execution infrastructure.
"""

from typing import Dict, List, Any, TYPE_CHECKING
import inspect

if TYPE_CHECKING:
    from .builder import WorkflowBuilder, DivergeRule, BranchRule
    from .decorators import StepMetadata
    from .composition import StepComposition

# Import legacy types
from ..types import (
    WorkflowDefinition,
    StepMetadata as LegacyStepMetadata,
    DivergeRule as LegacyDivergeRule,
    BranchRule as LegacyBranchRule,
    PatternMatch,
    ConditionBranch,
    BranchAction,
    ActionType,
)


class DSLSerializer:
    """Serializes DSL workflows to legacy WorkflowDefinition format.

    This bridges the new declarative DSL with the existing execution
    and serialization infrastructure.

    Example:
        >>> builder = WorkflowBuilder("my_workflow")
        >>> builder.timeline(step1 >> step2)
        >>> definition = DSLSerializer.to_workflow_definition(builder)
        >>> json_str = BlueprintSerializer.to_json(definition)
    """

    @staticmethod
    def to_workflow_definition(
        workflow_name: str,
        builder: "WorkflowBuilder",
    ) -> WorkflowDefinition:
        """Convert DSL builder to legacy WorkflowDefinition.

        Args:
            workflow_name: Name of the workflow
            builder: WorkflowBuilder instance with timeline, diverge, branch rules

        Returns:
            WorkflowDefinition compatible with existing infrastructure

        Example:
            >>> definition = DSLSerializer.to_workflow_definition(
            ...     "user_workflow",
            ...     builder
            ... )
        """
        # Collect all steps
        all_steps: Dict[str, "StepMetadata"] = {}

        # Add timeline steps (flattened)
        for step in builder.get_all_steps():
            all_steps[step.name] = step

        # Add steps from diverge rules
        from .composition import StepComposition
        for rule in builder.get_diverge_rules():
            # Add from_step
            if rule.from_step.name not in all_steps:
                all_steps[rule.from_step.name] = rule.from_step

            # Add pattern targets
            for pattern_value in rule.patterns.values():
                if isinstance(pattern_value, StepComposition):
                    for step in pattern_value.steps:
                        if step.name not in all_steps:
                            all_steps[step.name] = step
                else:
                    # Single StepMetadata
                    if pattern_value.name not in all_steps:
                        all_steps[pattern_value.name] = pattern_value

        # Add steps from branch rules
        for rule in builder.get_branch_rules():
            if rule.after.name not in all_steps:
                all_steps[rule.after.name] = rule.after
            if rule.when_true.name not in all_steps:
                all_steps[rule.when_true.name] = rule.when_true
            if rule.when_false.name not in all_steps:
                all_steps[rule.when_false.name] = rule.when_false

        # Create timeline (flattened - for backward compatibility)
        timeline = [step.name for step in builder.get_all_steps()]

        # Create timeline_structure (preserves parallel groups)
        from .composition import ParallelStepGroup
        timeline_structure = []
        for item in builder.get_timeline():
            if isinstance(item, ParallelStepGroup):
                # Parallel group - list of step names
                timeline_structure.append([step.name for step in item.steps])
            else:
                # Single step - just the name
                timeline_structure.append(item.name)

        # Store DSL StepMetadata directly (not legacy format)
        # This preserves has_context, has_inputs, and other DSL-specific attributes
        steps_metadata = all_steps

        diverge_rules = [
            DSLSerializer._convert_diverge_rule(rule)
            for rule in builder.get_diverge_rules()
        ]

        branch_rules = [
            DSLSerializer._convert_branch_rule(rule)
            for rule in builder.get_branch_rules()
        ]

        return WorkflowDefinition(
            id=workflow_name,
            timeline=timeline,
            steps_metadata=steps_metadata,
            diverge_rules=diverge_rules,
            branch_rules=branch_rules,
            timeline_structure=timeline_structure,
            inputs={},
        )

    @staticmethod
    def _convert_diverge_rule(rule: "DivergeRule") -> LegacyDivergeRule:
        """Convert DSL DivergeRule to legacy format.

        Args:
            rule: DSL DivergeRule

        Returns:
            Legacy DivergeRule
        """
        from .composition import StepComposition

        patterns = []
        for pattern_key, pattern_value in rule.patterns.items():
            if isinstance(pattern_value, StepComposition):
                # For compositions, use the first step as target
                # (The engine will need to handle composition execution)
                target = pattern_value.steps[0].name
            else:
                # Single step
                target = pattern_value.name

            patterns.append(PatternMatch(pattern=pattern_key, target=target))

        return LegacyDivergeRule(
            from_step=rule.from_step.name,
            patterns=patterns,
        )

    @staticmethod
    def _convert_branch_rule(rule: "BranchRule") -> LegacyBranchRule:
        """Convert DSL BranchRule to legacy format.

        Args:
            rule: DSL BranchRule

        Returns:
            Legacy BranchRule

        Note:
            The condition function is stored as a string identifier.
            For proper execution, the condition function needs to be
            registered and available at runtime.
        """
        # For now, use a string representation of the condition
        # In a full implementation, this would need proper serialization
        # or a registry of condition functions
        condition_name = getattr(rule.condition, '__name__', 'anonymous_condition')

        branches = [
            ConditionBranch(
                condition=f"{condition_name}==true",
                action=BranchAction(
                    type=ActionType.SKIP_TO,
                    target_step=rule.when_true.name,
                ),
            ),
            ConditionBranch(
                condition=f"{condition_name}==false",
                action=BranchAction(
                    type=ActionType.SKIP_TO,
                    target_step=rule.when_false.name,
                ),
            ),
        ]

        return LegacyBranchRule(
            from_step=rule.after.name,
            branches=branches,
        )

    @staticmethod
    def serialize_to_json(workflow_name: str, builder: "WorkflowBuilder") -> str:
        """Serialize DSL workflow to JSON blueprint.

        Convenience method that combines DSL conversion and JSON serialization.

        Args:
            workflow_name: Name of the workflow
            builder: WorkflowBuilder instance

        Returns:
            JSON string representation

        Example:
            >>> json_str = DSLSerializer.serialize_to_json("my_workflow", builder)
        """
        from ..blueprint import BlueprintSerializer

        definition = DSLSerializer.to_workflow_definition(workflow_name, builder)
        return BlueprintSerializer.to_json(definition)

    @staticmethod
    def serialize_to_dict(workflow_name: str, builder: "WorkflowBuilder") -> Dict[str, Any]:
        """Serialize DSL workflow to dictionary.

        Convenience method that combines DSL conversion and dict serialization.

        Args:
            workflow_name: Name of the workflow
            builder: WorkflowBuilder instance

        Returns:
            Dictionary representation

        Example:
            >>> blueprint = DSLSerializer.serialize_to_dict("my_workflow", builder)
        """
        from ..blueprint import BlueprintSerializer

        definition = DSLSerializer.to_workflow_definition(workflow_name, builder)
        return BlueprintSerializer.to_dict(definition)

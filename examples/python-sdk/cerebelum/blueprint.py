"""Blueprint serialization for Cerebelum workflows."""
from __future__ import annotations

import hashlib
import json
from typing import Any, Dict, List

from .types import WorkflowDefinition


class BlueprintSerializer:
    """Serializes workflow definitions to JSON blueprint format.

    The blueprint format is compatible with the Cerebelum Core gRPC API.
    """

    @staticmethod
    def to_json(workflow: WorkflowDefinition) -> str:
        """Serialize workflow to JSON blueprint.

        Args:
            workflow: Workflow definition to serialize

        Returns:
            JSON string representation of the blueprint
        """
        blueprint = BlueprintSerializer.to_dict(workflow)
        return json.dumps(blueprint, indent=2, sort_keys=True)

    @staticmethod
    def to_dict(workflow: WorkflowDefinition) -> Dict[str, Any]:
        """Convert workflow to blueprint dictionary.

        Args:
            workflow: Workflow definition to convert

        Returns:
            Dictionary representation compatible with gRPC API
        """
        # Build timeline
        timeline = []
        for step_name in workflow.timeline:
            step_meta = workflow.steps_metadata.get(step_name)
            if step_meta:
                # Handle both legacy (depends_on) and DSL (dependencies) formats
                deps = getattr(step_meta, 'depends_on', None) or getattr(step_meta, 'dependencies', [])
                timeline.append({"name": step_name, "depends_on": deps})
            else:
                timeline.append({"name": step_name, "depends_on": []})

        # Build diverge rules
        diverge_rules = [
            {
                "from_step": rule.from_step,
                "patterns": [
                    {"pattern": pattern.pattern, "target": pattern.target}
                    for pattern in rule.patterns
                ],
            }
            for rule in workflow.diverge_rules
        ]

        # Build branch rules
        branch_rules = [
            {
                "from_step": rule.from_step,
                "branches": [
                    {
                        "condition": branch.condition,
                        "action": {
                            "type": branch.action.type.value,
                            "target_step": branch.action.target_step,
                        },
                    }
                    for branch in rule.branches
                ],
            }
            for rule in workflow.branch_rules
        ]

        # Build complete definition
        definition = {
            "timeline": timeline,
            "diverge_rules": diverge_rules,
            "branch_rules": branch_rules,
            "inputs": workflow.inputs,
        }

        # Calculate workflow hash
        workflow_hash = BlueprintSerializer.compute_hash(workflow)

        # Build blueprint
        blueprint = {
            "workflow_module": workflow.id,
            "language": "python",
            "definition": definition,
            "version": workflow_hash,
        }

        return blueprint

    @staticmethod
    def compute_hash(workflow: WorkflowDefinition) -> str:
        """Compute SHA256 hash of workflow for versioning.

        Args:
            workflow: Workflow definition

        Returns:
            Hex-encoded SHA256 hash
        """
        # Create stable representation for hashing
        hash_input = {
            "workflow_module": workflow.id,
            "language": "python",
            "timeline": sorted(workflow.timeline),
            "diverge_rules": sorted(
                [
                    {
                        "from_step": rule.from_step,
                        "patterns": sorted(
                            [
                                {"pattern": p.pattern, "target": p.target}
                                for p in rule.patterns
                            ],
                            key=lambda x: x["pattern"],
                        ),
                    }
                    for rule in workflow.diverge_rules
                ],
                key=lambda x: x["from_step"],
            ),
            "branch_rules": sorted(
                [
                    {
                        "from_step": rule.from_step,
                        "branches": sorted(
                            [
                                {
                                    "condition": b.condition,
                                    "action": {
                                        "type": b.action.type.value,
                                        "target_step": b.action.target_step,
                                    },
                                }
                                for b in rule.branches
                            ],
                            key=lambda x: x["condition"],
                        ),
                    }
                    for rule in workflow.branch_rules
                ],
                key=lambda x: x["from_step"],
            ),
        }

        # Convert to JSON and hash
        json_str = json.dumps(hash_input, sort_keys=True)
        return hashlib.sha256(json_str.encode()).hexdigest()

    @staticmethod
    def from_json(json_str: str) -> Dict[str, Any]:
        """Deserialize JSON blueprint to dictionary.

        Args:
            json_str: JSON blueprint string

        Returns:
            Blueprint dictionary

        Note:
            This returns a dict, not a WorkflowDefinition, because
            the blueprint doesn't contain the actual step functions.
        """
        return json.loads(json_str)

"""Dependency analysis for workflow steps.

Provides dependency graph construction, cycle detection, topological sorting,
and parallel execution group detection.
"""

from dataclasses import dataclass, field
from typing import Set, Dict, List, Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from .decorators import StepMetadata


@dataclass
class DependencyNode:
    """Node in the dependency graph.

    Attributes:
        step: StepMetadata instance
        dependencies: Set of step names this node depends on
        dependents: Set of step names that depend on this node
    """

    step: "StepMetadata"
    dependencies: Set[str] = field(default_factory=set)
    dependents: Set[str] = field(default_factory=set)


class DependencyGraph:
    """Dependency graph for workflow steps.

    Manages the graph of step dependencies and provides algorithms for
    cycle detection, topological sorting, and parallel group detection.

    Complexity:
        - Cycle detection: O(V + E) using DFS
        - Topological sort: O(V + E) using Kahn's algorithm
        - Parallel groups: O(V) grouping by dependency sets
    """

    def __init__(self):
        """Initialize empty dependency graph."""
        self.nodes: Dict[str, DependencyNode] = {}

    def add_step(self, step: "StepMetadata") -> None:
        """Add a step to the graph.

        Args:
            step: StepMetadata instance to add

        Note:
            Dependencies are extracted from the step's metadata.
            Edges are built later by build_edges().
        """
        self.nodes[step.name] = DependencyNode(
            step=step,
            dependencies=set(step.dependencies),
            dependents=set(),
        )

    def build_edges(self) -> None:
        """Build dependency edges between nodes.

        For each dependency in each node, adds a reverse edge
        (dependent) to the referenced node.

        Raises:
            ValueError: If a step depends on a non-existent step
        """
        for name, node in self.nodes.items():
            for dep_name in node.dependencies:
                if dep_name not in self.nodes:
                    available = list(self.nodes.keys())
                    raise ValueError(
                        f"Step '{name}' depends on '{dep_name}' which does not exist. "
                        f"Available steps: {available}"
                    )
                # Add reverse edge (dependent)
                self.nodes[dep_name].dependents.add(name)

    def detect_cycles(self) -> Optional[List[str]]:
        """Detect circular dependencies using DFS.

        Uses depth-first search with recursion stack to detect cycles.
        This is the standard cycle detection algorithm for directed graphs.

        Returns:
            None if no cycle exists, otherwise list of step names in cycle

        Complexity:
            O(V + E) where V = vertices (steps), E = edges (dependencies)

        Example:
            >>> graph.detect_cycles()
            ['step_a', 'step_b', 'step_c', 'step_a']  # Cycle found
        """
        visited: Set[str] = set()
        rec_stack: Set[str] = set()

        def dfs(node_name: str, path: List[str]) -> Optional[List[str]]:
            """DFS helper function.

            Args:
                node_name: Current node being visited
                path: Current path from root to this node

            Returns:
                Cycle path if found, None otherwise
            """
            visited.add(node_name)
            rec_stack.add(node_name)
            path.append(node_name)

            node = self.nodes[node_name]
            for dep in node.dependencies:
                if dep not in visited:
                    # Recursively visit unvisited dependency
                    cycle = dfs(dep, path.copy())
                    if cycle:
                        return cycle
                elif dep in rec_stack:
                    # Found a cycle!
                    # Extract the cycle from the path
                    cycle_start = path.index(dep)
                    return path[cycle_start:] + [dep]

            rec_stack.remove(node_name)
            return None

        # Try DFS from each unvisited node
        for node_name in self.nodes:
            if node_name not in visited:
                cycle = dfs(node_name, [])
                if cycle:
                    return cycle

        return None

    def topological_sort(self) -> List[str]:
        """Return steps in topological order (dependencies first).

        Uses Kahn's algorithm for topological sorting.
        Steps with no dependencies come first, followed by steps
        that depend only on earlier steps.

        Returns:
            List of step names in dependency order

        Raises:
            ValueError: If circular dependency exists

        Complexity:
            O(V + E) where V = vertices, E = edges

        Example:
            >>> # Given: a -> b -> c
            >>> graph.topological_sort()
            ['a', 'b', 'c']  # a has no deps, b depends on a, c depends on b
        """
        # Check for cycles first
        cycle = self.detect_cycles()
        if cycle:
            cycle_str = " -> ".join(cycle)
            raise ValueError(
                f"Circular dependency detected: {cycle_str}\n"
                f"Suggestion: Remove one of the dependencies to break the cycle."
            )

        # Kahn's algorithm
        # in_degree[node] = number of incoming edges (dependencies)
        in_degree = {
            name: len(node.dependencies)
            for name, node in self.nodes.items()
        }

        # Queue of nodes with no dependencies
        queue = [name for name, deg in in_degree.items() if deg == 0]
        result = []

        while queue:
            # Sort for deterministic order
            # This ensures same input always produces same output
            queue.sort()
            node_name = queue.pop(0)
            result.append(node_name)

            # Decrease in-degree for all dependents
            for dependent in self.nodes[node_name].dependents:
                in_degree[dependent] -= 1
                if in_degree[dependent] == 0:
                    queue.append(dependent)

        return result

    def find_parallel_groups(self) -> List[Set[str]]:
        """Find groups of steps that can execute in parallel.

        Steps can execute in parallel if they have identical dependency sets.
        For example, if steps A and B both depend only on step X,
        they can run in parallel.

        Returns:
            List of sets, where each set contains step names that can
            run in parallel. Only groups with 2+ steps are returned.

        Complexity:
            O(V) where V = number of steps

        Example:
            >>> # Given:
            >>> # - send_email depends on [order]
            >>> # - send_sms depends on [order]
            >>> # - update_inventory depends on [order]
            >>> graph.find_parallel_groups()
            [{'send_email', 'send_sms', 'update_inventory'}]
        """
        # Group steps by their dependency set
        # Use frozenset as dict key (sets are not hashable)
        groups: Dict[frozenset, Set[str]] = {}

        for name, node in self.nodes.items():
            dep_key = frozenset(node.dependencies)
            if dep_key not in groups:
                groups[dep_key] = set()
            groups[dep_key].add(name)

        # Return only groups with 2+ steps
        return [group for group in groups.values() if len(group) > 1]


class DependencyAnalyzer:
    """Analyzes workflow dependencies.

    This is the main entry point for dependency analysis.
    It builds a complete dependency graph from timeline, diverge, and branch rules.
    """

    @staticmethod
    def analyze(
        timeline: List["StepMetadata"],
        diverge_rules: Optional[List] = None,
        branch_rules: Optional[List] = None,
    ) -> DependencyGraph:
        """Analyze workflow dependencies.

        Builds a complete dependency graph including all steps from
        timeline, diverge patterns, and branch targets.

        Args:
            timeline: Main timeline steps
            diverge_rules: Pattern matching rules (optional)
            branch_rules: Conditional routing rules (optional)

        Returns:
            DependencyGraph with all steps and edges

        Raises:
            ValueError: If dependencies are invalid or circular

        Example:
            >>> graph = DependencyAnalyzer.analyze(
            ...     timeline=[step1, step2, step3],
            ...     diverge_rules=[],
            ...     branch_rules=[]
            ... )
            >>> sorted_steps = graph.topological_sort()
        """
        from .composition import StepComposition

        graph = DependencyGraph()
        diverge_rules = diverge_rules or []
        branch_rules = branch_rules or []

        # Add all steps from timeline
        from .composition import ParallelStepGroup
        for item in timeline:
            if isinstance(item, ParallelStepGroup):
                # Parallel group - add all steps
                for step in item.steps:
                    if step.name not in graph.nodes:
                        graph.add_step(step)
            else:
                # Single step
                if item.name not in graph.nodes:
                    graph.add_step(item)

        # Add steps from diverge patterns
        for rule in diverge_rules:
            # Add from_step
            if rule.from_step.name not in graph.nodes:
                graph.add_step(rule.from_step)

            # Add pattern targets
            for pattern_value in rule.patterns.values():
                if isinstance(pattern_value, StepComposition):
                    # Composition: add all steps
                    for step in pattern_value.steps:
                        if step.name not in graph.nodes:
                            graph.add_step(step)
                else:
                    # Single step (StepMetadata)
                    if pattern_value.name not in graph.nodes:
                        graph.add_step(pattern_value)

        # Add steps from branch rules
        for rule in branch_rules:
            # Add after step
            if rule.after.name not in graph.nodes:
                graph.add_step(rule.after)

            # Add when_true step
            if rule.when_true.name not in graph.nodes:
                graph.add_step(rule.when_true)

            # Add when_false step
            if rule.when_false.name not in graph.nodes:
                graph.add_step(rule.when_false)

        # Build edges
        graph.build_edges()

        # Validate (detect cycles)
        cycle = graph.detect_cycles()
        if cycle:
            cycle_str = " -> ".join(cycle)
            raise ValueError(
                f"Circular dependency detected: {cycle_str}\n"
                f"Suggestion: Remove one of the dependencies to break the cycle."
            )

        return graph

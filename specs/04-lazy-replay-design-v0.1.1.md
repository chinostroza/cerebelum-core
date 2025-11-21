# Design Document - Lazy Replay & Forking (v0.1.1)

**Module:** cerebelum-core
**Target Version:** 0.1.1
**Status:** Draft
**Related to:** [Requirement 20: Horizontal Scalability](./01-requirements.md)

## Overview

This document outlines the architecture for **Lazy Replay** and **Execution Forking**, key features for the v0.1.1 release. These features enable "Time Travel" for AI agents, allowing for efficient exploration of alternative execution paths ("Tree of Thoughts") without re-executing costly side effects.

## Core Concepts

### 1. Lazy Replay (Time Travel)

Instead of storing heavy snapshots of the entire application state at every step, we rely on **Event Sourcing** as the source of truth. State is derived dynamically by replaying events.

*   **Concept:** `State = f(Events)`
*   **Mechanism:** To restore an execution to step N, we spawn a fresh process and apply events 0..N.
*   **Optimization:** "Lazy" means we only replay when necessary (e.g., on worker startup, crash recovery, or explicit fork request).

### 2. Side Effect Barrier (Command/Event Pattern)

To guarantee determinism during replay, the workflow logic must be strictly separated from side effects.

*   **Pure Core (The Brain):** Deterministic reducer. `(State, Event) -> (NewState, Commands)`
*   **Shell (The Body):** Executes commands (IO) and generates events. `Command -> IO -> Event`

**Rules:**
1.  The Core NEVER executes IO.
2.  The Core NEVER calls `System.system_time()` or `UUID.generate()` directly (these must be passed as inputs or handled by the Shell).
3.  During Replay, the Shell **intercepts** commands that have already been executed (checked against History) and **skips** them, immediately applying the corresponding recorded Event.

### 3. Execution Forking

The ability to branch an execution history into a new, independent path.

*   **Use Case:** "Tree of Thoughts" - An agent tries 3 different reasoning approaches from the same starting point.
*   **Mechanism:**
    1.  Identify `source_execution_id` and `version` (divergence point).
    2.  Create `new_execution_id`.
    3.  Copy events `0..version` from Source to New.
    4.  Inject a **Divergent Event** (e.g., a corrected input or a mock response) into New.
    5.  Resume execution of New.

## Implementation Design

### Data Structures

#### 1. Fork Metadata
Track the lineage of executions.

```elixir
defmodule Cerebelum.Execution.ForkMetadata do
  defstruct [
    :parent_execution_id,
    :fork_version,  # The version number where the fork occurred
    :fork_reason    # e.g., "user_correction", "tree_of_thoughts_branch_A"
  ]
end
```

### Components

#### 1. `Cerebelum.Execution.Forker`

Service responsible for creating forks.

```elixir
defmodule Cerebelum.Execution.Forker do
  alias Cerebelum.EventStore

  def fork_execution(source_id, target_version, opts \\ []) do
    new_id = UUID.uuid4()
    
    # 1. Fetch events up to target_version
    events = EventStore.get_events(source_id, up_to: target_version)
    
    # 2. Append "Forked" event to new stream (metadata)
    fork_event = Events.ExecutionForked.new(source_id, target_version)
    EventStore.append(new_id, fork_event, 0)
    
    # 3. Re-append historical events to new stream
    # Note: In a naive implementation, we copy. 
    # In optimized (v0.2), we might use "Copy-on-Write" or pointers.
    Enum.each(events, fn event -> 
      EventStore.append(new_id, event, event.version) 
    end)
    
    {:ok, new_id}
  end
end
```

#### 2. `Cerebelum.Execution.Engine` (Modifications)

Update `init/1` to support "Replay Mode" explicitly.

```elixir
def init(opts) do
  # ...
  if opts[:replay_until] do
    # Replay only up to a specific point, then pause/wait
    {:ok, :replaying, data}
  end
end
```

### API Changes

#### New API: Fork Execution

```elixir
Cerebelum.fork_execution(execution_id, version, opts)
```

*   `execution_id`: The ID of the execution to fork.
*   `version`: The event version number to fork *after*.
*   `opts`:
    *   `inject_event`: (Optional) An event to inject immediately after the fork point.
    *   `metadata`: Custom metadata for the new execution.

## Migration Strategy (v0.1.0 -> v0.1.1)

1.  **No Breaking Changes:** This is purely additive. Existing v0.1.0 workflows will continue to work.
2.  **EventStore Compatibility:** The `EventStore` schema (Postgres) remains the same. Forking is a logical operation on top of existing tables.
3.  **Performance:** Copying events for a fork is O(N). For v0.1.1, this is acceptable. For v0.2 (High Scale), we will investigate "Virtual Streams" where a stream is a pointer to a parent + a delta log.

## Future Considerations (v0.2+)

*   **Virtual Streams:** Avoid copying events. `Stream B` = `Stream A[0..50]` + `New Events`.
*   **Visual Debugger:** A UI to visualize the "Tree of Executions" and click to fork.

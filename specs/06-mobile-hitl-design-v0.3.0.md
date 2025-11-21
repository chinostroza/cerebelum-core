# Design Document - Mobile HITL (Human-in-the-Loop) (v0.3.0)

**Module:** cerebelum-core / cerebelum-mobile
**Target Version:** 0.3.0
**Status:** Draft

## Overview

This document outlines the architecture for **Native Human-in-the-Loop (HITL)** integration, leveraging Mobile (Kotlin Multiplatform) for offline-first, high-latency human interactions.

## Core Concepts

### 1. The Async Human Pattern

We treat the **Human** as an asynchronous, high-latency API service.
*   **Workflow State:** When a human approval is needed, the workflow **hibernates** (releases all compute resources).
*   **Wake-up Mechanism:** The workflow is rehydrated only when a specific "Signal" (callback) is received from the external world.

### 2. Offline-First Architecture

Unlike web-based approvals, the mobile architecture must support disconnected operation.
*   **Push:** Server pushes task to device.
*   **Queue:** Device queues task locally (Room/SQLDelight).
*   **Action:** User approves/rejects offline.
*   **Sync:** Device syncs decisions when connectivity is restored.

## Architecture

### 1. Workflow Definition (Python SDK)

```python
@step(activity_type="human_approval")
async def approve_expense(ctx, inputs):
    # Workflow hibernates here
    return await ctx.wait_for_signal(
        signal_name="approval_received",
        timeout="24h"
    )
```

### 2. Cerebelum Core (Elixir)

*   **Signal Detection:** Engine detects `wait_for_signal`.
*   **Notification Dispatch:**
    *   Lookup user device tokens (`UserRegistry`).
    *   Generate signed **Task Token**.
    *   Dispatch Data Notification (FCM/APNS) with payload: `{ "task_id": "...", "type": "EXPENSE_APPROVAL", "data": {...} }`.

### 3. Mobile SDK (Kotlin Multiplatform)

**Interface:**

```kotlin
Cerebelum.registerTaskHandler("EXPENSE_APPROVAL") { task ->
    val amount = task.data["amount"]
    
    // Native UI Logic
    val result = nativeUI.showApprovalDialog(
        title = "Aprobar Gasto",
        message = "Autorizar $amount?"
    )
    
    // Returns "APPROVED" | "REJECTED"
    // SDK handles offline queuing and retry logic
    return@registerTaskHandler result
}
```

**Responsibilities:**
*   **Background Sync:** `WorkManager` (Android) / `BGTaskScheduler` (iOS) to sync pending decisions.
*   **Security:** Biometric authentication (FaceID/TouchID) integration for signing approvals.
*   **Local Storage:** Persist pending tasks.

## API Extensions

### Core API
*   `POST /api/v1/tasks/sync` - Batch endpoint for mobile clients to upload decisions.
*   `POST /api/v1/signals/{signal_name}` - Internal endpoint to resume workflows.

## Benefits
1.  **Zero Latency UX:** No webview loading times.
2.  **Resilience:** Decisions are never lost, even without internet.
3.  **Compliance:** Biometric signing of approvals.

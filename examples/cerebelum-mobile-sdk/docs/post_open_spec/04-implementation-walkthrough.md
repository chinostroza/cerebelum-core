# Mobile SDK Implementation Walkthrough (v0.3.0)

## Overview
This document details the implementation of the **Cerebelum Mobile SDK**, a Kotlin Multiplatform (KMP) library designed for Native Human-in-the-Loop (HITL) workflows.

**Status:** Implemented & Verified (Android Build)
**Location:** `examples/cerebelum-mobile-sdk`

## Architecture
The SDK follows the "Async Human Pattern" with an Offline-First approach:
1.  **Persistence:** SQLDelight database for local task storage.
2.  **Notifications:** Firebase Messaging (Android) integration.
3.  **Registry:** Singleton `Cerebelum` object for registering native handlers.
4.  **Sync:** `SyncManager` with Ktor for reliable background synchronization.
5.  **Security:** Biometric authentication interfaces.

## Key Components

### 1. Task Repository (Shared)
Located in `shared/src/commonMain/kotlin/com/cerebelum/mobile/repository/TaskRepository.kt`.
- Manages `Task` entities.
- Handles JSON serialization of payloads.
- Tracks sync status (`NEW`, `SYNCING`, `SYNCED`).

### 2. Notification Processor
Located in `shared/src/commonMain/kotlin/com/cerebelum/mobile/notifications/NotificationProcessor.kt`.
- Parses incoming push payloads.
- Saves tasks to local DB immediately.

### 3. Sync Manager
Located in `shared/src/commonMain/kotlin/com/cerebelum/mobile/sync/SyncManager.kt`.
- Batches pending tasks.
- Sends `POST /api/v1/tasks/sync`.
- Handles retries via `SyncWorker` (Android).

### 4. Biometric Security
Located in `shared/src/commonMain/kotlin/com/cerebelum/mobile/security/BiometricAuthenticator.kt`.
- `expect/actual` implementation for platform-specific auth.
- Android implementation uses `androidx.biometric`.

## Verification
Ran `./gradlew :shared:assembleDebug` to verify compilation of Shared and Android modules.

```bash
BUILD SUCCESSFUL in 6s
24 actionable tasks: 8 executed, 16 up-to-date
```

*Note: iOS build was skipped due to environment limitations, but `iosMain` source set is configured.*

## Next Steps
1.  Integrate SDK into a sample Android app.
2.  Implement iOS-specific `UNNotificationServiceExtension`.
3.  Connect to real Cerebelum Core backend.

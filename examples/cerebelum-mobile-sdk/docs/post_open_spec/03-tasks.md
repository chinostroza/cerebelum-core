# Implementation Plan

- [ ] 1. Project Setup & Core Infrastructure
  - Initialize Kotlin Multiplatform project structure (Android/iOS/Shared)
  - Configure SQLDelight for local persistence
  - Configure Ktor Client for networking
  - Setup Serialization (kotlinx.serialization)
  - _Requirements: 1.3, 3.3_

- [ ] 2. Implement Local Persistence Layer
  - [ ] 2.1 Define Database Schema
    - Create `Task` table in SQLDelight (`id`, `type`, `payload`, `status`, `sync_status`)
    - Create `SyncAttempt` table for retry tracking
    - _Requirements: 1.3, 3.1_
  - [ ] 2.2 Implement TaskRepository
    - Implement `saveTask(task)`
    - Implement `getPendingTasks()`
    - Implement `markTaskCompleted(id, result)`
    - Write unit tests for repository logic
    - _Requirements: 1.3, 3.1_

- [ ] 3. Implement Notification Handling
  - [ ] 3.1 Android Implementation
    - Create `CerebelumMessagingService` extending `FirebaseMessagingService`
    - Parse incoming data payload
    - Call `TaskRepository.saveTask()`
    - Trigger local notification if backgrounded
    - _Requirements: 1.1, 1.2, 5.2_
  - [ ] 3.2 iOS Implementation
    - Implement `UNNotificationServiceExtension`
    - Handle background content fetch
    - Save task to shared database container
    - _Requirements: 1.1, 1.2, 5.2_

- [ ] 4. Implement Task Handler Registry
  - Create singleton `Cerebelum` object
  - Implement `registerTaskHandler(type, callback)`
  - Implement `dispatchTask(task)` logic to find and execute callbacks
  - Add error handling for missing handlers
  - _Requirements: 2.1, 2.2, 2.3_

- [ ] 5. Implement Synchronization Logic
  - [ ] 5.1 Sync Manager
    - Create `SyncManager` class
    - Implement `syncPendingTasks()`: read pending -> batch -> POST /sync -> update status
    - Handle API errors and mark for retry
    - _Requirements: 3.2, 3.3, 3.4_
  - [ ] 5.2 Background Schedulers
    - Android: Setup `WorkManager` PeriodicWorkRequest
    - iOS: Setup `BGAppRefreshTask`
    - _Requirements: 5.1_

- [ ] 6. Implement Biometric Security
  - Create `BiometricAuthenticator` interface in shared module
  - Android: Implement using `androidx.biometric`
  - iOS: Implement using `LocalAuthentication`
  - Integrate auth check before `markTaskCompleted`
  - _Requirements: 4.1, 4.2, 4.3_

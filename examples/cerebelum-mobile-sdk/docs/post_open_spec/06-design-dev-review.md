# Design Document - Refactoring & QA

## Overview
This document details the architectural changes required to transition the Cerebelum Mobile SDK to a **Clean Architecture** approach, ensuring SOLID principles and high testability.

## 1. Package Structure & Layers

We will restructure the `shared` module into three distinct layers:

```
com.cerebelum.mobile
├── domain                  # [Pure Kotlin] No dependencies on Android/SQLDelight
│   ├── model               # Data classes (Task, TaskStatus)
│   ├── repository          # Interfaces (TaskRepository)
│   └── usecase             # Business Logic (ProcessNotification, SyncTasks)
├── data                    # [Implementation] Depends on Domain
│   ├── local               # SQLDelight implementation
│   │   ├── DatabaseDriverFactory.kt
│   │   └── SqlDelightTaskRepository.kt
│   ├── remote              # Ktor implementation
│   │   └── KtorSyncService.kt
│   └── mapper              # Mappers (Entity <-> Domain)
└── presentation            # [Public API] Depends on Domain
    └── Cerebelum.kt        # SDK Entry Point (Facade)
```

## 2. Domain Layer (The Core)

### Models
Pure data classes. `Task` will be moved here and stripped of any framework-specific annotations (like `@Serializable` if possible, or kept if we treat it as a DTO, but ideally Domain models are pure).

### Repository Interfaces
```kotlin
interface TaskRepository {
    suspend fun saveTask(task: Task)
    suspend fun getPendingTasks(): List<Task>
    suspend fun markTaskCompleted(id: String, result: String)
    suspend fun updateSyncStatus(id: String, status: SyncStatus)
}
```

### Use Cases
Single-responsibility interactors.
- `ProcessNotificationUseCase(repo)`: Handles parsing and saving.
- `SyncTasksUseCase(repo, remoteService)`: Handles the sync logic (previously in `SyncManager`).
- `RegisterHandlerUseCase(registry)`: Manages callbacks.

## 3. Data Layer (The Infrastructure)

### Local Data Source
- **SqlDelightTaskRepository**: Implements `domain.TaskRepository`.
- **Mappers**: `TaskEntityMapper` converts SQLDelight generated classes to `domain.Task`.

### Remote Data Source
- **KtorSyncService**: Handles the HTTP calls. Decoupled from the Repository logic.

## 4. Dependency Injection (DI)
To maintain KMP simplicity without heavy frameworks (like Koin/Dagger) for this SDK size, we will use **Manual DI** via a `DependencyContainer`.

```kotlin
internal object DependencyContainer {
    val database by lazy { ... }
    val taskRepository by lazy { SqlDelightTaskRepository(database) }
    val syncService by lazy { KtorSyncService() }
    
    // Use Cases
    val processNotificationUseCase by lazy { ProcessNotificationUseCase(taskRepository) }
}
```

## 5. Testing Strategy

### Unit Tests (Domain)
- **Subject:** Use Cases.
- **Dependencies:** Fakes (e.g., `FakeTaskRepository` using `MutableList`).
- **Goal:** Verify business rules (e.g., "Don't save duplicate tasks", "Retry logic").

### Unit Tests (Data)
- **Subject:** `SqlDelightTaskRepository`.
- **Dependencies:** In-memory SQLDelight driver (`JdbcSqliteDriver` for JVM tests).
- **Goal:** Verify mapping and query correctness.

### Static Analysis (Detekt)
- **Config:** `detekt.yml` enabling `complexity`, `naming`, `potential-bugs`.
- **Baseline:** Generate baseline to ignore existing issues if necessary (though we aim to fix them).

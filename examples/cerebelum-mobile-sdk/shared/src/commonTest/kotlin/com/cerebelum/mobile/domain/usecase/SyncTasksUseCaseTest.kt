package com.cerebelum.mobile.domain.usecase

import com.cerebelum.mobile.domain.model.SyncStatus
import com.cerebelum.mobile.domain.model.Task
import com.cerebelum.mobile.domain.model.TaskStatus
import com.cerebelum.mobile.test.fakes.FakeSyncService
import com.cerebelum.mobile.test.fakes.FakeTaskRepository
import kotlinx.coroutines.test.runTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SyncTasksUseCaseTest {

    private lateinit var repository: FakeTaskRepository
    private lateinit var syncService: FakeSyncService
    private lateinit var useCase: SyncTasksUseCase

    @BeforeTest
    fun setup() {
        repository = FakeTaskRepository()
        syncService = FakeSyncService()
        useCase = SyncTasksUseCase(repository, syncService)
    }

    @Test
    fun `invoke syncs pending tasks and updates status to SYNCED on success`() = runTest {
        // Given
        val task = Task(
            id = "task-1",
            type = "test",
            payload = emptyMap(),
            status = TaskStatus.COMPLETED,
            syncStatus = SyncStatus.PENDING,
            result = "done"
        )
        repository.saveTask(task)

        // When
        useCase()

        // Then
        assertTrue(syncService.syncedTasks.contains(task))
        val updatedTask = repository.getAllTasks().first()
        assertEquals(SyncStatus.SYNCED, updatedTask.syncStatus)
    }

    @Test
    fun `invoke updates status to FAILED on sync failure`() = runTest {
        // Given
        syncService.shouldSucceed = false
        val task = Task(
            id = "task-1",
            type = "test",
            payload = emptyMap(),
            status = TaskStatus.COMPLETED,
            syncStatus = SyncStatus.PENDING,
            result = "done"
        )
        repository.saveTask(task)

        // When
        useCase()

        // Then
        assertTrue(syncService.syncedTasks.isEmpty())
        val updatedTask = repository.getAllTasks().first()
        assertEquals(SyncStatus.FAILED, updatedTask.syncStatus)
    }

    @Test
    fun `invoke does nothing if no pending sync tasks`() = runTest {
        // Given
        val task = Task(
            id = "task-1",
            type = "test",
            payload = emptyMap(),
            status = TaskStatus.COMPLETED,
            syncStatus = SyncStatus.SYNCED, // Already synced
            result = "done"
        )
        repository.saveTask(task)

        // When
        useCase()

        // Then
        assertTrue(syncService.syncedTasks.isEmpty())
    }
}

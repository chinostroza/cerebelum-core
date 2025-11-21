package com.cerebelum.mobile.domain.usecase

import com.cerebelum.mobile.domain.model.SyncStatus
import com.cerebelum.mobile.domain.repository.TaskRepository

class SyncTasksUseCase(
    private val taskRepository: TaskRepository,
    private val syncService: SyncService
) {
    @Suppress("TooGenericExceptionCaught", "SwallowedException")
    suspend operator fun invoke() {
        val pendingTasks = taskRepository.getPendingSyncTasks()
        if (pendingTasks.isEmpty()) return

        try {
            val success = syncService.syncTasks(pendingTasks)
            if (success) {
                pendingTasks.forEach { task ->
                    taskRepository.updateSyncStatus(task.id, SyncStatus.SYNCED)
                }
            } else {
                pendingTasks.forEach { task ->
                    taskRepository.updateSyncStatus(task.id, SyncStatus.FAILED)
                }
            }
        } catch (e: Exception) {
            // Log error
        }
    }
}

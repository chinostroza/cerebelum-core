package com.cerebelum.mobile.domain.usecase

import com.cerebelum.mobile.domain.model.SyncStatus
import com.cerebelum.mobile.domain.model.Task
import com.cerebelum.mobile.domain.model.TaskStatus
import com.cerebelum.mobile.domain.repository.TaskRepository

class ProcessNotificationUseCase(private val taskRepository: TaskRepository) {

    suspend operator fun invoke(taskId: String, type: String, payload: Map<String, String>) {
        val task = Task(
            id = taskId,
            type = type,
            payload = payload,
            status = TaskStatus.NEW,
            syncStatus = SyncStatus.NOT_SYNCED
        )
        taskRepository.saveTask(task)
    }
}

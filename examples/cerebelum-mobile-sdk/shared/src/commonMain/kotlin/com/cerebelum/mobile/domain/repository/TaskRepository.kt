package com.cerebelum.mobile.domain.repository

import com.cerebelum.mobile.domain.model.SyncStatus
import com.cerebelum.mobile.domain.model.Task

interface TaskRepository {
    suspend fun saveTask(task: Task)
    suspend fun getPendingTasks(): List<Task>
    suspend fun getPendingSyncTasks(): List<Task>
    suspend fun markTaskCompleted(id: String, result: String)
    suspend fun updateSyncStatus(id: String, status: SyncStatus)
}

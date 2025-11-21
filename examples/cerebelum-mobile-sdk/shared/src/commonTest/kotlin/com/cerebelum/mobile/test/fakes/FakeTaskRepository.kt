package com.cerebelum.mobile.test.fakes

import com.cerebelum.mobile.domain.model.SyncStatus
import com.cerebelum.mobile.domain.model.Task
import com.cerebelum.mobile.domain.model.TaskStatus
import com.cerebelum.mobile.domain.repository.TaskRepository

class FakeTaskRepository : TaskRepository {
    private val tasks = mutableListOf<Task>()

    override suspend fun saveTask(task: Task) {
        tasks.add(task)
    }

    override suspend fun getPendingTasks(): List<Task> {
        return tasks.filter { it.status != TaskStatus.COMPLETED }
    }

    override suspend fun getPendingSyncTasks(): List<Task> {
        return tasks.filter { it.syncStatus == SyncStatus.PENDING }
    }

    override suspend fun markTaskCompleted(id: String, result: String) {
        val index = tasks.indexOfFirst { it.id == id }
        if (index != -1) {
            val task = tasks[index]
            tasks[index] = task.copy(
                status = TaskStatus.COMPLETED,
                result = result
            )
        }
    }

    override suspend fun updateSyncStatus(id: String, status: SyncStatus) {
        val index = tasks.indexOfFirst { it.id == id }
        if (index != -1) {
            val task = tasks[index]
            tasks[index] = task.copy(syncStatus = status)
        }
    }
    
    // Helper for tests
    fun getAllTasks(): List<Task> = tasks.toList()
    fun clear() = tasks.clear()
}

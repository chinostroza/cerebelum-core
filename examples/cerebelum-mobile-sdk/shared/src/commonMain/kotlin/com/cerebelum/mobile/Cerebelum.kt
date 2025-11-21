package com.cerebelum.mobile

import com.cerebelum.mobile.data.local.DatabaseDriverFactory
import com.cerebelum.mobile.di.DependencyContainer
import com.cerebelum.mobile.domain.model.Task

object Cerebelum {
    private val handlers = mutableMapOf<String, suspend (Task) -> String>()

    fun initialize(databaseDriverFactory: DatabaseDriverFactory) {
        DependencyContainer.initialize(databaseDriverFactory)
    }

    fun registerTaskHandler(type: String, handler: suspend (Task) -> String) {
        handlers[type] = handler
    }

    @Suppress("TooGenericExceptionCaught", "SwallowedException")
    suspend fun processTask(task: Task) {
        val handler = handlers[task.type]
        if (handler != null) {
            try {
                val result = handler(task)
                DependencyContainer.getRepository().markTaskCompleted(task.id, result)
                // Trigger sync immediately or let background worker handle it
                // For now, let's try to sync if possible
                try {
                    DependencyContainer.syncTasksUseCase()
                } catch (e: Exception) {
                    // Ignore sync error here, worker will retry
                }
            } catch (e: Exception) {
                println("Error processing task ${task.id}: ${e.message}")
            }
        } else {
            println("No handler registered for task type: ${task.type}")
        }
    }

    fun getPendingTasks(): List<Task> = throw UnsupportedOperationException("Use getPendingTasksSuspend instead")

    suspend fun getPendingTasksSuspend(): List<Task> = DependencyContainer.getRepository().getPendingTasks()
}

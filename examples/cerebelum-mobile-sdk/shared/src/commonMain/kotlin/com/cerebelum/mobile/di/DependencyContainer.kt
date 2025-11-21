package com.cerebelum.mobile.di

import com.cerebelum.mobile.data.local.DatabaseDriverFactory
import com.cerebelum.mobile.data.remote.KtorSyncService
import com.cerebelum.mobile.data.repository.SqlDelightTaskRepository
import com.cerebelum.mobile.domain.repository.TaskRepository
import com.cerebelum.mobile.domain.usecase.ProcessNotificationUseCase
import com.cerebelum.mobile.domain.usecase.SyncTasksUseCase
import kotlin.native.concurrent.ThreadLocal

@ThreadLocal
object DependencyContainer {
    private var databaseDriverFactory: DatabaseDriverFactory? = null

    private val taskRepository: TaskRepository by lazy {
        val factory = databaseDriverFactory
        check(factory != null) { "Cerebelum SDK not initialized. Call Cerebelum.initialize() first." }
        SqlDelightTaskRepository(factory)
    }

    private val syncService by lazy {
        KtorSyncService()
    }

    val processNotificationUseCase by lazy {
        ProcessNotificationUseCase(taskRepository)
    }

    val syncTasksUseCase by lazy {
        SyncTasksUseCase(taskRepository, syncService)
    }

    fun initialize(driverFactory: DatabaseDriverFactory) {
        databaseDriverFactory = driverFactory
    }

    // Exposed for internal use if needed, but prefer Use Cases
    internal fun getRepository(): TaskRepository = taskRepository
}

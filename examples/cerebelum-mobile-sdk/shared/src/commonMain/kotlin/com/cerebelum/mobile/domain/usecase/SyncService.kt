package com.cerebelum.mobile.domain.usecase

import com.cerebelum.mobile.domain.model.Task

interface SyncService {
    suspend fun syncTasks(tasks: List<Task>): Boolean
}

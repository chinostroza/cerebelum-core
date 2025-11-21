package com.cerebelum.mobile.test.fakes

import com.cerebelum.mobile.domain.model.Task
import com.cerebelum.mobile.domain.usecase.SyncService

class FakeSyncService : SyncService {
    var shouldSucceed: Boolean = true
    val syncedTasks = mutableListOf<Task>()

    override suspend fun syncTasks(tasks: List<Task>): Boolean {
        if (shouldSucceed) {
            syncedTasks.addAll(tasks)
        }
        return shouldSucceed
    }
}

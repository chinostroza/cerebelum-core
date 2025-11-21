package com.cerebelum.mobile.data.repository

import com.cerebelum.mobile.data.local.CerebelumDatabase
import com.cerebelum.mobile.data.local.DatabaseDriverFactory
import com.cerebelum.mobile.data.mapper.TaskEntityMapper
import com.cerebelum.mobile.domain.model.SyncStatus
import com.cerebelum.mobile.domain.model.Task
import com.cerebelum.mobile.domain.model.TaskStatus
import com.cerebelum.mobile.domain.repository.TaskRepository

class SqlDelightTaskRepository(databaseDriverFactory: DatabaseDriverFactory) : TaskRepository {
    private val database = CerebelumDatabase(databaseDriverFactory.createDriver())
    private val dbQueries = database.cerebelumDatabaseQueries

    override suspend fun saveTask(task: Task) {
        val entity = TaskEntityMapper.toEntity(task)
        dbQueries.insertTask(
            id = entity.id,
            type = entity.type,
            payload = entity.payload,
            status = entity.status,
            sync_status = entity.sync_status,
            created_at = entity.created_at
        )
    }

    override suspend fun getPendingTasks(): List<Task> =
        dbQueries.selectAllTasks().executeAsList().map { TaskEntityMapper.toDomain(it) }

    override suspend fun getPendingSyncTasks(): List<Task> =
        dbQueries.selectPendingSyncTasks().executeAsList().map { TaskEntityMapper.toDomain(it) }

    @Suppress("ForbiddenComment", "MagicNumber")
    override suspend fun markTaskCompleted(id: String, result: String) {
        // TODO: Use proper timestamp
        val completedAt = 123_456_789L
        dbQueries.updateTaskStatus(
            status = TaskStatus.COMPLETED.name,
            completed_at = completedAt,
            result = result,
            id = id
        )
    }

    override suspend fun updateSyncStatus(id: String, status: SyncStatus) {
        dbQueries.updateSyncStatus(status.name, id)
    }
}

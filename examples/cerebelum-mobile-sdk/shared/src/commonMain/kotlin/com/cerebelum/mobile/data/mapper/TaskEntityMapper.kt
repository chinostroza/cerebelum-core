package com.cerebelum.mobile.data.mapper

import com.cerebelum.mobile.data.local.TaskEntity
import com.cerebelum.mobile.domain.model.SyncStatus
import com.cerebelum.mobile.domain.model.Task
import com.cerebelum.mobile.domain.model.TaskStatus
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

object TaskEntityMapper {
    @Suppress("TooGenericExceptionCaught", "SwallowedException")
    fun toDomain(entity: TaskEntity): Task {
        return Task(
            id = entity.id,
            type = entity.type,
            payload = try {
                Json.decodeFromString(entity.payload)
            } catch (e: Exception) {
                emptyMap()
            },
            status = TaskStatus.valueOf(entity.status),
            syncStatus = SyncStatus.valueOf(entity.sync_status),
            result = entity.result
        )
    }

    @Suppress("ForbiddenComment")
    fun toEntity(domain: Task): TaskEntity {
        return TaskEntity(
            id = domain.id,
            type = domain.type,
            payload = Json.encodeToString(domain.payload),
            status = domain.status.name,
            sync_status = domain.syncStatus.name,
            created_at = 0, // TODO: Add timestamp to domain model if needed
            completed_at = null,
            result = domain.result
        )
    }
}

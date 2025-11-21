package com.cerebelum.mobile.domain.model

data class Task(
    val id: String,
    val type: String,
    val payload: Map<String, String>,
    val status: TaskStatus,
    val syncStatus: SyncStatus,
    val result: String? = null
)

enum class TaskStatus {
    NEW, VIEWED, COMPLETED
}

enum class SyncStatus {
    NOT_SYNCED, SYNCING, SYNCED, FAILED
}

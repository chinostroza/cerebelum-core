package com.cerebelum.mobile.data.remote.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SyncBatchPayload(val tasks: List<SyncTaskPayload>)

@Serializable
data class SyncTaskPayload(
    @SerialName("task_id") val taskId: String,
    val result: String
)

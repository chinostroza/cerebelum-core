package com.cerebelum.mobile.data.remote

import com.cerebelum.mobile.data.remote.model.SyncBatchPayload
import com.cerebelum.mobile.data.remote.model.SyncTaskPayload
import com.cerebelum.mobile.domain.model.Task
import com.cerebelum.mobile.domain.usecase.SyncService
import io.ktor.client.HttpClient
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

class KtorSyncService : SyncService {

    private val client = HttpClient {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                prettyPrint = true
                isLenient = true
            })
        }
    }

    @Suppress("TooGenericExceptionCaught", "ForbiddenComment", "MagicNumber")
    override suspend fun syncTasks(tasks: List<Task>): Boolean {
        val payload = tasks.map {
            SyncTaskPayload(it.id, it.result ?: "")
        }

        return try {
            // TODO: Make URL configurable
            val response = client.post("https://api.cerebelum.io/v1/tasks/sync") {
                contentType(ContentType.Application.Json)
                setBody(SyncBatchPayload(payload))
            }
            response.status.value in 200..299
        } catch (e: Exception) {
            println("Sync failed: ${e.message}")
            false
        }
    }
}

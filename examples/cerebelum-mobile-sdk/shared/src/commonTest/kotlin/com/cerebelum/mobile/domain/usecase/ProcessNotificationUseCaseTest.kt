package com.cerebelum.mobile.domain.usecase

import com.cerebelum.mobile.domain.model.TaskStatus
import com.cerebelum.mobile.test.fakes.FakeTaskRepository
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals

class ProcessNotificationUseCaseTest {

    private val repository = FakeTaskRepository()
    private val useCase = ProcessNotificationUseCase(repository)

    @Test
    fun `invoke creates and saves task from notification data`() = runTest {
        val taskId = "task-123"
        val type = "human_review"
        val payload = mapOf("key" to "value", "foo" to "bar")

        useCase(taskId, type, payload)

        val tasks = repository.getAllTasks()
        assertEquals(1, tasks.size)
        
        val savedTask = tasks.first()
        assertEquals(taskId, savedTask.id)
        assertEquals(type, savedTask.type)
        assertEquals(payload, savedTask.payload)
        assertEquals(TaskStatus.PENDING, savedTask.status)
    }
}

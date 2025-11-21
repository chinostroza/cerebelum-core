package com.cerebelum.mobile.notifications

import com.cerebelum.mobile.di.DependencyContainer
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class CerebelumMessagingService : FirebaseMessagingService() {

    @Suppress("InjectDispatcher")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)

        if (remoteMessage.data.isNotEmpty()) {
            val data = remoteMessage.data
            val taskId = data["task_id"] ?: return
            val type = data["type"] ?: return
            // Simple map conversion, actual JSON parsing happens in UseCase/Mapper if needed
            // But UseCase expects Map<String, String> which data is.

            scope.launch {
                @Suppress("TooGenericExceptionCaught")
                try {
                    DependencyContainer.processNotificationUseCase(taskId, type, data)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }

    @Suppress("ForbiddenComment")
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        // TODO: Send token to server via a UseCase
    }
}

package com.cerebelum.mobile.security

import platform.LocalAuthentication.LAContext
import platform.LocalAuthentication.LAPolicyDeviceOwnerAuthenticationWithBiometrics
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

actual class BiometricAuthenticator {
    actual suspend fun authenticate(title: String, subtitle: String): Boolean {
        return suspendCoroutine { continuation ->
            val context = LAContext()
            val error = null
            
            // Note: Kotlin Native interop with ObjC pointers/errors is tricky
            // This is a conceptual implementation
            
            if (context.canEvaluatePolicy(LAPolicyDeviceOwnerAuthenticationWithBiometrics, null)) {
                context.evaluatePolicy(LAPolicyDeviceOwnerAuthenticationWithBiometrics, title) { success, _ ->
                    continuation.resume(success)
                }
            } else {
                continuation.resume(false)
            }
        }
    }
}

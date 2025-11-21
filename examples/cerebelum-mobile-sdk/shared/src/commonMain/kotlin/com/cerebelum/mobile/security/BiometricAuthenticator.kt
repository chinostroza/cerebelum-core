package com.cerebelum.mobile.security

expect class BiometricAuthenticator {
    suspend fun authenticate(title: String, subtitle: String): Boolean
}

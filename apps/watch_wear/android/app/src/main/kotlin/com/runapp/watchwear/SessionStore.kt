package com.runapp.watchwear

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.sessionDataStore by preferencesDataStore(name = "watch_wear_session")

/// On-disk cache of the last session pushed by the phone. Survives app
/// restart so a cold-launch while the phone is out of range still has
/// credentials to work with. The refresh token is the sensitive bit —
/// DataStore's per-app sandbox is an acceptable bar for Phase 1; if this
/// app later stores multi-user data, upgrade to EncryptedSharedPreferences
/// or the androidx.security.crypto DataStore wrapper.
data class StoredSession(
    val accessToken: String,
    val refreshToken: String,
    val userId: String,
    val baseUrl: String,
    val anonKey: String,
    val expiresAtMs: Long,
) {
    fun isExpired(nowMs: Long = System.currentTimeMillis()): Boolean =
        expiresAtMs > 0 && nowMs >= expiresAtMs - 60_000 // 1-min safety margin

    companion object {
        fun fromPayload(p: SessionPayload) = StoredSession(
            accessToken = p.accessToken,
            refreshToken = p.refreshToken,
            userId = p.userId,
            baseUrl = p.baseUrl,
            anonKey = p.anonKey,
            expiresAtMs = p.expiresAtMs,
        )
    }
}

private val KEY_ACCESS_TOKEN: Preferences.Key<String> = stringPreferencesKey("session_access_token")
private val KEY_REFRESH_TOKEN: Preferences.Key<String> = stringPreferencesKey("session_refresh_token")
private val KEY_USER_ID: Preferences.Key<String> = stringPreferencesKey("session_user_id")
private val KEY_BASE_URL: Preferences.Key<String> = stringPreferencesKey("session_base_url")
private val KEY_ANON_KEY: Preferences.Key<String> = stringPreferencesKey("session_anon_key")
private val KEY_EXPIRES_AT: Preferences.Key<Long> = longPreferencesKey("session_expires_at_ms")

class SessionStore(private val context: Context) {
    val session: Flow<StoredSession?> = context.sessionDataStore.data.map { prefs ->
        val access = prefs[KEY_ACCESS_TOKEN] ?: return@map null
        val refresh = prefs[KEY_REFRESH_TOKEN] ?: return@map null
        val user = prefs[KEY_USER_ID] ?: return@map null
        val baseUrl = prefs[KEY_BASE_URL] ?: return@map null
        val anonKey = prefs[KEY_ANON_KEY] ?: return@map null
        StoredSession(
            accessToken = access,
            refreshToken = refresh,
            userId = user,
            baseUrl = baseUrl,
            anonKey = anonKey,
            expiresAtMs = prefs[KEY_EXPIRES_AT] ?: 0,
        )
    }

    suspend fun current(): StoredSession? = session.first()

    suspend fun save(s: StoredSession) {
        context.sessionDataStore.edit { prefs ->
            prefs[KEY_ACCESS_TOKEN] = s.accessToken
            prefs[KEY_REFRESH_TOKEN] = s.refreshToken
            prefs[KEY_USER_ID] = s.userId
            prefs[KEY_BASE_URL] = s.baseUrl
            prefs[KEY_ANON_KEY] = s.anonKey
            prefs[KEY_EXPIRES_AT] = s.expiresAtMs
        }
    }

    suspend fun clear() {
        context.sessionDataStore.edit { prefs ->
            prefs.remove(KEY_ACCESS_TOKEN)
            prefs.remove(KEY_REFRESH_TOKEN)
            prefs.remove(KEY_USER_ID)
            prefs.remove(KEY_BASE_URL)
            prefs.remove(KEY_ANON_KEY)
            prefs.remove(KEY_EXPIRES_AT)
        }
    }
}

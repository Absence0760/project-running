package com.runapp.watchwear

import android.content.Context
import android.content.SharedPreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

/// On-disk cache of the last session pushed by the phone (or the
/// direct-sign-in result). Survives app restart so a cold-launch while
/// the phone is out of range still has credentials to work with.
///
/// **The access + refresh tokens are bearer credentials**: anyone who
/// reads them can impersonate the user against Supabase until they
/// expire (and the refresh token mints fresh access tokens
/// indefinitely). They therefore live in `EncryptedSharedPreferences`
/// (AES-256-GCM values keyed by an Android-Keystore-held master key),
/// not the plaintext-on-disk DataStore the rest of the app uses. The
/// whole session record is stored here — there's no cost to encrypting
/// the non-secret fields (`baseUrl`, `anonKey`, `userId`, expiry) too,
/// and keeping one store avoids a half-encrypted split.
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

// Legacy plaintext DataStore — the pre-encryption home of the session.
// Retained only so `migrateLegacy` can lift an existing session into the
// encrypted store and then wipe the plaintext copy off disk. Safe to
// delete this delegate (and the migration call) once every install has
// upgraded past the encryption change.
private val Context.sessionDataStore by preferencesDataStore(name = "watch_wear_session")
private val KEY_ACCESS_TOKEN: Preferences.Key<String> = stringPreferencesKey("session_access_token")
private val KEY_REFRESH_TOKEN: Preferences.Key<String> = stringPreferencesKey("session_refresh_token")
private val KEY_USER_ID: Preferences.Key<String> = stringPreferencesKey("session_user_id")
private val KEY_BASE_URL: Preferences.Key<String> = stringPreferencesKey("session_base_url")
private val KEY_ANON_KEY: Preferences.Key<String> = stringPreferencesKey("session_anon_key")
private val KEY_EXPIRES_AT: Preferences.Key<Long> = longPreferencesKey("session_expires_at_ms")

class SessionStore(context: Context) {
    private val appContext = context.applicationContext

    // EncryptedSharedPreferences creation can throw if the Keystore-held
    // master key is gone but the encrypted file remains (e.g. a
    // device-to-device transfer that copied app files but not the
    // Keystore). Recover by wiping the unreadable file and recreating;
    // the cost is one re-auth (the phone re-pushes the session), never a
    // crash on launch.
    private val prefs: SharedPreferences by lazy {
        try {
            createPrefs()
        } catch (e: Exception) {
            appContext.deleteSharedPreferences(PREFS_FILE)
            createPrefs()
        }
    }

    private fun createPrefs(): SharedPreferences {
        val masterKey = MasterKey.Builder(appContext)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        return EncryptedSharedPreferences.create(
            appContext,
            PREFS_FILE,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    suspend fun current(): StoredSession? = withContext(Dispatchers.IO) {
        readFromPrefs() ?: migrateLegacy()
    }

    suspend fun save(s: StoredSession): Unit = withContext(Dispatchers.IO) {
        prefs.edit()
            .putString(K_ACCESS, s.accessToken)
            .putString(K_REFRESH, s.refreshToken)
            .putString(K_USER, s.userId)
            .putString(K_BASE_URL, s.baseUrl)
            .putString(K_ANON, s.anonKey)
            .putLong(K_EXPIRES, s.expiresAtMs)
            .commit()
        Unit
    }

    suspend fun clear(): Unit = withContext(Dispatchers.IO) {
        prefs.edit().clear().commit()
        // Defensive: also wipe any plaintext leftover so a sign-out can't
        // leave the previous user's tokens recoverable on disk.
        clearLegacy()
    }

    private fun readFromPrefs(): StoredSession? {
        val access = prefs.getString(K_ACCESS, null) ?: return null
        val refresh = prefs.getString(K_REFRESH, null) ?: return null
        val user = prefs.getString(K_USER, null) ?: return null
        val baseUrl = prefs.getString(K_BASE_URL, null) ?: return null
        val anonKey = prefs.getString(K_ANON, null) ?: return null
        return StoredSession(
            accessToken = access,
            refreshToken = refresh,
            userId = user,
            baseUrl = baseUrl,
            anonKey = anonKey,
            expiresAtMs = prefs.getLong(K_EXPIRES, 0),
        )
    }

    /// One-time lift of a pre-encryption session out of the plaintext
    /// DataStore and into the encrypted store, then wipe the plaintext
    /// copy. Returns the migrated session (or null if there was none).
    private suspend fun migrateLegacy(): StoredSession? {
        val legacy = appContext.sessionDataStore.data.map { p ->
            val access = p[KEY_ACCESS_TOKEN] ?: return@map null
            val refresh = p[KEY_REFRESH_TOKEN] ?: return@map null
            val user = p[KEY_USER_ID] ?: return@map null
            val baseUrl = p[KEY_BASE_URL] ?: return@map null
            val anonKey = p[KEY_ANON_KEY] ?: return@map null
            StoredSession(access, refresh, user, baseUrl, anonKey, p[KEY_EXPIRES_AT] ?: 0)
        }.first() ?: return null
        save(legacy)
        clearLegacy()
        return legacy
    }

    private suspend fun clearLegacy() {
        appContext.sessionDataStore.edit { it.clear() }
    }

    private companion object {
        const val PREFS_FILE = "watch_wear_session_secure"
        const val K_ACCESS = "session_access_token"
        const val K_REFRESH = "session_refresh_token"
        const val K_USER = "session_user_id"
        const val K_BASE_URL = "session_base_url"
        const val K_ANON = "session_anon_key"
        const val K_EXPIRES = "session_expires_at_ms"
    }
}

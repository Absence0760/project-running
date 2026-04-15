package com.runapp.watchwear

import com.runapp.watchwear.generated.RunRow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.ByteArrayOutputStream
import java.util.zip.GZIPOutputStream

/// Minimal Supabase REST client for the Wear OS app.
///
/// Talks directly to `${baseUrl}/rest/v1`, `/auth/v1`, and `/storage/v1`.
/// The row contract lives in the generated [RunRow] — renaming a column in
/// a migration regenerates that file and fails to compile here, same
/// guarantee the Dart `ApiClient` has.
class SupabaseClient(
    private val baseUrl: String,
    private val anonKey: String,
    private val http: OkHttpClient = OkHttpClient(),
) {
    private val json = Json { ignoreUnknownKeys = true }
    private val jsonMedia = "application/json".toMediaType()

    private var accessToken: String? = null
    private var refreshToken: String? = null
    private var userId: String? = null

    val authedUserId: String? get() = userId

    /// Apply a session delivered by the paired phone via the Wearable Data
    /// Layer. Called from `SessionBridge` pushes + the `SessionStore`
    /// cold-start restore.
    fun applyCredentials(
        accessToken: String,
        refreshToken: String,
        userId: String,
        baseUrl: String,
        anonKey: String,
    ) {
        this.accessToken = accessToken
        this.refreshToken = refreshToken
        this.userId = userId
        // `baseUrl` / `anonKey` are not mutable on this client today — the
        // Gradle BuildConfig value is used. If the phone's environment ever
        // diverges from the watch's (staging phone paired to a local-dev
        // watch), we'll need to make these `var` and forward them here.
    }

    /// Exchange the cached refresh token for a fresh access token. Returns
    /// the new access + refresh token pair and the absolute expiry (ms since
    /// epoch); the caller persists them back to `SessionStore`.
    suspend fun refreshAccessToken(): RefreshedSession {
        val refresh = refreshToken
            ?: throw IllegalStateException("no refresh token cached")

        val body = buildJsonObject {
            put("refresh_token", refresh)
        }.toString().toRequestBody(jsonMedia)

        val req = Request.Builder()
            .url("$baseUrl/auth/v1/token?grant_type=refresh_token")
            .header("apikey", anonKey)
            .post(body)
            .build()

        val respBody = execute(req)
        val parsed = json.parseToJsonElement(respBody) as? JsonObject
            ?: throw IllegalStateException("unexpected refresh response")
        val newAccess = parsed["access_token"]?.toString()?.trim('"')
            ?: throw IllegalStateException("refresh response missing access_token")
        val newRefresh = parsed["refresh_token"]?.toString()?.trim('"') ?: refresh
        val expiresInSec = (parsed["expires_in"]?.toString()?.toLongOrNull()) ?: 3600L

        accessToken = newAccess
        refreshToken = newRefresh
        val expiresAtMs = System.currentTimeMillis() + expiresInSec * 1000L
        return RefreshedSession(newAccess, newRefresh, expiresAtMs)
    }

    data class RefreshedSession(
        val accessToken: String,
        val refreshToken: String,
        val expiresAtMs: Long,
    )

    /// Result of a password-grant sign-in, with everything needed to
    /// populate a [StoredSession] for the watch's auth cache.
    data class SignInResult(
        val accessToken: String,
        val refreshToken: String,
        val userId: String,
        val expiresAtMs: Long,
    )

    suspend fun signIn(email: String, password: String): SignInResult {
        val body = buildJsonObject {
            put("email", email)
            put("password", password)
        }.toString().toRequestBody(jsonMedia)

        val req = Request.Builder()
            .url("$baseUrl/auth/v1/token?grant_type=password")
            .header("apikey", anonKey)
            .post(body)
            .build()

        val respBody = execute(req)
        val parsed = json.parseToJsonElement(respBody) as? JsonObject
            ?: throw IllegalStateException("unexpected auth response")
        val access = parsed["access_token"]?.toString()?.trim('"')
            ?: throw IllegalStateException("auth response missing access_token")
        val refresh = parsed["refresh_token"]?.toString()?.trim('"') ?: ""
        val expiresInSec = parsed["expires_in"]?.toString()?.toLongOrNull() ?: 3600L
        val user = parsed["user"] as? JsonObject
            ?: throw IllegalStateException("auth response missing user")
        val uid = user["id"]?.toString()?.trim('"')
            ?: throw IllegalStateException("auth response missing user.id")

        accessToken = access
        refreshToken = refresh
        userId = uid
        return SignInResult(
            accessToken = access,
            refreshToken = refresh,
            userId = uid,
            expiresAtMs = System.currentTimeMillis() + expiresInSec * 1000L,
        )
    }

    /// Base URL + anon key exposed for the ViewModel to pack into a
    /// [StoredSession] after a direct watch sign-in.
    val environment: Pair<String, String> get() = baseUrl to anonKey

    /// Upload a run: gzip the track JSON into the `runs` bucket at
    /// `{userId}/{runId}.json.gz`, then insert the row.
    suspend fun saveRun(
        runId: String,
        startedAtIso: String,
        durationS: Int,
        distanceM: Double,
        trackJson: String,
        metadata: JsonObject?,
    ) {
        val token = accessToken ?: throw IllegalStateException("not authenticated")
        val uid = userId ?: throw IllegalStateException("not authenticated")

        val gz = gzip(trackJson.toByteArray(Charsets.UTF_8))
        val path = "$uid/$runId.json.gz"
        uploadTrack(path, gz, token)

        val rowMap = mapOf(
            RunRow.COL_ID to runId,
            RunRow.COL_USER_ID to uid,
            RunRow.COL_STARTED_AT to startedAtIso,
            RunRow.COL_DURATION_S to durationS,
            RunRow.COL_DISTANCE_M to distanceM,
            RunRow.COL_SOURCE to "app",
            RunRow.COL_TRACK_URL to path,
            RunRow.COL_METADATA to metadata,
        )
        val body = encodeJsonMap(rowMap).toRequestBody(jsonMedia)

        val req = Request.Builder()
            .url("$baseUrl/rest/v1/${RunRow.TABLE}")
            .header("apikey", anonKey)
            .header("Authorization", "Bearer $token")
            .header("Content-Type", "application/json")
            .header("Prefer", "return=minimal")
            .post(body)
            .build()

        execute(req)
    }

    private suspend fun uploadTrack(path: String, bytes: ByteArray, token: String) {
        val req = Request.Builder()
            .url("$baseUrl/storage/v1/object/runs/$path")
            .header("apikey", anonKey)
            .header("Authorization", "Bearer $token")
            .header("Content-Type", "application/json")
            .header("Content-Encoding", "gzip")
            .post(bytes.toRequestBody("application/json".toMediaType()))
            .build()
        execute(req)
    }

    /// Always suspends onto the IO dispatcher — OkHttp's `newCall().execute()`
    /// is a blocking call, and the ViewModel's `viewModelScope.launch {}`
    /// defaults to the Main dispatcher, which throws
    /// `NetworkOnMainThreadException` on any blocking network op.
    private suspend fun execute(req: Request): String = withContext(Dispatchers.IO) {
        http.newCall(req).execute().use { resp ->
            val body = resp.body.string()
            if (!resp.isSuccessful) {
                throw RuntimeException("HTTP ${resp.code}: $body")
            }
            body
        }
    }

    private fun gzip(data: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        GZIPOutputStream(out).use { it.write(data) }
        return out.toByteArray()
    }

    /// Encode a `Map<String, Any?>` from [RunRow.toJsonMap] to a JSON string.
    /// Values are `String`, `Int`, `Double`, `Boolean`, or `JsonElement` —
    /// no nested Maps today, so a minimal encoder keeps the dependency
    /// surface small. Replace with kotlinx.serialization proper if we grow
    /// more shapes.
    private fun encodeJsonMap(map: Map<String, Any?>): String {
        val sb = StringBuilder("{")
        var first = true
        for ((k, v) in map) {
            if (!first) sb.append(",")
            first = false
            sb.append('"').append(k).append("\":")
            sb.append(encodeValue(v))
        }
        sb.append("}")
        return sb.toString()
    }

    private fun encodeValue(v: Any?): String = when (v) {
        null -> "null"
        is String -> Json.encodeToString(kotlinx.serialization.json.JsonPrimitive.serializer(),
            kotlinx.serialization.json.JsonPrimitive(v))
        is Boolean -> v.toString()
        is Int -> v.toString()
        is Long -> v.toString()
        is Double -> v.toString()
        is Float -> v.toString()
        is kotlinx.serialization.json.JsonElement -> v.toString()
        else -> '"'.toString() + v.toString().replace("\"", "\\\"") + '"'
    }
}

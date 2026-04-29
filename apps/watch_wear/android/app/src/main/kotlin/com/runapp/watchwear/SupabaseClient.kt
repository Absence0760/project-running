package com.runapp.watchwear

import com.runapp.watchwear.generated.RunRow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.util.zip.GZIPOutputStream

/// Minimal Supabase REST client for the Wear OS app.
///
/// Talks directly to `${baseUrl}/rest/v1`, `/auth/v1`, and `/storage/v1`.
/// The row contract lives in the generated [RunRow] — renaming a column in
/// a migration regenerates that file and fails to compile here, same
/// guarantee the Dart `ApiClient` has.
class SupabaseClient(
    private var baseUrl: String,
    private var anonKey: String,
    private val http: OkHttpClient = OkHttpClient(),
) {
    private val json = Json { ignoreUnknownKeys = true }
    private val jsonMedia = "application/json".toMediaType()

    private var accessToken: String? = null
    private var refreshToken: String? = null
    private var userId: String? = null

    val authedUserId: String? get() = userId
    /// Exposed for the race-session client which issues requests on the
    /// same REST surface without owning the auth state itself.
    val currentAccessToken: String? get() = accessToken

    /// Drop the in-memory session. Caller is also responsible for clearing
    /// `SessionStore` so a cold restart doesn't restore it.
    fun clearCredentials() {
        accessToken = null
        refreshToken = null
        userId = null
    }

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
        this.baseUrl = baseUrl
        this.anonKey = anonKey
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

    /// Fetch the signed-in user's saved routes. Returns an empty list
    /// when the API is unreachable or the response can't be parsed —
    /// the picker gracefully shows "no routes" rather than the caller
    /// having to catch here. Caller decides whether to cache on success.
    ///
    /// Pulls `id`, `name`, `waypoints`, and `distance_m`; everything
    /// else stays on the phone / web. `waypoints` is a jsonb array of
    /// `{lat, lng, ...}` — we extract lat/lng only.
    suspend fun fetchRoutes(): List<SavedRoute> {
        val token = accessToken ?: return emptyList()
        val req = Request.Builder()
            .url("$baseUrl/rest/v1/routes?select=id,name,waypoints,distance_m&order=updated_at.desc")
            .header("apikey", anonKey)
            .header("Authorization", "Bearer $token")
            .get()
            .build()
        val body = try {
            execute(req)
        } catch (_: Throwable) {
            return emptyList()
        }
        val rows = (json.parseToJsonElement(body) as? JsonArray) ?: return emptyList()
        return rows.mapNotNull { row ->
            val obj = row as? JsonObject ?: return@mapNotNull null
            val id = obj["id"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            val name = obj["name"]?.jsonPrimitive?.contentOrNull ?: "Unnamed route"
            val distanceM = obj["distance_m"]?.jsonPrimitive?.doubleOrNull ?: 0.0
            val wpArr = obj["waypoints"] as? JsonArray ?: return@mapNotNull null
            val waypoints = wpArr.mapNotNull { el ->
                val wp = el as? JsonObject ?: return@mapNotNull null
                val lat = wp["lat"]?.jsonPrimitive?.doubleOrNull ?: return@mapNotNull null
                val lng = wp["lng"]?.jsonPrimitive?.doubleOrNull ?: return@mapNotNull null
                SavedRoute.Waypoint(lat = lat, lng = lng)
            }
            if (waypoints.size < 2) return@mapNotNull null
            SavedRoute(id = id, name = name, distanceM = distanceM, waypoints = waypoints)
        }
    }

    /// Upload a run: gzip the track file into the `runs` bucket at
    /// `{userId}/{runId}.json.gz`, then insert the row.
    ///
    /// The track file is streamed disk→gzip→disk (a sibling `.gz` temp file)
    /// rather than buffered into a `ByteArray`. For an ultra-length run the
    /// raw track can be several MB; holding the full gzipped payload in
    /// memory is a hazard we don't need to take.
    suspend fun saveRun(
        runId: String,
        startedAtIso: String,
        durationS: Int,
        distanceM: Double,
        trackFile: File,
        metadata: JsonObject?,
    ) {
        val token = accessToken ?: throw IllegalStateException("not authenticated")
        val uid = userId ?: throw IllegalStateException("not authenticated")

        val gzFile = withContext(Dispatchers.IO) { gzipToTempFile(trackFile) }
        try {
            val path = "$uid/$runId.json.gz"
            uploadTrack(path, gzFile, token)

            val rowMap = mapOf(
                RunRow.COL_ID to runId,
                RunRow.COL_USER_ID to uid,
                RunRow.COL_STARTED_AT to startedAtIso,
                RunRow.COL_DURATION_S to durationS,
                RunRow.COL_DISTANCE_M to distanceM,
                RunRow.COL_SOURCE to "watch",
                RunRow.COL_TRACK_URL to path,
                RunRow.COL_METADATA to metadata,
                RunRow.COL_EXTERNAL_ID to runId,
            )
            val body = encodeJsonMap(rowMap).toRequestBody(jsonMedia)

            val req = Request.Builder()
                .url("$baseUrl/rest/v1/${RunRow.TABLE}")
                .header("apikey", anonKey)
                .header("Authorization", "Bearer $token")
                .header("Content-Type", "application/json")
                .header("Prefer", "resolution=merge-duplicates,return=minimal")
                .post(body)
                .build()

            execute(req)
        } finally {
            gzFile.delete()
        }
    }

    private suspend fun uploadTrack(path: String, gzFile: File, token: String) {
        val req = Request.Builder()
            .url("$baseUrl/storage/v1/object/runs/$path")
            .header("apikey", anonKey)
            .header("Authorization", "Bearer $token")
            .header("Content-Type", "application/json")
            .header("Content-Encoding", "gzip")
            .post(gzFile.asRequestBody("application/json".toMediaType()))
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
                throw RuntimeException(humanErrorMessage(resp.code, body))
            }
            body
        }
    }

    /// Supabase errors come back as `{"code":400,"error_code":"...","msg":"..."}`
    /// or `{"error":"...","error_description":"..."}` depending on the endpoint.
    /// Pick the most user-readable field; fall back to the raw body if
    /// nothing parses.
    private fun humanErrorMessage(code: Int, body: String): String {
        return try {
            val obj = json.parseToJsonElement(body) as? JsonObject
                ?: return "HTTP $code"
            val msg = obj["msg"] ?: obj["error_description"] ?: obj["error"] ?: obj["message"]
            if (msg != null) msg.toString().trim('"') else "HTTP $code"
        } catch (_: Throwable) {
            "HTTP $code"
        }
    }

    /// Gzip `src` into a sibling temp file and return the temp file. Caller
    /// owns the returned file and must delete it. Streams 8 KiB at a time
    /// so peak memory is O(buffer) regardless of track size.
    private fun gzipToTempFile(src: File): File {
        val out = File.createTempFile("track_", ".gz", src.parentFile)
        src.inputStream().use { input ->
            GZIPOutputStream(out.outputStream().buffered()).use { gz ->
                input.copyTo(gz, bufferSize = 8192)
            }
        }
        return out
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

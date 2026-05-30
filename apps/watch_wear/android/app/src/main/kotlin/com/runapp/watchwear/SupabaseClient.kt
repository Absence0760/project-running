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
import kotlinx.serialization.json.intOrNull
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

/// Thrown by [SupabaseClient.execute] when the response is not 2xx.
///
/// The HTTP status survives on `code` so callers can branch on it
/// (e.g., 401 → refresh + retry, 409 → idempotent skip) without
/// substring-matching the human-readable `message`. Carrying the body's
/// `msg` / `error_description` / `error` / `message` field through as
/// the exception message keeps the UI-surfaced text user-readable.
class HttpException(val code: Int, message: String) : RuntimeException(message)

private val errorBodyJson = Json { ignoreUnknownKeys = true }

/// Pull the most user-readable string out of a Supabase / PostgREST /
/// GoTrue / Storage error body. Different surfaces use different field
/// names — try the well-known ones in priority order, fall back to
/// `"HTTP $code"` when the body isn't JSON or has none of them.
///
/// Internal so the unit test can pin the field-precedence behaviour.
/// Pure helper: build the `runs.insert` row map for [SupabaseClient.saveRun].
/// Lifted out of the suspending method so the column shape can be
/// unit-tested without booting OkHttp.
///
/// Mirrors the column projection used by mobile's
/// `ApiClient.saveRun` (Dart) so a watch-saved run reads back
/// identically to a phone-saved run. `source` is always `"watch"`
/// (the [RunSource] enum value the row labels the watch with).
/// `external_id` is set to [runId] for idempotency on retry — the
/// drain loop's 409 / `DropAndContinue` path counts on the unique
/// constraint here. `is_public` is OMITTED (not null) when the
/// caller doesn't pass it, so the DB default (`false`) applies.
internal fun buildSaveRunRowMap(
    runId: String,
    uid: String,
    startedAtIso: String,
    durationS: Int,
    distanceM: Double,
    trackPath: String,
    metadata: JsonObject?,
    isPublic: Boolean?,
): Map<String, Any?> = buildMap {
    put(RunRow.COL_ID, runId)
    put(RunRow.COL_USER_ID, uid)
    put(RunRow.COL_STARTED_AT, startedAtIso)
    put(RunRow.COL_DURATION_S, durationS)
    put(RunRow.COL_DISTANCE_M, distanceM)
    put(RunRow.COL_SOURCE, "watch")
    put(RunRow.COL_TRACK_URL, trackPath)
    put(RunRow.COL_METADATA, metadata)
    put(RunRow.COL_EXTERNAL_ID, runId)
    if (isPublic != null) put(RunRow.COL_IS_PUBLIC, isPublic)
}

internal fun humanErrorMessage(code: Int, body: String): String {
    return try {
        val obj = errorBodyJson.parseToJsonElement(body) as? JsonObject
            ?: return "HTTP $code"
        val msg = obj["msg"] ?: obj["error_description"] ?: obj["error"] ?: obj["message"]
        if (msg != null) msg.toString().trim('"') else "HTTP $code"
    } catch (_: Throwable) {
        "HTTP $code"
    }
}

/// Universal-prefs subset the wrist actually reads. Keep this narrow
/// — the watch is a recording surface, not a settings surface, so
/// only fields the recording loop or pre-run UX needs belong here.
///
/// Today:
///   - `defaultActivityType` flows into the pre-run picker so a
///     runner whose phone default is "walk" doesn't see "run"
///     pre-armed on the wrist.
///   - `privacyDefault` is stamped onto QueuedRun at stop-time so a
///     watch-saved run respects the user's universal default. The
///     mapping is `public → is_public=true`; `followers` /
///     `private` / null → omit the column (DB default `false`
///     wins). The phone/web social layer is the authoritative path
///     for the `followers` nuance.
///   - `hrZones` (5 strictly-ascending upper bounds) plus the
///     fallback inputs `maxHrBpm` and `dateOfBirth` feed the live
///     "Z3" badge next to BPM on the RunningScreen. The
///     `resolveZoneCutoffs` precedence is: explicit hr_zones >
///     60/70/80/90/100% of max_hr_bpm > 60/70/80/90/100% of
///     (Tanaka 208 − 0.7×age from DOB) > null (no zone display).
data class UniversalSettings(
    val defaultActivityType: String?,
    val privacyDefault: String?,
    val hrZones: List<Int>? = null,
    val restingHrBpm: Int? = null,
    val maxHrBpm: Int? = null,
    val dateOfBirth: String? = null,
    /// Body weight in kg for the post-run calorie estimate (persona
    /// samsung #34). Null → the shared default (70 kg) applies.
    val bodyWeightKg: Double? = null,
)

/// Allowed values for `default_activity_type`. Mirrors the CHECK
/// constraint that gates the pref's writers on web + Android. A
/// rogue value (older client, manual SQL edit) is silently ignored
/// so the watch can never end up trying to record a `metadata
/// .activity_type` Strava wouldn't recognise.
internal val UNIVERSAL_ACTIVITY_TYPES = setOf("run", "walk", "hike", "cycle")

/// Allowed values for `privacy_default`. Mirrors the editor on web +
/// mobile (docs/backend/settings.md: `'public' | 'followers' | 'private'`).
/// Rogue / future / typo values fall back to null → DB default
/// (`false`) wins on save.
internal val UNIVERSAL_PRIVACY_DEFAULTS = setOf("public", "followers", "private")

/// Pure parser for the PostgREST response body of
/// `GET /rest/v1/user_settings?user_id=eq.<uid>&select=prefs&limit=1`.
///
/// Internal so the unit test can pin the every shape variant: empty
/// array (no row), null `prefs`, missing `default_activity_type`
/// key, malformed value. Always returns a non-null `UniversalSettings`
/// when the body is a parseable array (even an empty `prefs`); the
/// caller can still get null from the wrapping `fetchUniversalSettings`
/// when the HTTP call fails entirely.
internal fun parseUniversalSettings(body: String?): UniversalSettings? {
    if (body.isNullOrBlank()) return null
    return try {
        val arr = errorBodyJson.parseToJsonElement(body) as? JsonArray
            ?: return null
        val empty = UniversalSettings(defaultActivityType = null, privacyDefault = null)
        if (arr.isEmpty()) return empty
        val row = arr[0] as? JsonObject ?: return null
        val prefs = row["prefs"] as? JsonObject ?: return empty
        UniversalSettings(
            defaultActivityType = prefs["default_activity_type"]?.jsonPrimitive?.contentOrNull
                ?.takeIf { it in UNIVERSAL_ACTIVITY_TYPES },
            privacyDefault = prefs["privacy_default"]?.jsonPrimitive?.contentOrNull
                ?.takeIf { it in UNIVERSAL_PRIVACY_DEFAULTS },
            hrZones = parseHrZones(prefs["hr_zones"] as? JsonObject),
            restingHrBpm = (prefs["resting_hr_bpm"]?.jsonPrimitive?.intOrNull)
                ?.takeIf { it in 25..120 },
            maxHrBpm = (prefs["max_hr_bpm"]?.jsonPrimitive?.intOrNull)
                ?.takeIf { it in 100..240 },
            dateOfBirth = prefs["date_of_birth"]?.jsonPrimitive?.contentOrNull
                ?.takeIf { isValidIsoDate(it) },
            bodyWeightKg = (prefs["body_weight_kg"]?.jsonPrimitive?.doubleOrNull)
                ?.takeIf { it in 20.0..400.0 },
        )
    } catch (_: Throwable) {
        null
    }
}

/// Parse an `hr_zones` object (`{z1, z2, z3, z4, z5}`) into an
/// ordered list of upper-bound cutoffs. Returns null when any entry
/// is missing, non-integer, non-positive, out of [40, 240], or when
/// the five values aren't strictly ascending. The strict-ascending
/// gate is what stops a misconfigured zone bag from rendering a
/// nonsensical "Z3" at e.g. bpm=130 when the cutoffs were saved as
/// {z1:170, z2:160, z3:150, ...} by an old client.
private fun parseHrZones(obj: JsonObject?): List<Int>? {
    if (obj == null) return null
    val keys = listOf("z1", "z2", "z3", "z4", "z5")
    val out = ArrayList<Int>(5)
    for (k in keys) {
        val v = obj[k]?.jsonPrimitive?.intOrNull ?: return null
        if (v !in 40..240) return null
        out.add(v)
    }
    for (i in 1 until out.size) {
        if (out[i] <= out[i - 1]) return null
    }
    return out
}

/// Cheap ISO-date sanity check (YYYY-MM-DD). Not a full RFC 3339
/// parse — the consumer does the day arithmetic via `LocalDate` so
/// any malformed string would surface there. We sanitise the most
/// obvious garbage here so a corrupt `date_of_birth` cell doesn't
/// poison the calling code with a `DateTimeParseException`.
private fun isValidIsoDate(s: String): Boolean {
    if (s.length != 10) return false
    if (s[4] != '-' || s[7] != '-') return false
    return s.substring(0, 4).all { it.isDigit() } &&
        s.substring(5, 7).all { it.isDigit() } &&
        s.substring(8, 10).all { it.isDigit() }
}

/// Pure mapping from a live BPM to a 1..5 zone, given the
/// strictly-ascending 5-element cutoff array. Returns null when
/// `cutoffs` is null or empty so the caller can omit the "Z3"
/// badge rather than rendering a misleading default. The Dart
/// twin in `apps/mobile_android/lib/hr_zones.dart`'s `_zoneIndex`
/// uses 0..4; the wrist uses 1..5 because it surfaces directly
/// in user-visible text.
internal fun hrZoneOf(bpm: Int, cutoffs: List<Int>?): Int? {
    if (cutoffs.isNullOrEmpty() || cutoffs.size != 5) return null
    for (i in 0 until 4) {
        if (bpm <= cutoffs[i]) return i + 1
    }
    return 5
}

/// Pick zone cutoffs in priority order: explicit `hr_zones` >
/// 60/70/80/90/100% of `max_hr_bpm` > 60/70/80/90/100% of
/// (Tanaka 208 − 0.7×age from `date_of_birth`) > null.
///
/// `nowMs` is injected so tests can pin the age calculation —
/// production callers pass `System.currentTimeMillis()`.
internal fun resolveZoneCutoffs(s: UniversalSettings, nowMs: Long): List<Int>? {
    s.hrZones?.let { return it }
    val maxHr = s.maxHrBpm ?: ageBasedMaxHr(s.dateOfBirth, nowMs)
    if (maxHr == null) return null
    // 60/70/80/90/100% — matches the Dart `zoneCutoffsFromMaxHr`
    // ladder (60% × 190 = 114, etc.) and the web inferred path.
    // Math.round, not truncation, to stay byte-for-byte with the twin.
    return listOf(
        Math.round(maxHr * 0.60).toInt(),
        Math.round(maxHr * 0.70).toInt(),
        Math.round(maxHr * 0.80).toInt(),
        Math.round(maxHr * 0.90).toInt(),
        maxHr,
    )
}

/// Tanaka (2001) age-predicted maximal heart rate: 208 − 0.7 × age.
/// More accurate for masters runners than the classic 220 − age, which
/// overestimates HR-max past ~40 (persona-hunt Older #8). Mirrors the
/// Dart `tanakaMaxHr` + the web `tanakaMaxHr`.
private fun ageBasedMaxHr(dob: String?, nowMs: Long): Int? {
    if (dob == null) return null
    return try {
        val year = dob.substring(0, 4).toInt()
        val month = dob.substring(5, 7).toInt()
        val day = dob.substring(8, 10).toInt()
        val now = java.time.Instant.ofEpochMilli(nowMs)
            .atZone(java.time.ZoneOffset.UTC).toLocalDate()
        val born = java.time.LocalDate.of(year, month, day)
        val age = java.time.Period.between(born, now).years
        if (age in 5..120) Math.round(208 - 0.7 * age).toInt() else null
    } catch (_: Throwable) {
        null
    }
}

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

        // Wire shape lives in `SupabaseUrlBuilders.kt` so the URL +
        // body keys can be unit-tested (see `SupabaseUrlBuildersTest`).
        val body = buildRefreshTokenBody(refresh).toRequestBody(jsonMedia)
        val req = Request.Builder()
            .url(buildRefreshTokenUrl(baseUrl))
            .header("apikey", anonKey)
            .post(body)
            .build()

        val respBody = execute(req)
        val parsed = json.parseToJsonElement(respBody) as? JsonObject
            ?: throw IllegalStateException("unexpected refresh response")
        val newAccess = parsed["access_token"]?.toString()?.trim('"')
            ?: throw IllegalStateException("refresh response missing access_token")
        val newRefresh = parsed["refresh_token"]?.toString()?.trim('"') ?: refresh
        val expiresInSec = (parsed["expires_in"]?.toString()?.toLongOrNull())

        accessToken = newAccess
        refreshToken = newRefresh
        val expiresAtMs = computeRefreshExpiryMs(System.currentTimeMillis(), expiresInSec)
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
        // Query-string predicates + the starred-vs-fallback decision
        // are in `SupabaseUrlBuilders.kt` so the URL build can be
        // unit-tested (see `SupabaseUrlBuildersTest`).
        val starred = fetchRoutesQuery(token, chooseFirstRoutesQuery())
        if (starred.isNotEmpty()) return starred
        return fetchRoutesQuery(token, chooseFallbackRoutesQuery())
    }

    private suspend fun fetchRoutesQuery(token: String, query: String): List<SavedRoute> {
        val req = Request.Builder()
            .url(buildFetchRoutesUrl(baseUrl, query))
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

    /// Fetch the signed-in user's universal-prefs bag from
    /// `user_settings.prefs`. Today the only field we consume on the
    /// wrist is `default_activity_type`; the rest of the bag (HR
    /// zones, privacy_default, date_of_birth, etc.) is edited from
    /// the phone / web. We keep this surface read-only on Wear OS
    /// per `apps/watch_wear/CLAUDE.md` — settings panels belong on
    /// the pocket app, not the wrist.
    ///
    /// Returns null on any failure (offline, RLS denial, malformed
    /// row) so the caller can fall through to the on-device default
    /// without a try/catch. The caller treats null as "leave the
    /// default in place"; a present `UniversalSettings` with a null
    /// `defaultActivityType` is also fine — the bag exists but the
    /// user hasn't picked a default yet.
    suspend fun fetchUniversalSettings(): UniversalSettings? {
        val token = accessToken ?: return null
        val uid = userId ?: return null
        val req = Request.Builder()
            .url("$baseUrl/rest/v1/user_settings?user_id=eq.$uid&select=prefs&limit=1")
            .header("apikey", anonKey)
            .header("Authorization", "Bearer $token")
            .get()
            .build()
        val body = try {
            execute(req)
        } catch (_: Throwable) {
            return null
        }
        return parseUniversalSettings(body)
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
        /// Snapshot of the user's `privacy_default` at run-stop time,
        /// mapped to a boolean: `public → true`, `followers / private
        /// → false`. Null omits the column so the DB default (`false`)
        /// applies — same as a watch-saved run before the privacy_default
        /// fetch existed. Stamped on QueuedRun rather than read at upload
        /// time so a later pref change can't retroactively flip an
        /// already-recorded run's visibility.
        isPublic: Boolean? = null,
    ) {
        val token = accessToken ?: throw IllegalStateException("not authenticated")
        val uid = userId ?: throw IllegalStateException("not authenticated")

        val gzFile = withContext(Dispatchers.IO) { gzipToTempFile(trackFile) }
        try {
            val path = "$uid/$runId.json.gz"
            uploadTrack(path, gzFile, token)

            val rowMap = buildSaveRunRowMap(
                runId = runId,
                uid = uid,
                startedAtIso = startedAtIso,
                durationS = durationS,
                distanceM = distanceM,
                trackPath = path,
                metadata = metadata,
                isPublic = isPublic,
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
                throw HttpException(resp.code, humanErrorMessage(resp.code, body))
            }
            body
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
}

/// Hand-rolled JSON encoder for the row maps that
/// [SupabaseClient.saveRun] (and a handful of other callers) POST to
/// PostgREST.
///
/// Values are `String`, `Int`, `Double`, `Boolean`, or `JsonElement`
/// — no nested Maps today, so a minimal encoder keeps the dependency
/// surface small. Replace with kotlinx.serialization proper if we
/// grow more shapes.
///
/// Lifted to file-level `internal` (was a private method) so the
/// encoder contract — string escaping, null handling, numeric
/// preservation — can be unit-tested. Every save-to-Supabase path
/// flows through this encoder; a regression here breaks every POST.
internal fun encodeJsonMap(map: Map<String, Any?>): String {
    val sb = StringBuilder("{")
    var first = true
    for ((k, v) in map) {
        if (!first) sb.append(",")
        first = false
        sb.append('"').append(k).append("\":")
        sb.append(encodeJsonValue(v))
    }
    sb.append("}")
    return sb.toString()
}

internal fun encodeJsonValue(v: Any?): String = when (v) {
    null -> "null"
    is String -> Json.encodeToString(
        kotlinx.serialization.json.JsonPrimitive.serializer(),
        kotlinx.serialization.json.JsonPrimitive(v),
    )
    is Boolean -> v.toString()
    is Int -> v.toString()
    is Long -> v.toString()
    is Double -> v.toString()
    is Float -> v.toString()
    is kotlinx.serialization.json.JsonElement -> v.toString()
    else -> '"'.toString() + v.toString().replace("\"", "\\\"") + '"'
}

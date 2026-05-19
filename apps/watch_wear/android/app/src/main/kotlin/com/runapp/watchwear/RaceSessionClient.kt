package com.runapp.watchwear

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.net.URLEncoder
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/// Thin REST client for the `race_sessions`, `race_pings`, and
/// `event_results` endpoints. Shares the wire format with
/// `SupabaseClient.saveRun` — this file owns nothing else about that
/// service and keeps `SupabaseClient.kt` focused on the run-upload path.
class RaceSessionClient(
    private val baseUrl: String,
    private val anonKey: String,
    private val http: OkHttpClient = OkHttpClient(),
) {
    private val json = Json { ignoreUnknownKeys = true }
    private val jsonMedia = "application/json".toMediaType()

    data class ActiveRace(
        val eventId: String,
        val instanceStart: String,
        val status: String,
        val startedAtIso: String?,
        val eventTitle: String?,
    )

    /// Return the most relevant armed/running race for the signed-in
    /// user by scanning their `going` RSVPs within a +/- 12h window and
    /// looking up race_sessions row-by-row. Returns null when none
    /// match — the watch screen then hides the race banner entirely.
    suspend fun fetchActive(accessToken: String, userId: String): ActiveRace? {
        val now = System.currentTimeMillis()
        val past = isoUtc(now - 12 * 3600_000L)
        val future = isoUtc(now + 12 * 3600_000L)
        val rsvps = get(
            "$baseUrl/rest/v1/event_attendees?user_id=eq.${enc(userId)}" +
                "&status=eq.going" +
                "&instance_start=gte.${enc(past)}" +
                "&instance_start=lte.${enc(future)}" +
                "&select=event_id,instance_start",
            accessToken,
        )
        val list = (json.parseToJsonElement(rsvps) as? JsonArray) ?: return null
        for (el in list) {
            val obj = el as? JsonObject ?: continue
            val eventId = obj["event_id"]?.jsonPrimitive?.content ?: continue
            val instance = obj["instance_start"]?.jsonPrimitive?.content ?: continue
            val raceRes = get(
                "$baseUrl/rest/v1/race_sessions" +
                    "?event_id=eq.${enc(eventId)}" +
                    "&instance_start=eq.${enc(instance)}" +
                    "&status=in.(armed,running)" +
                    "&select=status,started_at",
                accessToken,
            )
            val races = (json.parseToJsonElement(raceRes) as? JsonArray) ?: continue
            if (races.isEmpty()) continue
            val r = races[0] as JsonObject
            val status = r["status"]?.jsonPrimitive?.content ?: continue
            val startedAt = r["started_at"]?.jsonPrimitive?.content
            val titleRes = get(
                "$baseUrl/rest/v1/events?id=eq.${enc(eventId)}&select=title",
                accessToken,
            )
            val title = (json.parseToJsonElement(titleRes) as? JsonArray)
                ?.firstOrNull()?.let { (it as JsonObject)["title"]?.jsonPrimitive?.content }
            return ActiveRace(eventId, instance, status, startedAt, title)
        }
        return null
    }

    /// Fire-and-forget ping post. Caller debounces to every 10s or so.
    suspend fun pushPing(
        accessToken: String,
        userId: String,
        eventId: String,
        instanceStart: String,
        lat: Double,
        lng: Double,
        distanceM: Double,
        elapsedS: Int,
        bpm: Int?,
    ) {
        val body = buildJsonObject {
            put("event_id", eventId)
            put("instance_start", instanceStart)
            put("user_id", userId)
            put("lat", lat)
            put("lng", lng)
            put("distance_m", distanceM)
            put("elapsed_s", elapsedS)
            if (bpm != null) put("bpm", bpm)
        }
        post("$baseUrl/rest/v1/race_pings", body.toString(), accessToken)
    }

    suspend fun submitResult(
        accessToken: String,
        userId: String,
        eventId: String,
        instanceStart: String,
        runId: String,
        durationS: Int,
        distanceM: Double,
    ) {
        val body = buildJsonObject {
            put("event_id", eventId)
            put("instance_start", instanceStart)
            put("user_id", userId)
            put("run_id", runId)
            put("duration_s", durationS)
            put("distance_m", distanceM)
            put("finisher_status", "finished")
        }
        val req = Request.Builder()
            .url("$baseUrl/rest/v1/event_results")
            .header("apikey", anonKey)
            .header("Authorization", "Bearer $accessToken")
            .header("Content-Type", "application/json")
            .header("Prefer", "resolution=merge-duplicates,return=minimal")
            .post(body.toString().toRequestBody(jsonMedia))
            .build()
        execute(req)
    }

    // ----- internal -----

    private suspend fun get(url: String, token: String): String {
        val req = Request.Builder()
            .url(url)
            .header("apikey", anonKey)
            .header("Authorization", "Bearer $token")
            .get()
            .build()
        return execute(req)
    }

    private suspend fun post(url: String, body: String, token: String): String {
        val req = Request.Builder()
            .url(url)
            .header("apikey", anonKey)
            .header("Authorization", "Bearer $token")
            .header("Content-Type", "application/json")
            .header("Prefer", "return=minimal")
            .post(body.toRequestBody(jsonMedia))
            .build()
        return execute(req)
    }

    private suspend fun execute(req: Request): String = withContext(Dispatchers.IO) {
        http.newCall(req).execute().use { resp ->
            val body = resp.body.string()
            if (!resp.isSuccessful) {
                throw RuntimeException("HTTP ${resp.code}: $body")
            }
            body
        }
    }

    private fun isoUtc(ms: Long): String {
        // `Instant.toString()` always emits the `Z` suffix form which
        // happens to be URL-safe, but we still feed it through `enc`
        // below so the URL-building call sites can't accidentally
        // forget to encode some future caller's value.
        return java.time.Instant.ofEpochMilli(ms).toString()
    }

    private fun enc(s: String): String = encodeQueryValue(s)

    companion object {
        /// URL-encode a value for interpolation into a PostgREST query
        /// string. Critically defensive for `instance_start` values
        /// that come BACK from PostgREST as timestamptz — Postgres
        /// serializes timestamptz as `2026-05-22T18:00:00+00:00`, and
        /// a raw `+` in a PostgREST query value gets decoded as a
        /// SPACE (PostgREST treats the query as
        /// application/x-www-form-urlencoded). Without this encoding
        /// the second-hop query `instance_start=eq.<value>` would fail
        /// to match the row it just read, and `fetchActive` would
        /// return null whenever a user has an actual armed race
        /// waiting on the day-of.
        ///
        /// `internal` so unit tests can exercise it without spinning
        /// up a real OkHttp stack — see `RaceSessionClientTest`.
        @JvmStatic
        internal fun encodeQueryValue(s: String): String =
            URLEncoder.encode(s, Charsets.UTF_8.name())
    }
}

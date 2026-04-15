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
            "$baseUrl/rest/v1/event_attendees?user_id=eq.$userId" +
                "&status=eq.going" +
                "&instance_start=gte.$past" +
                "&instance_start=lte.$future" +
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
                    "?event_id=eq.$eventId" +
                    "&instance_start=eq.$instance" +
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
                "$baseUrl/rest/v1/events?id=eq.$eventId&select=title",
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
        // Postgrest query params need URL-encoded ISO-8601; simplest is
        // java.time.Instant.toString which is already URL-safe.
        return java.time.Instant.ofEpochMilli(ms).toString()
    }
}

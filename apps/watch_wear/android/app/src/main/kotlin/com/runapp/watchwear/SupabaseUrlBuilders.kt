package com.runapp.watchwear

import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.Request
import okhttp3.RequestBody

/// Pure helpers that build the PostgREST / GoTrue URLs + bodies the
/// watch's [SupabaseClient] POSTs and GETs. Lifted out of the HTTP-
/// bound methods so the wire shape — query string, body keys, the
/// starred-first-then-fallback decision — can be unit-tested without
/// booting OkHttp.

// ───────────────────────── fetchRoutes ─────────────────────────

/// Query-string predicate for the "starred only, recent first" pass.
/// Backed by the partial index `idx_routes_user_starred` (user_id,
/// updated_at desc) WHERE is_starred → O(starred) read. Cap at 30
/// for the rare power user.
internal const val FETCH_ROUTES_STARRED_QUERY =
    "select=id,name,waypoints,distance_m&is_starred=eq.true&order=updated_at.desc&limit=30"

/// Query-string for the first-launch fallback: 10 most-recently-
/// updated owned routes. A new user without starred routes still
/// needs *something* in the watch picker. Capped tighter than the
/// starred path because this is undirected — better to show too few
/// than fill the picker with stale GPX imports.
internal const val FETCH_ROUTES_FALLBACK_QUERY =
    "select=id,name,waypoints,distance_m&order=updated_at.desc&limit=10"

/// Compose the absolute URL the OkHttp request hits, given a base
/// supabase URL + a query-string predicate from above.
internal fun buildFetchRoutesUrl(baseUrl: String, query: String): String =
    "$baseUrl/rest/v1/routes?$query"

/// Decide which routes query to fire FIRST. Pure logic so the
/// starred-vs-fallback decision is testable.
///
/// Returns the starred query unconditionally — the production code
/// then inspects the result and falls back to [chooseFallbackQuery]
/// when the starred result is empty. Splitting the decision in two
/// pure helpers lets tests pin both paths independently.
internal fun chooseFirstRoutesQuery(): String = FETCH_ROUTES_STARRED_QUERY

internal fun chooseFallbackRoutesQuery(): String = FETCH_ROUTES_FALLBACK_QUERY

// ───────────────────────── refreshAccessToken ─────────────────────────

/// Body the GoTrue `POST /auth/v1/token?grant_type=refresh_token`
/// endpoint expects. Single field; we set ONLY refresh_token so a
/// future refactor can't accidentally leak the access_token through
/// the wire (the access token is what we're trying to REPLACE).
internal fun buildRefreshTokenBody(refreshToken: String): String =
    buildJsonObject {
        put("refresh_token", refreshToken)
    }.toString()

/// Compose the refresh-token URL from a base supabase URL. The
/// `grant_type=refresh_token` query is mandatory — GoTrue's same
/// endpoint also handles `grant_type=password` for direct sign-in,
/// and omitting the grant_type misroutes the request to password-
/// grant where it 400s on the missing email+password fields.
internal fun buildRefreshTokenUrl(baseUrl: String): String =
    "$baseUrl/auth/v1/token?grant_type=refresh_token"

/// Compute the absolute expiry timestamp (epoch ms) from a GoTrue
/// `expires_in` (seconds-from-now). Falls back to 1 hour if the
/// response is missing the field — GoTrue's default token lifetime
/// is 3600 s so this is the right default-on-missing.
internal fun computeRefreshExpiryMs(
    nowMs: Long,
    expiresInSec: Long?,
): Long = nowMs + (expiresInSec ?: 3600L) * 1000L

// ───────────────────────── uploadTrack ─────────────────────────

/// Build the Storage request that uploads a run's gzipped track to
/// `runs/{userId}/{runId}.json.gz`. The track object is keyed
/// deterministically, so a retry after a partial-success save (track
/// uploaded, row POST failed) re-uploads an object that already
/// exists. `x-upsert: true` makes Storage overwrite it instead of
/// returning `409 Duplicate` — the same idempotent-overwrite intent
/// the row POST expresses with `resolution=merge-duplicates` and that
/// mobile's `ApiClient.uploadTrackBytes` expresses with `upsert: true`.
/// Without it, a track-already-there run wedges the offline queue
/// forever (issue #455).
///
/// Extracted so the header set — the load-bearing idempotency
/// guarantee — is unit-testable without booting OkHttp's network.
internal fun buildUploadTrackRequest(
    baseUrl: String,
    path: String,
    anonKey: String,
    token: String,
    body: RequestBody,
): Request =
    Request.Builder()
        .url("$baseUrl/storage/v1/object/runs/$path")
        .header("apikey", anonKey)
        .header("Authorization", "Bearer $token")
        .header("Content-Type", "application/json")
        .header("Content-Encoding", "gzip")
        .header("x-upsert", "true")
        .post(body)
        .build()

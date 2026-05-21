package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// Pin the URLs + bodies the watch's [SupabaseClient] sends. A typo
/// in the query string (wrong filter, dropped sort, missing limit)
/// would silently change which routes appear on the watch picker
/// or how the refresh-token grant is routed — both load-bearing for
/// daily use.
class SupabaseUrlBuildersTest {

    // ───────────── fetchRoutes URL strings ─────────────

    @Test fun `starred query selects the right columns and filters`() {
        // The watch picker needs id (for the deep-link), name (for
        // the chip label), waypoints (rendered as the polyline +
        // off-route math), and distance_m (the chip's secondary
        // label). Any other column would just bloat the wire.
        assertTrue(FETCH_ROUTES_STARRED_QUERY.contains("select=id,name,waypoints,distance_m"))
        // Starred-only filter — without `is_starred=eq.true` we'd
        // be back at the old behaviour of pulling 30 most-recent
        // routes, defeating the curation feature.
        assertTrue(FETCH_ROUTES_STARRED_QUERY.contains("is_starred=eq.true"))
        // Most-recent first so the runner's latest curation lands
        // at the top of the picker.
        assertTrue(FETCH_ROUTES_STARRED_QUERY.contains("order=updated_at.desc"))
        // Cap at 30 — pinned so a future "let's show 100" change
        // requires a test edit + thinks about the 1.4-inch UX.
        assertTrue(FETCH_ROUTES_STARRED_QUERY.contains("limit=30"))
    }

    @Test fun `fallback query omits the starred filter, caps tighter`() {
        // Without the `is_starred=eq.true` predicate this falls back
        // to "all owned routes". Capped tighter (10) than the
        // starred path because this is undirected — better to show
        // too few than stale GPX imports.
        assertEquals(false, FETCH_ROUTES_FALLBACK_QUERY.contains("is_starred"))
        assertTrue(FETCH_ROUTES_FALLBACK_QUERY.contains("order=updated_at.desc"))
        assertTrue(FETCH_ROUTES_FALLBACK_QUERY.contains("limit=10"))
        assertTrue(FETCH_ROUTES_FALLBACK_QUERY.contains("select=id,name,waypoints,distance_m"))
    }

    @Test fun `chooseFirstRoutesQuery returns the starred predicate`() {
        // Pin the decision: the FIRST attempt is always starred-only.
        assertEquals(FETCH_ROUTES_STARRED_QUERY, chooseFirstRoutesQuery())
    }

    @Test fun `chooseFallbackRoutesQuery returns the recent-routes predicate`() {
        // Pin the decision: the SECOND attempt (when starred is
        // empty) is recent-routes.
        assertEquals(FETCH_ROUTES_FALLBACK_QUERY, chooseFallbackRoutesQuery())
    }

    @Test fun `buildFetchRoutesUrl composes base + query string`() {
        val out = buildFetchRoutesUrl(
            baseUrl = "https://x.supabase.co",
            query = FETCH_ROUTES_STARRED_QUERY,
        )
        assertEquals(
            "https://x.supabase.co/rest/v1/routes?$FETCH_ROUTES_STARRED_QUERY",
            out,
        )
    }

    @Test fun `buildFetchRoutesUrl handles local-emulator base URL`() {
        // 10.0.2.2 is the Android emulator's loopback alias for the
        // host machine — what the watch hits against a local
        // Supabase stack. Make sure the URL composer doesn't
        // mangle the IPv4 numeric form.
        val out = buildFetchRoutesUrl(
            baseUrl = "http://10.0.2.2:54321",
            query = "anything",
        )
        assertEquals("http://10.0.2.2:54321/rest/v1/routes?anything", out)
    }

    // ───────────── refreshAccessToken wire shape ─────────────

    @Test fun `refresh body carries only refresh_token`() {
        // Critical security property: the refresh body must NEVER
        // include the current access token. Doing so would leak it
        // through proxy logs, and the access token is the thing
        // we're trying to REPLACE. Pin the single-key body.
        val out = buildRefreshTokenBody("rt-abc")
        assertEquals("""{"refresh_token":"rt-abc"}""", out)
    }

    @Test fun `refresh body escapes embedded quotes in the token`() {
        // A bogus / corrupted refresh token shouldn't crash the
        // JSON encoder. JsonObject handles escaping correctly.
        val out = buildRefreshTokenBody("""rt"with"quotes""")
        assertEquals("""{"refresh_token":"rt\"with\"quotes"}""", out)
    }

    @Test fun `refresh URL includes the grant_type query string`() {
        // GoTrue's `/auth/v1/token` endpoint multiplexes on
        // `grant_type` — refresh_token vs password. Missing the
        // query string misroutes the request to password-grant
        // where it 400s on the missing email+password fields.
        val out = buildRefreshTokenUrl("https://x.supabase.co")
        assertEquals(
            "https://x.supabase.co/auth/v1/token?grant_type=refresh_token",
            out,
        )
    }

    @Test fun `refresh URL with local-emulator base composes cleanly`() {
        val out = buildRefreshTokenUrl("http://10.0.2.2:54321")
        assertEquals(
            "http://10.0.2.2:54321/auth/v1/token?grant_type=refresh_token",
            out,
        )
    }

    // ───────────── computeRefreshExpiryMs ─────────────

    @Test fun `expiry uses GoTrue expires_in directly when present`() {
        // GoTrue returns `expires_in: 3600` for a 1-hour token.
        // Convert to absolute ms-from-epoch added to nowMs.
        val nowMs = 1_700_000_000_000L
        val out = computeRefreshExpiryMs(nowMs, expiresInSec = 3600L)
        assertEquals(nowMs + 3_600_000L, out)
    }

    @Test fun `expiry falls back to 1 hour when expires_in is null`() {
        // Defensive: GoTrue ALWAYS includes expires_in, but a
        // future server change shouldn't break the watch's
        // expiry tracking. Default to the historical 1-hour token
        // lifetime so the watch still knows when to refresh.
        val nowMs = 1_700_000_000_000L
        val out = computeRefreshExpiryMs(nowMs, expiresInSec = null)
        assertEquals(nowMs + 3_600_000L, out)
    }

    @Test fun `expiry honours short-lived tokens (60 sec edge case)`() {
        // GoTrue's `jwt_exp` config can be set as low as 60 s for
        // testing. Confirm the math works without overflow / loss.
        val nowMs = 0L
        val out = computeRefreshExpiryMs(nowMs, expiresInSec = 60L)
        assertEquals(60_000L, out)
    }

    @Test fun `expiry honours long-lived tokens (1 week edge case)`() {
        // Some self-hosted Supabase deployments use week-long
        // tokens. Confirm no overflow.
        val nowMs = 1_700_000_000_000L
        val weekSec = 7L * 24 * 3600
        val out = computeRefreshExpiryMs(nowMs, expiresInSec = weekSec)
        assertEquals(nowMs + weekSec * 1000L, out)
    }
}

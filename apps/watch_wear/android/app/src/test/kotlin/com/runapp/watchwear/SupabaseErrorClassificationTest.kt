package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/// Regression guard for the post-stop "unauthorized" sync error.
///
/// SupabaseClient.execute throws HttpException whose message comes from
/// humanErrorMessage(code, body) — i.e., the body's `msg` /
/// `error_description` / `error` / `message` field, falling back to
/// `"HTTP $code"` only when none of those parse. The first half of this
/// suite locks in that field-precedence so a future refactor can't quietly
/// regress it; the second half asserts the drain classifier branches on
/// the typed `HttpException.code` rather than the (sometimes-empty,
/// sometimes-human-prose) message.
///
/// The historical bug: drainQueue detected 401s by `msg.contains("HTTP 401")`,
/// but humanErrorMessage strips that string the moment the response body has
/// any of the four well-known fields — which Supabase always populates for
/// auth failures. So 401 → refresh+retry was effectively dead code, and the
/// user saw "JWT expired" / "unauthorized" surface as a sticky syncError.
class SupabaseErrorClassificationTest {

    // ---------- humanErrorMessage field precedence ----------

    @Test
    fun `humanErrorMessage prefers msg`() {
        val out = humanErrorMessage(
            401,
            """{"msg":"Invalid JWT","error":"unauthorized","message":"x"}""",
        )
        assertEquals("Invalid JWT", out)
    }

    @Test
    fun `humanErrorMessage falls through msg to error_description`() {
        val out = humanErrorMessage(
            401,
            """{"error_description":"Refresh token reused","error":"invalid_grant"}""",
        )
        assertEquals("Refresh token reused", out)
    }

    @Test
    fun `humanErrorMessage falls through to error`() {
        val out = humanErrorMessage(401, """{"error":"unauthorized"}""")
        assertEquals("unauthorized", out)
    }

    @Test
    fun `humanErrorMessage falls through to message`() {
        // The PostgREST shape — what an expired JWT on the runs-table
        // POST actually returns. This is the body that originally
        // defeated `msg.contains("HTTP 401")` in drainQueue.
        val out = humanErrorMessage(401, """{"message":"JWT expired","code":"PGRST301"}""")
        assertEquals("JWT expired", out)
    }

    @Test
    fun `humanErrorMessage falls back to HTTP code on empty body`() {
        assertEquals("HTTP 401", humanErrorMessage(401, ""))
    }

    @Test
    fun `humanErrorMessage falls back to HTTP code on non-json body`() {
        assertEquals("HTTP 503", humanErrorMessage(503, "<html>upstream timeout</html>"))
    }

    @Test
    fun `humanErrorMessage falls back to HTTP code when no known field present`() {
        assertEquals("HTTP 418", humanErrorMessage(418, """{"hint":"i am a teapot"}"""))
    }

    // ---------- classifyDrainError ----------

    @Test
    fun `401 with body-derived message routes to refresh-and-retry`() {
        // The exact shape that produced the bug — the message has no
        // "HTTP 401" substring because humanErrorMessage stripped the
        // status in favour of the body field. A status-code-aware
        // classifier still picks the right branch.
        val action = classifyDrainError(HttpException(401, "JWT expired"))
        assertSame(DrainAction.RetryAfterRefresh, action)
    }

    @Test
    fun `401 with unauthorized error string also routes to refresh-and-retry`() {
        val action = classifyDrainError(HttpException(401, "unauthorized"))
        assertSame(DrainAction.RetryAfterRefresh, action)
    }

    @Test
    fun `409 routes to drop-and-continue (idempotent re-upload)`() {
        val action = classifyDrainError(HttpException(409, "duplicate key value"))
        assertSame(DrainAction.DropAndContinue, action)
    }

    @Test
    fun `400 404 422 route to skip-and-continue (permanent)`() {
        for (code in listOf(400, 404, 422)) {
            assertSame(
                "code $code",
                DrainAction.SkipAndContinue,
                classifyDrainError(HttpException(code, "bad request")),
            )
        }
    }

    @Test
    fun `5xx routes to stop-and-retry-later`() {
        for (code in listOf(500, 502, 503, 504)) {
            assertSame(
                "code $code",
                DrainAction.StopAndRetryLater,
                classifyDrainError(HttpException(code, "upstream")),
            )
        }
    }

    @Test
    fun `unknown 4xx routes to skip-and-continue`() {
        // 418, 429, etc. — not specifically classified, treat as
        // permanent so the loop moves on rather than thrashing.
        assertSame(
            DrainAction.SkipAndContinue,
            classifyDrainError(HttpException(429, "rate limited")),
        )
    }

    @Test
    fun `network-layer timeout routes to stop-and-retry-later`() {
        // Non-HttpException path: OkHttp surfaces these as plain
        // IOException / SocketTimeoutException with the message we sniff.
        val action = classifyDrainError(RuntimeException("timeout connecting to host"))
        assertSame(DrainAction.StopAndRetryLater, action)
    }

    @Test
    fun `dns failure routes to stop-and-retry-later`() {
        val action = classifyDrainError(RuntimeException("Unable to resolve host \"x.supabase.co\""))
        assertSame(DrainAction.StopAndRetryLater, action)
    }

    @Test
    fun `connection-refused routes to stop-and-retry-later`() {
        // OkHttp/java.net wording when the backend is unreachable — the most
        // common offline error on a watch, previously mis-classified
        // permanent (defeating short-circuit + backoff).
        val action = classifyDrainError(
            RuntimeException("Failed to connect to threkir.supabase.co/1.2.3.4:443"),
        )
        assertSame(DrainAction.StopAndRetryLater, action)
    }

    @Test
    fun `connection-reset routes to stop-and-retry-later`() {
        val action = classifyDrainError(java.net.SocketException("Connection reset"))
        assertSame(DrainAction.StopAndRetryLater, action)
    }

    @Test
    fun `econnrefused routes to stop-and-retry-later`() {
        val action = classifyDrainError(
            RuntimeException("connect failed: ECONNREFUSED (Connection refused)"),
        )
        assertSame(DrainAction.StopAndRetryLater, action)
    }

    @Test
    fun `truncated body routes to stop-and-retry-later`() {
        val action = classifyDrainError(java.io.IOException("unexpected end of stream"))
        assertSame(DrainAction.StopAndRetryLater, action)
    }

    @Test
    fun `unknown non-http error routes to skip-and-continue`() {
        val action = classifyDrainError(RuntimeException("nothing in particular"))
        assertSame(DrainAction.SkipAndContinue, action)
    }
}

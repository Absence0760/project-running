package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// Unit tests for `StoredSession` — the persisted auth shape that
/// survives cold launch so a watch can start a run without
/// connectivity. The `isExpired` method gates `RunViewModel`'s
/// proactive token refresh; a bug in its boundary handling would
/// either thrash refresh calls (refresh-too-eager) or 401-silent
/// (refresh-too-late). Pin every boundary case so a future tweak to
/// the safety margin (currently 60s) doesn't drift.
///
/// Also pins one DELIBERATE edge of the contract that deserves
/// future-reviewer attention: an `expiresAtMs <= 0` session is
/// currently treated as NEVER expired (the `expiresAtMs > 0 && ...`
/// guard). See the "expiresAtMs zero" test below for the trade-off
/// rationale.
class StoredSessionTest {

    private val baseSession = StoredSession(
        accessToken = "access-tok",
        refreshToken = "refresh-tok",
        userId = "user-1",
        baseUrl = "http://127.0.0.1:54321",
        anonKey = "anon-key",
        expiresAtMs = 1_000_000L, // arbitrary
    )

    // ───────────────────── isExpired boundaries ─────────────────────

    @Test
    fun `not expired when now is well before the expiry`() {
        // 3600s = 1h pre-expiry → refresh sits idle. The far-from-
        // expiry case is the most common — `refreshIfExpired` reads
        // this on every API call.
        val s = baseSession.copy(expiresAtMs = 10_000_000L)
        assertFalse(s.isExpired(nowMs = 10_000_000L - 3_600_000L))
    }

    @Test
    fun `not expired at expiresAtMs minus 60001 ms (1s outside margin)`() {
        // Just OUTSIDE the 60s safety margin → still valid. A
        // regression that shifted the margin to 30s would flip this
        // to true and trigger unnecessary refresh cycles.
        val s = baseSession.copy(expiresAtMs = 1_000_000L)
        assertFalse(s.isExpired(nowMs = 1_000_000L - 60_001L))
    }

    @Test
    fun `expired at expiresAtMs minus exactly 60000 ms (margin inclusive)`() {
        // `nowMs >= expiresAtMs - 60_000` — the margin boundary is
        // INCLUSIVE. At exactly margin-edge, refresh fires. A
        // regression to strict `>` would let the session race the
        // network call (refresh fires AT expiry rather than 60s
        // before).
        val s = baseSession.copy(expiresAtMs = 1_000_000L)
        assertTrue(s.isExpired(nowMs = 1_000_000L - 60_000L))
    }

    @Test
    fun `expired well within the 60s safety margin`() {
        // 30s before actual expiry → should be flagged so the
        // refresh has time to complete before the access token
        // would have 401'd.
        val s = baseSession.copy(expiresAtMs = 1_000_000L)
        assertTrue(s.isExpired(nowMs = 1_000_000L - 30_000L))
    }

    @Test
    fun `expired exactly at expiresAtMs`() {
        val s = baseSession.copy(expiresAtMs = 1_000_000L)
        assertTrue(s.isExpired(nowMs = 1_000_000L))
    }

    @Test
    fun `expired past expiresAtMs`() {
        // The session has already 401'd — at this point refresh is
        // best-effort and likely to surface "please sign in again"
        // when refresh token has also expired.
        val s = baseSession.copy(expiresAtMs = 1_000_000L)
        assertTrue(s.isExpired(nowMs = 1_000_000L + 3_600_000L))
    }

    // ───────────────────── expiresAtMs zero — DELIBERATE edge ────

    @Test
    fun `expiresAtMs zero is treated as NOT expired (current contract)`() {
        // ── Future-reviewer note ────────────────────────────────
        // The `expiresAtMs > 0 && ...` guard in isExpired means a
        // session with expiresAtMs == 0 is treated as NEVER expired.
        // In practice this shouldn't happen — SignInResult builds
        // expiresAtMs as `now + expires_in * 1000`, and SessionBridge
        // forwards the phone's Supabase onAuthStateChange expiry.
        //
        // BUT — a future migration / refactor / partial-prefs-clear
        // that zeroed the persisted expiresAtMs would silently
        // disable refreshIfExpired, leading to silent 401s on every
        // subsequent API call (no proactive refresh, no user
        // signal).
        //
        // The safer alternative would be `expiresAtMs <= 0`-treated-
        // as-expired so refresh fires, fails loud if the refresh
        // token has also expired, and prompts re-sign-in. Flipping
        // this is a deliberate change that needs broader sign-off
        // (changes the cold-launch behaviour for any session that's
        // ever had a zero-expiry persisted). This test PINS the
        // current contract so a stealth flip would fail loud here.
        val s = baseSession.copy(expiresAtMs = 0L)
        assertFalse(s.isExpired(nowMs = 9_999_999_999L))
    }

    @Test
    fun `negative expiresAtMs is treated as NOT expired (same guard)`() {
        // Same `> 0` guard — negative values are also "never
        // expired" today. Negative wouldn't arise from honest sign-
        // in (always a positive future ms), but pinning the
        // negative-input behaviour catches a `Long.MIN_VALUE` /
        // overflow regression.
        val s = baseSession.copy(expiresAtMs = -1L)
        assertFalse(s.isExpired(nowMs = 9_999_999_999L))
    }

    // ───────────────────── fromPayload mapping ─────────────────────

    @Test
    fun `fromPayload copies every field from the phone-push shape`() {
        // The wire shape between SessionBridge (receiver) and
        // SessionStore (persistence). A field misalignment here
        // would silently lose part of the session — e.g. anonKey
        // dropping would surface as "401 missing apikey" on every
        // request.
        val p = SessionPayload(
            accessToken = "a",
            refreshToken = "r",
            userId = "u",
            baseUrl = "http://b",
            anonKey = "k",
            expiresAtMs = 12345L,
        )
        val s = StoredSession.fromPayload(p)
        assertEquals("a", s.accessToken)
        assertEquals("r", s.refreshToken)
        assertEquals("u", s.userId)
        assertEquals("http://b", s.baseUrl)
        assertEquals("k", s.anonKey)
        assertEquals(12345L, s.expiresAtMs)
    }

    @Test
    fun `fromPayload roundtrips through isExpired with the inherited expiry`() {
        // Belt-and-braces: a fromPayload-built session with a past
        // expiry IS expired, future is not. Catches any
        // field-shift regression in fromPayload that mapped
        // expiresAtMs onto the wrong slot.
        val past = SessionPayload(
            accessToken = "a", refreshToken = "r", userId = "u",
            baseUrl = "http://b", anonKey = "k",
            expiresAtMs = 1L,
        )
        assertTrue(StoredSession.fromPayload(past).isExpired(nowMs = 2L))
        val future = past.copy(expiresAtMs = 9_999_999_999L)
        assertFalse(StoredSession.fromPayload(future).isExpired(nowMs = 1L))
    }
}

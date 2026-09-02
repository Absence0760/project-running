package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/// Unit + source-level guards for `SessionBridge`.
///
/// The Wearable Data Layer listener can't be exercised on a host JVM
/// (`DataClient` / `DataEvent` are Google Play Services types that need
/// the Wearable runtime), so this file pins the bug fix at two layers:
///
/// 1. **Sealed-class shape** — `SessionEvent.Updated` and
///    `SessionEvent.Cleared` are distinguishable, equality works, and
///    `Cleared` is a singleton. Without these the `when` branch in
///    `RunViewModel.bootstrapAuth` couldn't reliably dispatch.
/// 2. **Source-level guard** — the listener inside `SessionBridge.kt`
///    must handle BOTH `DataEvent.TYPE_CHANGED` AND
///    `DataEvent.TYPE_DELETED`. The original code only filtered on
///    `TYPE_CHANGED`, so a phone-side `dataClient.deleteDataItems(uri)`
///    (which is what `WearAuthBridge.kt` does when the user signs out
///    on the phone) was silently dropped on the watch and the watch
///    kept a stale session forever — every API call thereafter
///    succeeded under the signed-out user's tokens until they expired.
///    Pin the dual-type handling so a "tidy up" refactor that reverts
///    to a single-type filter fails loud here.
class SessionBridgeTest {

    private val samplePayload = SessionPayload(
        accessToken = "a",
        refreshToken = "r",
        userId = "u",
        baseUrl = "http://b",
        anonKey = "k",
        expiresAtMs = 12345L,
    )

    // ─────────────────────── sealed-class shape ───────────────────────

    @Test
    fun `Updated equals self by value`() {
        val a = SessionEvent.Updated(samplePayload)
        val b = SessionEvent.Updated(samplePayload)
        // data-class equality so the collector's `when (event)` branch
        // doesn't accidentally re-fire on logically-equal payloads.
        assertEquals(a, b)
    }

    @Test
    fun `Updated is distinguishable from Cleared`() {
        val updated: SessionEvent = SessionEvent.Updated(samplePayload)
        val cleared: SessionEvent = SessionEvent.Cleared
        assertNotEquals(updated, cleared)
        assertTrue(updated is SessionEvent.Updated)
        assertTrue(cleared is SessionEvent.Cleared)
    }

    @Test
    fun `Cleared is a singleton`() {
        // The object declaration is the contract — two references to
        // SessionEvent.Cleared MUST be the same instance so the
        // RunViewModel's `SessionEvent.Cleared ->` branch matches by
        // identity (a `data class Cleared()` would silently regress
        // this without the test failing).
        val a: SessionEvent = SessionEvent.Cleared
        val b: SessionEvent = SessionEvent.Cleared
        assertSame(a, b)
    }

    // ─────────────── receive-side grading (fail-closed) ───────────────

    private fun fields(
        accessToken: String? = "a",
        refreshToken: String? = "r",
        userId: String? = "u",
        baseUrl: String? = "http://b",
        anonKey: String? = "k",
        expiresAtMs: Long = 12345L,
    ) = SessionPayload.fromFields(
        accessToken = accessToken,
        refreshToken = refreshToken,
        userId = userId,
        baseUrl = baseUrl,
        anonKey = anonKey,
        expiresAtMs = expiresAtMs,
    )

    @Test
    fun `a complete push carries every field through`() {
        assertEquals(samplePayload, fields())
    }

    @Test
    fun `a push with no access token is refused, not blanked`() {
        // The regression: an absent field was coerced to "". The
        // ViewModel then SAVED that over the encrypted cached session —
        // the one credential a watch out of Bluetooth range still holds —
        // and set authed = true, so the sign-in affordance stayed hidden
        // behind a session that can never authenticate one request.
        assertNull(fields(accessToken = null))
        assertNull(fields(accessToken = ""))
    }

    @Test
    fun `a push with no refresh token is refused`() {
        // Reachable from a shipped writer, not only from corruption:
        // the phone's `wear_auth_bridge.dart` sends
        // `session.refreshToken ?? ''`, and the phone-side parser checks
        // presence and type but never emptiness — so an empty string is
        // a value the sender is built to produce.
        assertNull(fields(refreshToken = null))
        assertNull(fields(refreshToken = ""))
    }

    @Test
    fun `a push with no user id is refused`() {
        assertNull(fields(userId = null))
        assertNull(fields(userId = ""))
    }

    @Test
    fun `a push with no base url is refused`() {
        assertNull(fields(baseUrl = null))
        assertNull(fields(baseUrl = ""))
    }

    @Test
    fun `a push with no anon key is refused`() {
        assertNull(fields(anonKey = null))
        assertNull(fields(anonKey = ""))
    }

    @Test
    fun `a whitespace-only field is refused like an absent one`() {
        // A DataMap carrying " " is exactly as unusable as one carrying
        // nothing, and reads as present to a null check.
        assertNull(fields(accessToken = " "))
        assertNull(fields(anonKey = "\t"))
    }

    @Test
    fun `a zero expiry is NOT a refusal`() {
        // `StoredSession.isExpired` documents 0 as NOT expired and
        // `StoredSessionTest` pins it. Grading the expiry here would
        // reject a session the rest of the app calls valid; the five
        // strings are the load-bearing set.
        assertEquals(0L, fields(expiresAtMs = 0L)?.expiresAtMs)
    }

    @Test
    fun `an unusable push does not reach the flow, and is not a sign-out`() {
        // Source-level: the TYPE_CHANGED branch must grade through
        // `fromDataMapOrNull` and emit only on a non-null. Emitting
        // `Cleared` instead would be worse than the bug — it runs
        // `tearDownSession`, which WIPES the unsynced-run queue and its
        // track files (LocalRunStore.clear, fail-closed against
        // cross-user upload). A malformed push must leave the session
        // the watch already holds alone.
        val src = File(
            "src/main/kotlin/com/runapp/watchwear/SessionBridge.kt"
        ).readText()
        assertTrue(
            "the TYPE_CHANGED branch must grade the DataMap through " +
                "fromDataMapOrNull before emitting",
            src.contains("fromDataMapOrNull(dm)?.let"),
        )
        assertTrue(
            "the cold-start current() read must grade through the same " +
                "helper — it applies a session on exactly the same path",
            src.contains("fromDataMapOrNull(DataMapItem.fromDataItem(item).dataMap)"),
        )
        assertFalse(
            "no field may be coerced to an empty string on the receive " +
                "side — that coercion IS the bug",
            src.contains("?: \"\""),
        )
    }

    // ─────────────────── source-level fix guard ───────────────────

    @Test
    fun `SessionBridge listener handles both TYPE_CHANGED and TYPE_DELETED`() {
        // Source-level guard: the listener inside the callbackFlow must
        // dispatch on BOTH event types. A regression to "only handle
        // TYPE_CHANGED" silently breaks phone-driven sign-out on the
        // watch — see this file's KDoc.
        val src = File(
            "src/main/kotlin/com/runapp/watchwear/SessionBridge.kt"
        ).readText()
        assertTrue(
            "SessionBridge.kt must reference DataEvent.TYPE_CHANGED " +
                "(updated-payload branch)",
            src.contains("DataEvent.TYPE_CHANGED"),
        )
        assertTrue(
            "SessionBridge.kt must reference DataEvent.TYPE_DELETED " +
                "(phone-side sign-out propagation — the bug this " +
                "guards against was the TYPE_CHANGED-only filter " +
                "silently dropping deletes)",
            src.contains("DataEvent.TYPE_DELETED"),
        )
        // And the emission must wire `Cleared` into the Flow, not just
        // log it or drop it. A future regression that reads the event
        // type but forgets to `trySend(SessionEvent.Cleared)` would
        // still pass the two contains() above.
        assertTrue(
            "SessionBridge.kt must `trySend(SessionEvent.Cleared)` " +
                "for the TYPE_DELETED branch — otherwise the listener " +
                "sees the delete but the consumer never does",
            src.contains("SessionEvent.Cleared"),
        )
    }
}

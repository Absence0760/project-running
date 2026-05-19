package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertEquals
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

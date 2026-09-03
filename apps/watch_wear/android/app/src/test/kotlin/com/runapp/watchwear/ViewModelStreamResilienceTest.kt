package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// The sibling of `SensorStreamResilienceTest`, one layer up.
///
/// `RunViewModel` installs no `CoroutineExceptionHandler`, and
/// `viewModelScope` is a `SupervisorJob` — which stops a failing child
/// from cancelling its siblings but does NOT stop an unhandled throw in
/// a `launch` reaching the thread's uncaught handler, which on Android
/// is the process. The recording service lives in that same process, so
/// a phone-pushed session update that throws ends the run.
///
/// Three flows cross a boundary the view model does not control: the two
/// Wearable Data Layer bridges (the paired phone's session and starred
/// routes, delivered by Google Play Services) and the DataStore-backed
/// run queue, which surfaces a corrupt file as an exception in the flow
/// rather than as an empty read. Each needs a `catch` on the STREAM —
/// a `try` inside the collect lambda does not see an upstream failure —
/// and the ones whose bodies do disk, crypto or network work need a
/// guard on the BODY as well (decisions § 1054).
///
/// The asymmetry that made this findable: the one-shot `current()` reads
/// of both bridges were already wrapped, with `no paired phone, fine`
/// written beside one of them. The streaming reads of the same payloads,
/// running the same handlers, were not.
class ViewModelStreamResilienceTest {

    private val src: String by lazy {
        File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()
    }

    /// Derived, not listed: a third bridge added tomorrow is covered by
    /// this without anyone remembering to extend it.
    private fun bridgeStreams(): List<String> =
        Regex("""\w+Bridge\.events""").findAll(src).map { it.value }.distinct().sorted().toList()

    @Test
    fun `the guard is reading the bridges it claims to`() {
        assertTrue(
            "no `<x>Bridge.events` stream parsed out of RunViewModel — the " +
                "check below would pass on anything",
            bridgeStreams().size >= 2,
        )
    }

    @Test
    fun `every data-layer bridge stream carries a catch`() {
        val unguarded = bridgeStreams()
            .filterNot { Regex(Regex.escape(it) + """\s*\.catch""").containsMatchIn(src) }
        assertEquals(
            "collected with no `.catch` on the stream, so a Data Layer " +
                "failure reaches the uncaught handler and kills the process " +
                "the recording service is in: $unguarded",
            emptyList<String>(),
            unguarded,
        )
    }

    @Test
    fun `the run queue stream carries a catch`() {
        // DataStore reports a corrupt or unreadable file by failing the
        // flow. The queue is exactly what such a file would be — the
        // runner's unsynced runs — so losing the process over it loses
        // the recording that was about to join them.
        assertTrue(
            "store.queue is collected with no `.catch`",
            Regex("""store\.queue\s*\.catch""").containsMatchIn(src),
        )
    }

    @Test
    fun `the session bridge guards the body as well as the stream`() {
        // `.catch` covers upstream only. Everything this handler reaches
        // — the encrypted session store, the route / run / tile wipes on
        // sign-out, the queue drain — can throw from inside the collect,
        // where `.catch` cannot see it.
        assertTrue(
            "the sessionBridge collect body must be wrapped — encrypted-store " +
                "I/O and the sign-out wipes run inside it",
            Regex(
                """sessionBridge\.events.{0,400}?\.collect\s*\{[^{}]*try\s*\{""",
                RegexOption.DOT_MATCHES_ALL,
            ).containsMatchIn(src),
        )
    }

    @Test
    fun `no guard is completely silent`() {
        // Not a demand for a log on every catch — several of these are
        // advisory polls whose comment IS the rationale. What must not
        // exist is a catch that says nothing at all: sign-out's tile-cache
        // wipe was one, and the cache that survives it is a map of where
        // the signed-out user runs.
        val silent = Regex("""catch\s*\([^)]*\)\s*\{\s*\}""")
            .findAll(src)
            .map { it.value }
            .toList()
        assertEquals(
            "a catch in RunViewModel with an empty body — no log, no state, " +
                "not even a reason: $silent",
            emptyList<String>(),
            silent,
        )
    }
}

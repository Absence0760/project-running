package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// The sibling of `SensorStreamResilienceTest`, one layer up.
///
/// `viewModelScope` is a `SupervisorJob` — which stops a failing child
/// from cancelling its siblings but does NOT stop an unhandled throw in
/// a `launch` reaching the thread's uncaught handler, which on Android
/// is the process. The recording service lives in that same process, so
/// a phone-pushed session update that throws ends the run.
///
/// Two rungs answer that, and the tests below hold both. The per-site
/// guards are the first: a failure the runner should hear about is
/// caught where it happens and reported. `launchGuarded` is the second —
/// a `CoroutineExceptionHandler` under every `launch` in the class, so
/// the sites nobody has reached yet log instead of ending the run
/// (decisions § 1082).
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
    fun `the run queue stream is retried, not caught`() {
        // DataStore reports a corrupt or unreadable file by failing the
        // flow. The queue is exactly what such a file would be — the
        // runner's unsynced runs — so losing the process over it loses
        // the recording that was about to join them.
        //
        // `.catch` answered that and cost more than it saved: catch
        // COMPLETES the flow, so one failed read froze `queuedCount` at its
        // last value for the life of the process and the pre-run chip, gated
        // on `queuedCount > 0`, never appeared again. Catching is not a
        // judgement about corruption — it is a judgement that the FIRST
        // failure is the LAST one (decisions § 1104).
        assertTrue(
            "store.queue is collected with a terminal `.catch` — after one " +
                "failed read the count freezes and the pre-run Sync chip can " +
                "never appear again; retry the stream instead",
            !Regex("""store\.queue\s*\.catch""").containsMatchIn(src),
        )
        assertTrue(
            "store.queue must be retried so a read that fails once can " +
                "recover without a process restart",
            Regex("""store\.queue\s*\.retryWhen""").containsMatchIn(src),
        )
    }

    @Test
    fun `the queue retry backs off and says the count is stale`() {
        val body = Regex(
            """store\.queue\s*\.retryWhen\s*\{(.*?)\n                \}""",
            RegexOption.DOT_MATCHES_ALL,
        ).find(src)
        assertTrue("no `store.queue.retryWhen { … }` body parsed — the checks below read nothing", body != null)
        val branch = body!!.groupValues[1]
        assertTrue(
            "the retry must delay — an unbounded immediate retry against a " +
                "corrupt DataStore file is a busy loop: $branch",
            branch.contains("delay(queueReadRetryDelayMs("),
        )
        assertTrue(
            "the retry must raise `queueUnreadable` — a count that is being " +
                "retried is stale, and the pre-run screen has no other way to " +
                "know it: $branch",
            branch.contains("queueUnreadable = true"),
        )
        assertTrue(
            "the retry must log — a stream failing every minute in silence is " +
                "the state this exists to make visible: $branch",
            branch.contains("Log."),
        )
    }

    @Test
    fun `a successful read clears the stale flag`() {
        // Both readers of the file set the flag, so whichever read last
        // decides whether the figure on screen still stands. Without the
        // clear on the collect, a queue that recovered would keep offering a
        // retry chip for a count it now knows.
        assertTrue(
            "the queue collect must clear `queueUnreadable`",
            Regex(
                """\.collect\s*\{\s*list\s*->.{0,400}?queueUnreadable = false""",
                RegexOption.DOT_MATCHES_ALL,
            ).containsMatchIn(src),
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

    /// Derived, not listed: the helper's own definition is the one place
    /// `viewModelScope.launch` may appear.
    @Test
    fun `every coroutine this view model starts carries the crash handler`() {
        val bare = Regex("""viewModelScope\.launch\s*\{""").findAll(src).count()
        assertEquals(
            "a `viewModelScope.launch { … }` outside `launchGuarded` — a handler " +
                "on every site but one is the same defect with better odds; use " +
                "`launchGuarded { … }`",
            0,
            bare,
        )
        assertTrue(
            "`launchGuarded` must pass the handler into the launch it delegates to",
            Regex("""fun launchGuarded[^=]*=\s*viewModelScope\.launch\(crashGuard""")
                .containsMatchIn(src),
        )
        assertTrue(
            "the handler must report — a `CoroutineExceptionHandler` that swallows " +
                "silently trades a crash for an invisible one",
            Regex(
                """crashGuard\s*=\s*CoroutineExceptionHandler\s*\{[^}]*Log\.""",
                RegexOption.DOT_MATCHES_ALL,
            ).containsMatchIn(src),
        )
    }

    @Test
    fun `the guard is reading a view model that still launches coroutines`() {
        // Without this the count-zero assertion above passes on an empty read.
        assertTrue(
            "no `launchGuarded {` found in RunViewModel — the check above would " +
                "pass on a file that had stopped launching anything",
            Regex("""launchGuarded\s*\{""").findAll(src).count() >= 20,
        )
    }

    @Test
    fun `an unreadable run queue is not drained as an empty one`() {
        // `.first()` on the same DataStore-backed flow the stream `.catch`
        // covers. The three available answers are not equivalent: an empty
        // list drains nothing and reports success, so the sync banner clears
        // on the one condition that guarantees nothing can ever sync.
        val guarded = Regex(
            """try\s*\{\s*store\.queue\.first\(\)\s*\}\s*catch\s*\([^)]*\)\s*\{(.*?)\n        \}""",
            RegexOption.DOT_MATCHES_ALL,
        ).find(src)
        assertTrue(
            "`store.queue.first()` in the drain is unguarded — a corrupt queue " +
                "file reaches the crash handler and the drain is skipped with no " +
                "record of why",
            guarded != null,
        )
        val branch = guarded!!.groupValues[1]
        assertTrue(
            "the failure branch must arm backoff — the condition persists, so " +
                "every network flap would otherwise retry a read that cannot " +
                "succeed: $branch",
            branch.contains("drainBackoff.onFailure()"),
        )
        assertTrue(
            "the failure branch must surface it as syncError — a queue that " +
                "cannot be read is the one state in which 'Synced' is a lie: " +
                "$branch",
            branch.contains("syncError ="),
        )
        assertTrue(
            "the failure branch must return rather than fall through into the " +
                "drain loop with no snapshot: $branch",
            branch.contains("return"),
        )
        assertTrue(
            "the failure branch must raise `queueUnreadable` — the drain and " +
                "the stream read the same file, and a pre-run chip that " +
                "disagrees with the drain about whether the queue is readable " +
                "is worse than either answer: $branch",
            branch.contains("queueUnreadable = true"),
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

    /// Blocking calls this class makes that must not run on the collector's
    /// thread. Every emission the view model handles arrives on
    /// `Dispatchers.Main.immediate` — `launchGuarded` is `viewModelScope`,
    /// and `handleFinishedRun` is called straight out of the
    /// `RecordingRepository.metrics` collect body — so a disk read there is a
    /// frozen watch, not a slow one.
    private val blockingIoCalls = listOf(
        ".readText()", ".readBytes()", ".writeText()",
        ".exists()", ".delete()", ".listFiles()",
    )

    /// Members at this class's own indent, `{` through the matching `\n    }`.
    /// Nested braces sit at eight spaces or more, so the four-space close is
    /// the member boundary — the same extraction `SignOutLifecycleWiringTest`
    /// uses on `tearDownSession`.
    private fun memberBodies(): Map<String, String> =
        Regex("""\n    (?:private |internal |public )*(?:suspend )?fun (\w+)\(([\s\S]*?)\n    \}""")
            .findAll(src)
            .associate { it.groupValues[1] to it.groupValues[2] }

    @Test
    fun `every blocking disk call in the view model runs on the IO dispatcher`() {
        val bodies = memberBodies()
        assertTrue(
            "no member bodies parsed out of RunViewModel.kt — the scan would pass on anything",
            bodies.size >= 20,
        )
        val touching = bodies.filterValues { body -> blockingIoCalls.any { body.contains(it) } }
        // Derived, not listed — but a scan that matches nothing is asleep
        // rather than clean: this class does touch disk in several places.
        assertTrue(
            "no member of RunViewModel matched any blocking disk call — the token " +
                "list has gone stale",
            touching.size >= 3,
        )
        val onMainThread = touching
            .filterValues { !it.contains("Dispatchers.IO") }
            .keys.sorted()
        assertEquals(
            "reads or writes disk without withContext(Dispatchers.IO): $onMainThread. " +
                "Every emission this class handles arrives on Dispatchers.Main.immediate, " +
                "so the call blocks the UI thread. readTrackForPreview was the outlier and " +
                "the largest — a 100-hour ultra's track is ~2.8 MB of JSON, read and parsed " +
                "between the runner pressing Stop and the post-run screen appearing.",
            emptyList<String>(),
            onMainThread,
        )
    }

}

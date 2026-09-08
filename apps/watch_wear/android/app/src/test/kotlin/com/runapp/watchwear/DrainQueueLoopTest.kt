package com.runapp.watchwear

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// Comprehensive coverage of `drainQueueLoop` — the offline-runs sync
/// orchestration extracted from `RunViewModel.drainQueue`. Tests every
/// per-error-class branch in isolation plus realistic mixed-outcome
/// sequences so the loop's behaviour under partial failure is pinned
/// in source.
///
/// The classifier itself (`classifyDrainError`) is covered by
/// `SupabaseErrorClassificationTest`; here we exercise the real
/// classifier via crafted HttpException codes so the per-action
/// branches reach `drainQueueLoop`'s switch arms.
class DrainQueueLoopTest {

    /// Every failure the loop reported this test, in the order it reported
    /// them. Fresh per test method — JUnit builds a new instance for each.
    ///
    /// The sink is a REQUIRED argument of `drainQueueLoop`, so no call below
    /// can be written without one. That is the point of it: the previous
    /// shape returned the failures on the result and nothing held the
    /// production caller to reading them, so the wrist's only diagnostic
    /// could be refactored away with this whole file still green.
    private val reported = mutableListOf<DrainFailure>()

    private fun run(id: String) = QueuedRun(
        id = id,
        startedAtIso = "2026-01-01T00:00:00Z",
        durationS = 3600,
        distanceM = 10_000.0,
        trackFilePath = "/tmp/$id.json",
        activityType = "run",
    )

    // ───────────────────────── happy paths ─────────────────────────

    @Test fun `empty queue drains to empty result with no failure`() = runBlocking {
        val result = drainQueueLoop(
            snapshot = emptyList(),
            push = PushQueuedRun { /* unreachable */ },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { /* unreachable */ },
            report = DrainFailureReport { reported += it },
            classify = { error("unreachable") },
        )
        assertEquals(emptyList<String>(), result.drainedIds)
        assertFalse(result.anyTransientFailure)
        assertNull(result.lastFault)
    }

    @Test fun `every-success path drains every id in order`() = runBlocking {
        val removed = mutableListOf<String>()
        val result = drainQueueLoop(
            snapshot = listOf(run("a"), run("b"), run("c")),
            push = PushQueuedRun { /* succeed */ },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { id -> removed += id },
            report = DrainFailureReport { reported += it },
            classify = { error("unreachable") },
        )
        assertEquals(listOf("a", "b", "c"), result.drainedIds)
        assertEquals(listOf("a", "b", "c"), removed)
        assertFalse(result.anyTransientFailure)
        // Successful pass clears the sync-error banner.
        assertNull(result.lastFault)
    }

    @Test fun `success clears a previous-run error message`() = runBlocking {
        // [success, success, success] should leave the fault null.
        var pushCalls = 0
        val result = drainQueueLoop(
            snapshot = listOf(run("a"), run("b"), run("c")),
            push = PushQueuedRun {
                pushCalls++
                // No throw — all succeed.
            },
            refresh = RefreshAuthForDrain { true },
            onSuccessfulDrain = OnSuccessfulDrain { },
            report = DrainFailureReport { reported += it },
            classify = { error("no errors thrown") },
        )
        assertEquals(3, pushCalls)
        assertNull(result.lastFault)
    }

    // ─────────────────── SkipAndContinue (4xx) ───────────────────

    @Test fun `409 keeps the id queued (skip) and keeps draining`() = runBlocking {
        // Regression guard for issue #404: a 409 must NOT drop the run.
        // The watch's own retries never 409 (a same-id re-POST merges on the
        // primary key and returns 200), so a 409 that surfaces is a genuine
        // conflict whose row may never have been inserted — dropping it would
        // silently lose the run. It is classified permanent-skip
        // (decisions.md §17), leaving it queued for manual discard.
        val removed = mutableListOf<String>()
        val pushedIds = mutableListOf<String>()
        val result = drainQueueLoop(
            snapshot = listOf(run("conflict"), run("clean")),
            push = PushQueuedRun { r ->
                pushedIds += r.id
                if (r.id == "conflict") throw HttpException(409, "duplicate key")
            },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { id -> removed += id },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        assertEquals(listOf("conflict", "clean"), pushedIds)
        // 409 must NOT remove the conflicting id — only the clean run drains.
        assertEquals(listOf("clean"), removed)
        assertEquals(listOf("clean"), result.drainedIds)
        // 409 is permanent, not transient — no backoff arming.
        assertFalse(result.anyTransientFailure)
    }

    @Test fun `400 skips the id (no remove) and keeps draining`() = runBlocking {
        val removed = mutableListOf<String>()
        val result = drainQueueLoop(
            snapshot = listOf(run("malformed"), run("clean")),
            push = PushQueuedRun { r ->
                if (r.id == "malformed") {
                    throw HttpException(400, "bad request")
                }
            },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { id -> removed += id },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        // 400 is permanent → SKIP, not remove. Only the clean run drains.
        assertEquals(listOf("clean"), result.drainedIds)
        // onSuccessfulDrain must NOT fire for the skipped run.
        assertEquals(listOf("clean"), removed)
        // Permanent failures don't arm backoff — retrying would just re-skip.
        assertFalse(result.anyTransientFailure)
        // Skip-followed-by-success clears the banner.
        assertNull(result.lastFault)
    }

    @Test fun `skip persists the fault when no later success clears it`() = runBlocking {
        // [skip-only] → the fault sticks for the UI banner.
        val result = drainQueueLoop(
            snapshot = listOf(run("malformed")),
            push = PushQueuedRun { throw HttpException(400, "bad request") },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        assertEquals(emptyList<String>(), result.drainedIds)
        assertFalse(result.anyTransientFailure)
        // Single permanent-skip run leaves the fault for the UI. The wrist is
        // told a catalogued sentence; the raw text a bug report needs rides
        // `failures` and reaches `Log.e`, never the display (decisions § 1490).
        assertEquals(SyncFault.Refused, result.lastFault)
        assertEquals(listOf("malformed"), reported.map { it.runId })
        assertEquals("bad request", reported.single().error.message)
    }

    // ─────────────────── StopAndRetryLater (5xx) ───────────────────

    @Test fun `5xx breaks the loop and does NOT touch later runs`() = runBlocking {
        val pushedIds = mutableListOf<String>()
        val result = drainQueueLoop(
            snapshot = listOf(run("a"), run("server-down"), run("c")),
            push = PushQueuedRun { r ->
                pushedIds += r.id
                if (r.id == "server-down") {
                    throw HttpException(503, "upstream timeout")
                }
            },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        // Loop must stop on 5xx — run 'c' never attempted.
        assertEquals(listOf("a", "server-down"), pushedIds)
        // Only the runs before the break drain.
        assertEquals(listOf("a"), result.drainedIds)
        // 5xx arms backoff so the next drain trigger waits.
        assertTrue(result.anyTransientFailure)
        assertEquals(SyncFault.ServerBusy, result.lastFault)
        assertEquals("upstream timeout", reported.single().error.message)
    }

    @Test fun `network timeout (non-http) also breaks the loop`() = runBlocking {
        val pushedIds = mutableListOf<String>()
        val result = drainQueueLoop(
            snapshot = listOf(run("a"), run("net-drop"), run("c")),
            push = PushQueuedRun { r ->
                pushedIds += r.id
                if (r.id == "net-drop") {
                    throw RuntimeException("timeout connecting to host")
                }
            },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        assertEquals(listOf("a", "net-drop"), pushedIds)
        assertTrue(result.anyTransientFailure)
    }

    // ─────────────────── RetryAfterRefresh (401) ───────────────────

    @Test fun `401 triggers refresh+retry and the retry SUCCEEDS`() = runBlocking {
        var pushAttempts = 0
        var refreshCalls = 0
        val removed = mutableListOf<String>()
        val result = drainQueueLoop(
            snapshot = listOf(run("a")),
            push = PushQueuedRun {
                pushAttempts++
                // First attempt: 401. Second attempt: success.
                if (pushAttempts == 1) throw HttpException(401, "JWT expired")
                // pushAttempts == 2 → no throw
            },
            refresh = RefreshAuthForDrain {
                refreshCalls++
                true
            },
            onSuccessfulDrain = OnSuccessfulDrain { id -> removed += id },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        // Initial push + one retry after refresh.
        assertEquals(2, pushAttempts)
        // Token refresh fires exactly once.
        assertEquals(1, refreshCalls)
        assertEquals(listOf("a"), removed)
        assertEquals(listOf("a"), result.drainedIds)
        // 401 followed by successful refresh+retry is NOT a transient failure.
        assertFalse(result.anyTransientFailure)
        assertNull(result.lastFault)
    }

    @Test fun `401 followed by REFRESH FAILURE stops + arms backoff`() = runBlocking {
        var pushAttempts = 0
        val removed = mutableListOf<String>()
        val result = drainQueueLoop(
            snapshot = listOf(run("a"), run("b")),
            push = PushQueuedRun {
                pushAttempts++
                throw HttpException(401, "JWT expired")
            },
            refresh = RefreshAuthForDrain { false },
            onSuccessfulDrain = OnSuccessfulDrain { id -> removed += id },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        // Push fires once; refresh fails → no retry; 'b' never attempted.
        assertEquals(1, pushAttempts)
        assertEquals(emptyList<String>(), removed)
        assertEquals(emptyList<String>(), result.drainedIds)
        // Refresh failure arms backoff so the next drain trigger waits.
        assertTrue(result.anyTransientFailure)
        // A 401 the refresh could not repair is the one fault whose remedy is
        // an action on the wrist, so it is its own member rather than a
        // generic failure.
        assertEquals(SyncFault.SignInRequired, result.lastFault)
        assertEquals("JWT expired", reported.single().error.message)
    }

    @Test fun `401 with refresh-throws stops + arms backoff`() = runBlocking {
        // The refresh lambda THROWS rather than returning false — same
        // outcome: stop the loop, arm backoff, surface the error.
        val result = drainQueueLoop(
            snapshot = listOf(run("a")),
            push = PushQueuedRun { throw HttpException(401, "JWT expired") },
            refresh = RefreshAuthForDrain { throw RuntimeException("refresh socket reset") },
            onSuccessfulDrain = OnSuccessfulDrain { },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        assertEquals(emptyList<String>(), result.drainedIds)
        assertTrue(result.anyTransientFailure)
        assertEquals(SyncFault.SignInRequired, result.lastFault)
        // Both throwables reach the log — the 401 that provoked the refresh and
        // the refresh's own failure. Only one of them can be the banner.
        assertEquals(
            listOf("JWT expired", "refresh socket reset"),
            reported.map { it.error.message },
        )
    }

    @Test fun `401, refresh succeeds, retry also 401, stops with backoff`() = runBlocking {
        // Refresh succeeds but the retry STILL 401's (token still
        // bad / revoked). Stop + backoff so we don't refresh-loop.
        var pushAttempts = 0
        var refreshCalls = 0
        val result = drainQueueLoop(
            snapshot = listOf(run("a"), run("b")),
            push = PushQueuedRun {
                pushAttempts++
                throw HttpException(401, "JWT expired")
            },
            refresh = RefreshAuthForDrain {
                refreshCalls++
                true
            },
            onSuccessfulDrain = OnSuccessfulDrain { },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        // Initial push + retry; both 401.
        assertEquals(2, pushAttempts)
        // Only ONE refresh attempt — no thrash.
        assertEquals(1, refreshCalls)
        assertEquals(emptyList<String>(), result.drainedIds)
        assertTrue(result.anyTransientFailure)
    }

    // ─────────────────── Mixed sequences ───────────────────

    @Test fun `mixed ok, 401-refresh-retry, ok drains all three`() = runBlocking {
        // Realistic case: queue has a couple runs, mid-way the token
        // expires, refresh succeeds, the rest sails through.
        var pushAttempts = 0
        val removed = mutableListOf<String>()
        var refreshCount = 0
        val result = drainQueueLoop(
            snapshot = listOf(run("a"), run("b"), run("c")),
            push = PushQueuedRun { r ->
                pushAttempts++
                // 'b' fails the first time with 401. After refresh,
                // 'b' succeeds. 'a' and 'c' always succeed.
                if (r.id == "b" && pushAttempts == 2) {
                    throw HttpException(401, "JWT expired")
                }
            },
            refresh = RefreshAuthForDrain {
                refreshCount++
                true
            },
            onSuccessfulDrain = OnSuccessfulDrain { id -> removed += id },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        assertEquals(listOf("a", "b", "c"), removed)
        // Exactly one refresh fired (only one 401).
        assertEquals(1, refreshCount)
        assertFalse(result.anyTransientFailure)
        assertNull(result.lastFault)
    }

    @Test fun `mixed ok, skip-permanent, ok drains 2, leaves skipped`() = runBlocking {
        val removed = mutableListOf<String>()
        val result = drainQueueLoop(
            snapshot = listOf(run("a"), run("malformed"), run("c")),
            push = PushQueuedRun { r ->
                if (r.id == "malformed") throw HttpException(422, "validation failed")
            },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { id -> removed += id },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        // Skipped run stays in the queue; clean ones drain.
        assertEquals(listOf("a", "c"), removed)
        assertEquals(listOf("a", "c"), result.drainedIds)
        assertFalse(result.anyTransientFailure)
        // Trailing success clears the banner even if a middle run was skipped.
        assertNull(result.lastFault)
    }

    @Test fun `mixed ok, transient, ok drains only the first and stops`() = runBlocking {
        // 5xx in the middle: the third run never gets a chance.
        val pushedIds = mutableListOf<String>()
        val removed = mutableListOf<String>()
        val result = drainQueueLoop(
            snapshot = listOf(run("a"), run("down"), run("c")),
            push = PushQueuedRun { r ->
                pushedIds += r.id
                if (r.id == "down") throw HttpException(502, "bad gateway")
            },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { id -> removed += id },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        // 'c' is never attempted — loop broke on 'down'.
        assertEquals(listOf("a", "down"), pushedIds)
        assertEquals(listOf("a"), removed)
        assertTrue(result.anyTransientFailure)
        assertEquals(SyncFault.ServerBusy, result.lastFault)
        assertEquals("bad gateway", reported.single().error.message)
    }

    @Test fun `pure-skip queue does NOT arm backoff`() = runBlocking {
        // Three stuck runs in a row, all 400. The user has bad data
        // they need to manually discard. We must NOT thrash backoff
        // for permanent errors — backing off would just delay the
        // user discovering the problem.
        val result = drainQueueLoop(
            snapshot = listOf(run("a"), run("b"), run("c")),
            push = PushQueuedRun { throw HttpException(400, "validation failed") },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        assertEquals(emptyList<String>(), result.drainedIds)
        // Permanent skips don't count as transient — backoff stays off.
        assertFalse(result.anyTransientFailure)
        assertEquals(SyncFault.Refused, result.lastFault)
        // Three refusals, three log lines. The banner can only say one thing;
        // the diagnostic must not lose the other two.
        assertEquals(listOf("a", "b", "c"), reported.map { it.runId })
    }

    // ─────────────────── Side-effect ordering ───────────────────

    @Test fun `onSuccessfulDrain fires AFTER push succeeds, never before`() = runBlocking {
        val order = mutableListOf<String>()
        drainQueueLoop(
            snapshot = listOf(run("a")),
            push = PushQueuedRun { order += "push" },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { order += "remove" },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        // Removing from the queue BEFORE the push would lose the run
        // on retry. Pin the order.
        assertEquals(listOf("push", "remove"), order)
    }

    @Test fun `push throwing means onSuccessfulDrain NOT called`() = runBlocking {
        val removed = mutableListOf<String>()
        drainQueueLoop(
            snapshot = listOf(run("a")),
            push = PushQueuedRun { throw HttpException(503, "down") },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { id -> removed += id },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        // Removing a run that failed to upload would lose data —
        // bug must not regress.
        assertTrue(removed.isEmpty())
    }

    // ───────────── Permanent rejection, carried out to the UI ─────────────

    @Test fun `a permanent skip is reported as a rejection a later success cannot erase`() = runBlocking {
        // The defect: `lastFault = null` runs on every success, so the trailing
        // clean run wiped the skipped run's message, `anyTransientFailure` stayed
        // false, and the caller reported a successful sync while the queue count
        // never fell. `lastFault` KEEPS that behaviour — the two assertions above
        // state it deliberately — and the rejection rides its own field.
        val result = drainQueueLoop(
            snapshot = listOf(run("malformed"), run("clean")),
            push = PushQueuedRun { r ->
                if (r.id == "malformed") throw HttpException(422, "validation failed")
            },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        assertEquals(listOf("malformed"), result.rejectedIds)
        assertEquals(listOf("clean"), result.drainedIds)
        // The stated decision, unchanged.
        assertNull(result.lastFault)
        // …and the refusal is still in the log even though the banner cleared.
        assertEquals(listOf("malformed"), reported.map { it.runId })
        assertFalse(result.anyTransientFailure)
    }

    @Test fun `every classification that keeps the run queued is reported`() = runBlocking {
        val result = drainQueueLoop(
            snapshot = listOf(run("a"), run("b"), run("c"), run("d")),
            push = PushQueuedRun { r ->
                when (r.id) {
                    "a" -> throw HttpException(400, "bad request")
                    "b" -> throw HttpException(404, "no such table")
                    "c" -> throw HttpException(409, "duplicate key")
                    else -> throw HttpException(422, "validation failed")
                }
            },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { error("nothing drains") },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        assertEquals(listOf("a", "b", "c", "d"), result.rejectedIds)
        assertEquals(emptyList<String>(), result.drainedIds)
    }

    @Test fun `a report sink that throws does not take the drain with it`() = runBlocking {
        // The report is an L4 diagnostic hanging off the one path that carries
        // a runner's unsynced runs. A sink that throws must cost the log line
        // and nothing else — the alternative is a logger ending the pass that
        // was about to upload the run it was logging about.
        val result = drainQueueLoop(
            snapshot = listOf(run("a"), run("b")),
            push = PushQueuedRun { r ->
                if (r.id == "a") throw HttpException(400, "bad request")
            },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { reported += DrainFailure(it, SyncFault.Unknown, RuntimeException("drained")) },
            report = DrainFailureReport { error("the log is on fire") },
            classify = ::classifyDrainError,
        )
        assertEquals(listOf("a"), result.rejectedIds)
        assertEquals(listOf("b"), result.drainedIds)
        assertEquals(listOf("b"), reported.map { it.runId })
    }

    @Test fun `the refresh's own failure is reported, not only the 401 that provoked it`() = runBlocking {
        // The live lambda used to catch its own error and return a bare
        // `false`, so the one failure on this path — a session the server will
        // not renew — reached no log at all. Both throwables are reported and
        // only one of them is the banner.
        val result = drainQueueLoop(
            snapshot = listOf(run("a")),
            push = PushQueuedRun { throw HttpException(401, "JWT expired") },
            refresh = RefreshAuthForDrain { throw HttpException(400, "invalid_grant") },
            onSuccessfulDrain = OnSuccessfulDrain { error("nothing drains") },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        assertEquals(
            listOf("JWT expired", "invalid_grant"),
            reported.map { it.error.message },
        )
        assertEquals(SyncFault.SignInRequired, result.lastFault)
    }

    @Test fun `an all-success pass rejects nothing`() = runBlocking {
        val result = drainQueueLoop(
            snapshot = listOf(run("a"), run("b")),
            push = PushQueuedRun { },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { },
            report = DrainFailureReport { reported += it },
            classify = { error("unreachable") },
        )
        assertEquals(emptyList<String>(), result.rejectedIds)
        assertEquals(listOf("a", "b"), result.attemptedIds)
    }

    @Test fun `a transient break leaves every later run unattempted`() = runBlocking {
        // The reason `attemptedIds` exists: the caller carries rejections across
        // passes, and a run this pass never reached has no verdict to carry.
        val result = drainQueueLoop(
            snapshot = listOf(run("skipped"), run("down"), run("never-reached")),
            push = PushQueuedRun { r ->
                when (r.id) {
                    "skipped" -> throw HttpException(400, "bad request")
                    "down" -> throw HttpException(503, "upstream timeout")
                    else -> error("`never-reached` must not be attempted")
                }
            },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        assertEquals(listOf("skipped", "down"), result.attemptedIds)
        assertEquals(listOf("skipped"), result.rejectedIds)
        assertTrue(result.anyTransientFailure)
    }

    @Test fun `a 401 whose refresh-retry succeeds is attempted once and rejected never`() = runBlocking {
        var pushAttempts = 0
        val result = drainQueueLoop(
            snapshot = listOf(run("a")),
            push = PushQueuedRun {
                pushAttempts++
                if (pushAttempts == 1) throw HttpException(401, "JWT expired")
            },
            refresh = RefreshAuthForDrain { true },
            onSuccessfulDrain = OnSuccessfulDrain { },
            report = DrainFailureReport { reported += it },
            classify = ::classifyDrainError,
        )
        // Two pushes, one entry: `attemptedIds` is about runs, not requests.
        assertEquals(listOf("a"), result.attemptedIds)
        assertEquals(emptyList<String>(), result.rejectedIds)
    }

    // ───────────────────── rejectedAfterPass ─────────────────────

    private fun result(
        drained: List<String> = emptyList(),
        rejected: List<String> = emptyList(),
        attempted: List<String> = emptyList(),
    ) = DrainQueueLoopResult(
        drainedIds = drained,
        rejectedIds = rejected,
        attemptedIds = attempted,
        anyTransientFailure = false,
        lastFault = null,
    )

    @Test fun `a fresh rejection enters the carried set`() {
        assertEquals(
            setOf("a"),
            rejectedAfterPass(
                previouslyRejected = emptySet(),
                queuedIdsBeforePass = listOf("a", "b"),
                result = result(drained = listOf("b"), rejected = listOf("a"), attempted = listOf("a", "b")),
            ),
        )
    }

    @Test fun `a run this pass reached and did NOT reject loses its rejection`() {
        // The server was fixed, or the failure is transient this time. Either
        // way the standing claim is no longer this pass's verdict.
        assertEquals(
            emptySet<String>(),
            rejectedAfterPass(
                previouslyRejected = setOf("a"),
                queuedIdsBeforePass = listOf("a", "b"),
                result = result(attempted = listOf("a")),
            ),
        )
    }

    @Test fun `a run this pass never reached keeps the verdict of the pass that did`() {
        // A server that goes down before the loop reaches the stuck entry must
        // not take the only notice of it off the screen.
        assertEquals(
            setOf("b"),
            rejectedAfterPass(
                previouslyRejected = setOf("b"),
                queuedIdsBeforePass = listOf("a", "b"),
                result = result(attempted = listOf("a")),
            ),
        )
    }

    @Test fun `a rejection that drained this pass is dropped`() {
        assertEquals(
            emptySet<String>(),
            rejectedAfterPass(
                previouslyRejected = setOf("a"),
                queuedIdsBeforePass = listOf("a"),
                result = result(drained = listOf("a"), attempted = listOf("a")),
            ),
        )
    }

    @Test fun `a rejection for an id no longer in the queue is dropped`() {
        // Discarded from the chip, or cleared by a sign-out. Carrying it would
        // keep the chip claiming a run that does not exist.
        assertEquals(
            emptySet<String>(),
            rejectedAfterPass(
                previouslyRejected = setOf("gone"),
                queuedIdsBeforePass = listOf("a"),
                result = result(drained = listOf("a"), attempted = listOf("a")),
            ),
        )
    }

    @Test fun `an empty pass over an empty queue carries nothing`() {
        assertEquals(
            emptySet<String>(),
            rejectedAfterPass(
                previouslyRejected = setOf("a"),
                queuedIdsBeforePass = emptyList(),
                result = result(),
            ),
        )
    }
}

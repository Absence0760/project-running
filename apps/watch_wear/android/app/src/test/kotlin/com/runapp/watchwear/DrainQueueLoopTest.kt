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
            classify = { error("unreachable") },
        )
        assertEquals(emptyList<String>(), result.drainedIds)
        assertFalse(result.anyTransientFailure)
        assertNull(result.lastError)
    }

    @Test fun `every-success path drains every id in order`() = runBlocking {
        val removed = mutableListOf<String>()
        val result = drainQueueLoop(
            snapshot = listOf(run("a"), run("b"), run("c")),
            push = PushQueuedRun { /* succeed */ },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { id -> removed += id },
            classify = { error("unreachable") },
        )
        assertEquals(listOf("a", "b", "c"), result.drainedIds)
        assertEquals(listOf("a", "b", "c"), removed)
        assertFalse(result.anyTransientFailure)
        // Successful pass clears the sync-error banner.
        assertNull(result.lastError)
    }

    @Test fun `success clears a previous-run error message`() = runBlocking {
        // [success, success, success] should leave lastError null.
        var pushCalls = 0
        val result = drainQueueLoop(
            snapshot = listOf(run("a"), run("b"), run("c")),
            push = PushQueuedRun {
                pushCalls++
                // No throw — all succeed.
            },
            refresh = RefreshAuthForDrain { true },
            onSuccessfulDrain = OnSuccessfulDrain { },
            classify = { error("no errors thrown") },
        )
        assertEquals(3, pushCalls)
        assertNull(result.lastError)
    }

    // ─────────────────── DropAndContinue (409) ───────────────────

    @Test fun `409 drops the id from the queue and continues`() = runBlocking {
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
            classify = ::classifyDrainError,
        )
        assertEquals(listOf("conflict", "clean"), pushedIds)
        // 409 must STILL remove the id — the row is in the DB.
        assertEquals(listOf("conflict", "clean"), removed)
        assertEquals(listOf("conflict", "clean"), result.drainedIds)
        // 409 is idempotent success, not transient failure.
        assertFalse(result.anyTransientFailure)
        // 409 followed by success clears the error banner.
        assertNull(result.lastError)
    }

    // ─────────────────── SkipAndContinue (4xx) ───────────────────

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
            classify = ::classifyDrainError,
        )
        // 400 is permanent → SKIP, not remove. Only the clean run drains.
        assertEquals(listOf("clean"), result.drainedIds)
        // onSuccessfulDrain must NOT fire for the skipped run.
        assertEquals(listOf("clean"), removed)
        // Permanent failures don't arm backoff — retrying would just re-skip.
        assertFalse(result.anyTransientFailure)
        // Skip-followed-by-success clears the banner.
        assertNull(result.lastError)
    }

    @Test fun `skip persists lastError when no later success clears it`() = runBlocking {
        // [skip-only] → lastError sticks for the UI banner.
        val result = drainQueueLoop(
            snapshot = listOf(run("malformed")),
            push = PushQueuedRun { throw HttpException(400, "bad request") },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { },
            classify = ::classifyDrainError,
        )
        assertEquals(emptyList<String>(), result.drainedIds)
        assertFalse(result.anyTransientFailure)
        // Single permanent-skip run leaves lastError for the UI.
        assertEquals("bad request", result.lastError)
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
            classify = ::classifyDrainError,
        )
        // Loop must stop on 5xx — run 'c' never attempted.
        assertEquals(listOf("a", "server-down"), pushedIds)
        // Only the runs before the break drain.
        assertEquals(listOf("a"), result.drainedIds)
        // 5xx arms backoff so the next drain trigger waits.
        assertTrue(result.anyTransientFailure)
        assertEquals("upstream timeout", result.lastError)
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
        assertNull(result.lastError)
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
            classify = ::classifyDrainError,
        )
        // Push fires once; refresh fails → no retry; 'b' never attempted.
        assertEquals(1, pushAttempts)
        assertEquals(emptyList<String>(), removed)
        assertEquals(emptyList<String>(), result.drainedIds)
        // Refresh failure arms backoff so the next drain trigger waits.
        assertTrue(result.anyTransientFailure)
        assertEquals("JWT expired", result.lastError)
    }

    @Test fun `401 with refresh-throws stops + arms backoff`() = runBlocking {
        // The refresh lambda THROWS rather than returning false — same
        // outcome: stop the loop, arm backoff, surface the error.
        val result = drainQueueLoop(
            snapshot = listOf(run("a")),
            push = PushQueuedRun { throw HttpException(401, "JWT expired") },
            refresh = RefreshAuthForDrain { throw RuntimeException("refresh socket reset") },
            onSuccessfulDrain = OnSuccessfulDrain { },
            classify = ::classifyDrainError,
        )
        assertEquals(emptyList<String>(), result.drainedIds)
        assertTrue(result.anyTransientFailure)
        // Refresh exception message bubbles into lastError.
        assertEquals("refresh socket reset", result.lastError)
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
            classify = ::classifyDrainError,
        )
        assertEquals(listOf("a", "b", "c"), removed)
        // Exactly one refresh fired (only one 401).
        assertEquals(1, refreshCount)
        assertFalse(result.anyTransientFailure)
        assertNull(result.lastError)
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
            classify = ::classifyDrainError,
        )
        // Skipped run stays in the queue; clean ones drain.
        assertEquals(listOf("a", "c"), removed)
        assertEquals(listOf("a", "c"), result.drainedIds)
        assertFalse(result.anyTransientFailure)
        // Trailing success clears the banner even if a middle run was skipped.
        assertNull(result.lastError)
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
            classify = ::classifyDrainError,
        )
        // 'c' is never attempted — loop broke on 'down'.
        assertEquals(listOf("a", "down"), pushedIds)
        assertEquals(listOf("a"), removed)
        assertTrue(result.anyTransientFailure)
        assertEquals("bad gateway", result.lastError)
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
            classify = ::classifyDrainError,
        )
        assertEquals(emptyList<String>(), result.drainedIds)
        // Permanent skips don't count as transient — backoff stays off.
        assertFalse(result.anyTransientFailure)
        assertEquals("validation failed", result.lastError)
    }

    // ─────────────────── Side-effect ordering ───────────────────

    @Test fun `onSuccessfulDrain fires AFTER push succeeds, never before`() = runBlocking {
        val order = mutableListOf<String>()
        drainQueueLoop(
            snapshot = listOf(run("a")),
            push = PushQueuedRun { order += "push" },
            refresh = RefreshAuthForDrain { error("unreachable") },
            onSuccessfulDrain = OnSuccessfulDrain { order += "remove" },
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
            classify = ::classifyDrainError,
        )
        // Removing a run that failed to upload would lose data —
        // bug must not regress.
        assertTrue(removed.isEmpty())
    }
}

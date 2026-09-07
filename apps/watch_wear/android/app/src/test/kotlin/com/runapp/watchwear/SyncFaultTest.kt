package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/// The wrist's sync vocabulary, evaluated rather than read.
///
/// The field this classifies used to carry `e.message ?: e.javaClass.simpleName`
/// straight to a `caption3` on a 1.4-inch display — the one user-facing string
/// on this watch that never went through a catalogue, so a runner in any of the
/// seven locales could be shown `Unable to resolve host "…supabase.co"`
/// (decisions § 1490).
///
/// Two things have to hold for that replacement to be an improvement rather
/// than a loss. The classification must AGREE with the one the drain loop acts
/// on, or the wrist says "will retry" about a run the loop has given up on; and
/// each member must have a sentence of its own, or a vocabulary of six is a
/// vocabulary of three wearing six names.
class SyncFaultTest {

    /// One throwable per branch of `classifyDrainError`, plus the shapes that
    /// have historically been mis-read: a network drop whose message names no
    /// timeout, and an unrecognised throwable that is not an HTTP answer at all.
    private val corpus: List<Pair<String, Throwable>> = listOf(
        "401" to HttpException(401, "JWT expired"),
        "403" to HttpException(403, "forbidden"),
        "400" to HttpException(400, "bad request"),
        "404" to HttpException(404, "no such row"),
        "409" to HttpException(409, "duplicate key"),
        "422" to HttpException(422, "validation failed"),
        "500" to HttpException(500, "internal error"),
        "503" to HttpException(503, "upstream timeout"),
        "dns" to RuntimeException("Unable to resolve host \"x.supabase.co\""),
        "refused" to RuntimeException("Failed to connect to /10.0.0.1:443"),
        "reset" to RuntimeException("Connection reset"),
        "truncated" to RuntimeException("unexpected end of stream"),
        "timeout" to RuntimeException("timeout"),
        "opaque" to IllegalStateException("something nobody has seen"),
        "messageless" to RuntimeException(),
    )

    @Test
    fun `the fault a runner is told never contradicts the action the loop takes`() {
        // A "will retry" sentence over a run the loop has permanently skipped
        // leaves the runner waiting for a retry that will never happen; the
        // reverse tells them to discard a run the next pass would have landed.
        val wrong = corpus.filter { (_, e) ->
            val allowed = when (classifyDrainError(e)) {
                DrainAction.RetryAfterRefresh -> setOf(SyncFault.SignInRequired)
                DrainAction.StopAndRetryLater ->
                    setOf(SyncFault.Offline, SyncFault.ServerBusy)
                DrainAction.SkipAndContinue ->
                    setOf(SyncFault.Refused, SyncFault.Unknown)
            }
            syncFaultFor(e) !in allowed
        }.map { it.first }
        assertEquals("fault disagrees with the drain action", emptyList<String>(), wrong)
    }

    @Test
    fun `every fault the classifier can reach is reachable from this corpus`() {
        // Minus the one the classifier cannot produce: an unreadable queue is
        // raised by the caller, before any throwable exists to classify.
        val reached = corpus.map { syncFaultFor(it.second) }.toSet()
        assertEquals(
            SyncFault.entries.toSet() - SyncFault.QueueUnreadable,
            reached,
        )
    }

    @Test
    fun `a server that answered is separated from one that was never reached`() {
        // Both are permanent to the loop, and they are not the same sentence:
        // "the server refused this run" is a claim about a server, and an
        // unrecognised throwable may mean nothing ever left the watch.
        assertEquals(SyncFault.Refused, syncFaultFor(HttpException(422, "validation failed")))
        assertEquals(SyncFault.Unknown, syncFaultFor(IllegalStateException("?")))
        // Both are transient, and only one is fixed by walking somewhere with
        // signal.
        assertEquals(SyncFault.ServerBusy, syncFaultFor(HttpException(503, "down")))
        assertEquals(SyncFault.Offline, syncFaultFor(RuntimeException("Connection reset")))
    }

    @Test
    fun `a throwable with no message at all still classifies`() {
        // The old field's fallback was `e.javaClass.simpleName`, so a
        // messageless throwable put "RuntimeException" on the runner's wrist.
        assertEquals(SyncFault.Unknown, syncFaultFor(RuntimeException()))
    }

    @Test
    fun `no two faults say the same sentence`() {
        // A member that shares another's string is a distinction the runner
        // cannot see, which makes the classification above unobservable.
        val ids = SyncFault.entries.map { syncFaultMessage(it) }
        assertEquals("a fault shares another's string resource", ids.size, ids.toSet().size)
        for (id in ids) assertNotEquals("an unresolved resource id", 0, id)
    }
}

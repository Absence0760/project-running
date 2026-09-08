package com.runapp.watchwear.ui

import com.runapp.watchwear.SyncFault

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// The PreRun top arc's slot precedence, evaluated rather than read.
///
/// Three files used to assert this by grepping `RunWatchApp.kt` for the order
/// of four `else if` arms — `ScreenWiringTest`, `PreRunRejectedQueueTest`,
/// `PreRunSyncFailureTest`. A source grep can see that one line precedes
/// another; it cannot answer what the arc renders for a given state, which is
/// the thing that matters and the thing a fifth fact would break. So the
/// decision moved into [syncChipState] and this suite runs the WHOLE state
/// space through it — every combination of the six inputs, 96 tuples.
///
/// The blocking fault is swept over three values rather than two, because
/// what stopped a pass is not a boolean: a 5xx the runner retries and a
/// session the server will not renew are the same flag and different chips
/// (decisions § 1544). One representative of the "another attempt could
/// clear it" class stands for the four faults that resolve identically;
/// `every fault that is not the sign-in one relabels the counted chip` sweeps
/// the rest.
///
/// The expectation is written as an ordered list of independent claims rather
/// than as a second `when`, so a reordering of the production branches is not
/// mirrored into the check by the shape of the check.
class SyncChipStateTest {

    private data class Input(
        val queueUnreadable: Boolean,
        val rejectedCount: Int,
        val queuedCount: Int,
        val syncBlockedBy: SyncFault?,
        val online: Boolean,
        val authed: Boolean,
    )

    private fun resolve(i: Input): SyncChipState = syncChipState(
        queueUnreadable = i.queueUnreadable,
        rejectedCount = i.rejectedCount,
        queuedCount = i.queuedCount,
        syncBlockedBy = i.syncBlockedBy,
        online = i.online,
        authed = i.authed,
    )

    /// Every state whose claim holds for this input, most-urgent first. The
    /// arc renders the first; `Silent` is what is left when none of them hold.
    private fun claims(i: Input): List<SyncChipState> = buildList {
        if (i.authed && i.queueUnreadable) add(SyncChipState.Unreadable)
        if (i.authed && i.rejectedCount > 0) add(SyncChipState.Rejected)
        if (i.queuedCount > 0 && i.authed && i.online && i.syncBlockedBy != null) {
            add(
                if (i.syncBlockedBy == SyncFault.SignInRequired) SyncChipState.SignInRequired
                else SyncChipState.RetryQueued
            )
        }
        if (i.queuedCount > 0) add(SyncChipState.Queued)
        if (i.authed && !i.online) add(SyncChipState.Offline)
    }

    private val space: List<Input> = buildList {
        for (unreadable in listOf(false, true)) {
            for (rejected in listOf(0, 2)) {
                for (queued in listOf(0, 3)) {
                    for (blocked in listOf(null, SyncFault.ServerBusy, SyncFault.SignInRequired)) {
                        for (online in listOf(false, true)) {
                            for (authed in listOf(false, true)) {
                                add(Input(unreadable, rejected, queued, blocked, online, authed))
                            }
                        }
                    }
                }
            }
        }
    }

    @Test
    fun `the space is the whole space`() {
        // 2 x 2 x 2 x 3 x 2 x 2. A sweep that shrank silently would make every
        // assertion below weaker without failing any of them.
        assertEquals(96, space.size)
        assertEquals(96, space.toSet().size)
    }

    @Test
    fun `every state in the space resolves to its most urgent standing claim`() {
        val wrong = space.filter { resolve(it) != (claims(it).firstOrNull() ?: SyncChipState.Silent) }
            .map { "$it -> ${resolve(it)}, expected ${claims(it).firstOrNull() ?: SyncChipState.Silent}" }
        assertEquals("slot resolved against the claim order: $wrong", emptyList<String>(), wrong)
    }

    @Test
    fun `every slot is reachable`() {
        // A state nothing can produce is a branch in the composable that has
        // never rendered — and an enum constant nothing produces makes the
        // sweep above pass over ground it never covers.
        val reached = space.map { resolve(it) }.toSet()
        assertEquals(
            "a declared slot the state space cannot produce",
            SyncChipState.entries.toSet(),
            reached,
        )
    }

    @Test
    fun `an unreadable queue outranks everything, including a rejection`() {
        // The count is the thing a rejection states, and the read that would
        // have produced it failed. Naming a figure here is naming a stale one
        // (decisions § 1104).
        assertEquals(
            SyncChipState.Unreadable,
            resolve(Input(true, rejectedCount = 5, queuedCount = 9, syncBlockedBy = SyncFault.ServerBusy, online = true, authed = true)),
        )
    }

    @Test
    fun `a rejection outranks the counted chip`() {
        // `Sync N` reports success on every tap while N never falls, which is
        // the one claim this state makes false (decisions § 1347).
        assertEquals(
            SyncChipState.Rejected,
            resolve(Input(false, rejectedCount = 1, queuedCount = 4, syncBlockedBy = null, online = true, authed = true)),
        )
    }

    @Test
    fun `a transient failure relabels the counted chip rather than taking its slot`() {
        // Sync is still the useful affordance during a transient: a slot that
        // took it would remove the retry in order to describe why the retry is
        // needed (decisions § 1390).
        assertEquals(
            SyncChipState.RetryQueued,
            resolve(Input(false, 0, queuedCount = 2, syncBlockedBy = SyncFault.ServerBusy, online = true, authed = true)),
        )
        assertEquals(
            SyncChipState.Queued,
            resolve(Input(false, 0, queuedCount = 2, syncBlockedBy = null, online = true, authed = true)),
        )
    }

    @Test
    fun `a disabled chip is never the retry one, nor the sign-in one`() {
        // Offline and signed-out both disable the chip, and dimming a control
        // that says "Retry" — or offers a sign-in the network cannot carry —
        // invites a tap that cannot fire. The verdict survives until a pass
        // clears it, so the label comes back on its own.
        for (blocked in listOf(SyncFault.ServerBusy, SyncFault.SignInRequired)) {
            assertEquals(
                "$blocked offline",
                SyncChipState.Queued,
                resolve(Input(false, 0, queuedCount = 2, syncBlockedBy = blocked, online = false, authed = true)),
            )
            assertEquals(
                "$blocked signed out",
                SyncChipState.Queued,
                resolve(Input(false, 0, queuedCount = 2, syncBlockedBy = blocked, online = true, authed = false)),
            )
        }
    }

    @Test
    fun `the one fault a retry cannot clear takes the slot instead of relabelling it`() {
        // `classifyDrainError` reads a 401 as `RetryAfterRefresh`, so a refresh
        // the server refuses ends the pass on `SignInRequired` — and "Retry N"
        // is then a tap that fires, re-runs the same drain, and fails the same
        // refresh every time. The remedy is a sign-in, so the chip becomes one
        // (decisions § 1544).
        assertEquals(
            SyncChipState.SignInRequired,
            resolve(
                Input(false, 0, queuedCount = 2, syncBlockedBy = SyncFault.SignInRequired, online = true, authed = true)
            ),
        )
    }

    @Test
    fun `every other fault relabels the counted chip rather than offering a sign-in`() {
        // Swept over the whole vocabulary rather than over the one member the
        // space samples: a fault added to `SyncFault` lands in the retry class
        // by default, and sending a runner to a sign-in screen over a 5xx is
        // the mirror image of the defect this slot exists to fix.
        val signIn = SyncFault.entries.filter {
            resolve(
                Input(false, 0, queuedCount = 2, syncBlockedBy = it, online = true, authed = true)
            ) == SyncChipState.SignInRequired
        }
        assertEquals(listOf(SyncFault.SignInRequired), signIn)
    }

    @Test
    fun `a signed-out watch is offered nothing it cannot act on`() {
        // `drainQueue` returns before reading anything without a session, so
        // the retry and the discard are both affordances that cannot fire; and
        // "Offline" is the wrong sentence for a runner who has simply never
        // signed in on the wrist — the sign-in chip below is what they need.
        for (i in space.filter { !it.authed }) {
            val expected = if (i.queuedCount > 0) SyncChipState.Queued else SyncChipState.Silent
            assertEquals("$i", expected, resolve(i))
        }
    }

    @Test
    fun `a queue that survived a sign-out is still stated`() {
        // The count is a fact about the file whether or not there is a session
        // to drain it with, and the chip disables itself.
        assertEquals(
            SyncChipState.Queued,
            resolve(Input(false, 0, queuedCount = 1, syncBlockedBy = null, online = false, authed = false)),
        )
    }

    @Test
    fun `the offline caption needs a session, a network fault and an empty queue`() {
        assertEquals(
            SyncChipState.Offline,
            resolve(Input(false, 0, queuedCount = 0, syncBlockedBy = null, online = false, authed = true)),
        )
        // Any one of the three withdrawn and the caption goes.
        assertTrue(
            resolve(Input(false, 0, 0, null, true, true)) != SyncChipState.Offline &&
                resolve(Input(false, 0, 0, null, false, false)) != SyncChipState.Offline &&
                resolve(Input(false, 0, 1, null, false, true)) != SyncChipState.Offline,
        )
    }
}

package com.runapp.watchwear

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// `SupabaseClient.refreshAccessToken` is single-flighted because GoTrue
/// rotates the refresh token: two concurrent refreshes mean the second
/// presents a token the first has already spent, and the watch signs itself
/// out mid-run. Cold start fires two session restores, and a drain-triggered
/// 401 can land on top of either.
class SingleFlightTest {

    @Test fun `concurrent callers run the block once and share the result`() = runBlocking {
        val flight = SingleFlight<String>()
        var calls = 0
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()

        val first = async {
            flight.run {
                calls++
                entered.complete(Unit)
                release.await()
                "token-1"
            }
        }
        entered.await()
        val second = async { flight.run { calls++; "token-2" } }
        // Let the second caller reach the flight and park on the shared slot
        // before the first one finishes and releases it.
        yield()
        release.complete(Unit)

        assertEquals("token-1", first.await())
        assertEquals("token-1", second.await())
        assertEquals(1, calls)
    }

    @Test fun `a joined caller sees the same failure`() = runBlocking {
        val flight = SingleFlight<String>()
        var calls = 0
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()

        val first = async {
            runCatching {
                flight.run {
                    calls++
                    entered.complete(Unit)
                    release.await()
                    throw IllegalStateException("refresh rejected")
                }
            }
        }
        entered.await()
        val second = async { runCatching { flight.run { calls++; "token-2" } } }
        yield()
        release.complete(Unit)

        assertEquals("refresh rejected", first.await().exceptionOrNull()?.message)
        assertEquals("refresh rejected", second.await().exceptionOrNull()?.message)
        assertEquals(1, calls)
    }

    @Test fun `the slot is released so a later call runs again`() = runBlocking {
        val flight = SingleFlight<Int>()
        var calls = 0
        assertEquals(1, flight.run { ++calls })
        assertEquals(2, flight.run { ++calls })
    }

    @Test fun `a failed flight still releases the slot`() = runBlocking {
        val flight = SingleFlight<Int>()
        val failed = runCatching { flight.run { throw IllegalStateException("boom") } }
        assertTrue(failed.isFailure)
        assertEquals(7, flight.run { 7 })
    }
}

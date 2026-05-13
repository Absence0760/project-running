package com.runapp.watchwear.recording

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.ZoneId

/// Mirror suite for `apps/web/src/lib/streaks.test.ts` and
/// `apps/mobile_android/test/streaks_test.dart`. The Strava grace rule
/// is the same on every surface — a regression on the watch surface
/// would silently disagree with the dashboard.
class StreaksTest {

    private val utc = ZoneId.of("UTC")

    /// Local noon (in UTC) for a given Y/M/D, as epoch millis. Noon is
    /// stable against fractional-hour TZ slop in the test fixture.
    private fun localNoonUtcMillis(y: Int, m: Int, d: Int): Long {
        return java.time.ZonedDateTime.of(y, m, d, 12, 0, 0, 0, utc)
            .toInstant()
            .toEpochMilli()
    }

    @Test
    fun `empty input returns zero`() {
        val out = Streaks.compute(
            emptyList(),
            localNoonUtcMillis(2026, 5, 13),
            utc,
        )
        assertEquals(Streaks.Result(current = 0, best = 0), out)
    }

    @Test
    fun `single run today gives current=1 best=1`() {
        val out = Streaks.compute(
            listOf(localNoonUtcMillis(2026, 5, 13)),
            localNoonUtcMillis(2026, 5, 13),
            utc,
        )
        assertEquals(Streaks.Result(current = 1, best = 1), out)
    }

    @Test
    fun `multiple runs same day count once`() {
        val out = Streaks.compute(
            listOf(
                localNoonUtcMillis(2026, 5, 13),
                java.time.ZonedDateTime.of(2026, 5, 13, 7, 0, 0, 0, utc).toInstant().toEpochMilli(),
                java.time.ZonedDateTime.of(2026, 5, 13, 18, 0, 0, 0, utc).toInstant().toEpochMilli(),
            ),
            localNoonUtcMillis(2026, 5, 13),
            utc,
        )
        assertEquals(Streaks.Result(current = 1, best = 1), out)
    }

    @Test
    fun `three day streak ending today`() {
        val out = Streaks.compute(
            listOf(
                localNoonUtcMillis(2026, 5, 11),
                localNoonUtcMillis(2026, 5, 12),
                localNoonUtcMillis(2026, 5, 13),
            ),
            localNoonUtcMillis(2026, 5, 13),
            utc,
        )
        assertEquals(Streaks.Result(current = 3, best = 3), out)
    }

    @Test
    fun `Strava grace - missing today but yesterday present`() {
        val out = Streaks.compute(
            listOf(
                localNoonUtcMillis(2026, 5, 11),
                localNoonUtcMillis(2026, 5, 12),
            ),
            localNoonUtcMillis(2026, 5, 13),
            utc,
        )
        assertEquals(Streaks.Result(current = 2, best = 2), out)
    }

    @Test
    fun `two consecutive days missing breaks the streak`() {
        val out = Streaks.compute(
            listOf(
                localNoonUtcMillis(2026, 5, 9),
                localNoonUtcMillis(2026, 5, 10),
            ),
            localNoonUtcMillis(2026, 5, 13),
            utc,
        )
        assertEquals(Streaks.Result(current = 0, best = 2), out)
    }

    @Test
    fun `best preserves a historical longer run`() {
        val out = Streaks.compute(
            listOf(
                localNoonUtcMillis(2026, 4, 1),
                localNoonUtcMillis(2026, 4, 2),
                localNoonUtcMillis(2026, 4, 3),
                localNoonUtcMillis(2026, 4, 4),
                localNoonUtcMillis(2026, 4, 5),
                localNoonUtcMillis(2026, 5, 12),
                localNoonUtcMillis(2026, 5, 13),
            ),
            localNoonUtcMillis(2026, 5, 13),
            utc,
        )
        assertEquals(Streaks.Result(current = 2, best = 5), out)
    }

    @Test
    fun `future-dated runs are clamped to less than or equal to today`() {
        val out = Streaks.compute(
            listOf(
                localNoonUtcMillis(2026, 5, 13),
                localNoonUtcMillis(2026, 5, 14),
                localNoonUtcMillis(2026, 5, 15),
            ),
            localNoonUtcMillis(2026, 5, 13),
            utc,
        )
        assertEquals(Streaks.Result(current = 1, best = 1), out)
    }

    @Test
    fun `long single streak - current equals best`() {
        val days = 30
        val start = java.time.ZonedDateTime.of(2026, 4, 14, 12, 0, 0, 0, utc)
        val runs = mutableListOf<Long>()
        for (i in 0 until days) {
            runs.add(start.plusDays(i.toLong()).toInstant().toEpochMilli())
        }
        val out = Streaks.compute(runs, localNoonUtcMillis(2026, 5, 13), utc)
        assertEquals(days, out.current)
        assertEquals(days, out.best)
    }

    @Test
    fun `input order does not matter`() {
        val ordered = Streaks.compute(
            listOf(
                localNoonUtcMillis(2026, 5, 11),
                localNoonUtcMillis(2026, 5, 12),
                localNoonUtcMillis(2026, 5, 13),
            ),
            localNoonUtcMillis(2026, 5, 13),
            utc,
        )
        val shuffled = Streaks.compute(
            listOf(
                localNoonUtcMillis(2026, 5, 13),
                localNoonUtcMillis(2026, 5, 11),
                localNoonUtcMillis(2026, 5, 12),
            ),
            localNoonUtcMillis(2026, 5, 13),
            utc,
        )
        assertEquals(ordered, shuffled)
    }

    @Test
    fun `month boundary is consecutive`() {
        val out = Streaks.compute(
            listOf(
                localNoonUtcMillis(2026, 4, 30),
                localNoonUtcMillis(2026, 5, 1),
                localNoonUtcMillis(2026, 5, 13),
            ),
            localNoonUtcMillis(2026, 5, 13),
            utc,
        )
        assertEquals(Streaks.Result(current = 1, best = 2), out)
    }

    @Test
    fun `year boundary is consecutive`() {
        val out = Streaks.compute(
            listOf(
                localNoonUtcMillis(2025, 12, 31),
                localNoonUtcMillis(2026, 1, 1),
            ),
            localNoonUtcMillis(2026, 1, 1),
            utc,
        )
        assertEquals(Streaks.Result(current = 2, best = 2), out)
    }

    @Test
    fun `gap of exactly one day breaks the streak`() {
        val out = Streaks.compute(
            listOf(
                localNoonUtcMillis(2026, 5, 11),
                localNoonUtcMillis(2026, 5, 13),
            ),
            localNoonUtcMillis(2026, 5, 13),
            utc,
        )
        assertEquals(Streaks.Result(current = 1, best = 1), out)
    }
}

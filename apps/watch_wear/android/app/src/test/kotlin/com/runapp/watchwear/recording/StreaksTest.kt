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

    // ─────────── DST safety ───────────

    @Test
    fun `spring-forward day + next day still register as consecutive in US Eastern`() {
        // Mar 8 2026 is US DST spring-forward — clocks jump 02:00 → 03:00
        // in America/New_York, so the local day is 23 hours long. The
        // Streaks helper uses java.time.LocalDate.plusDays() which is
        // DST-safe by construction; this test exercises the boundary
        // in a real DST zone rather than UTC.
        val ny = ZoneId.of("America/New_York")
        val mar8Noon = java.time.ZonedDateTime.of(2026, 3, 8, 12, 0, 0, 0, ny)
            .toInstant().toEpochMilli()
        val mar9Noon = java.time.ZonedDateTime.of(2026, 3, 9, 12, 0, 0, 0, ny)
            .toInstant().toEpochMilli()
        val out = Streaks.compute(listOf(mar8Noon, mar9Noon), mar9Noon, ny)
        assertEquals(Streaks.Result(current = 2, best = 2), out)
    }

    @Test
    fun `fall-back day + next day still register as consecutive in US Eastern`() {
        // Nov 1 2026 is US DST fall-back — 25-hour day. Subtracting
        // 86_400_000 ms from Nov 2 noon would land at 11am Nov 1, but
        // LocalDate.minusDays(1) lands cleanly on Nov 1 regardless.
        val ny = ZoneId.of("America/New_York")
        val nov1Noon = java.time.ZonedDateTime.of(2026, 11, 1, 12, 0, 0, 0, ny)
            .toInstant().toEpochMilli()
        val nov2Noon = java.time.ZonedDateTime.of(2026, 11, 2, 12, 0, 0, 0, ny)
            .toInstant().toEpochMilli()
        val out = Streaks.compute(listOf(nov1Noon, nov2Noon), nov2Noon, ny)
        assertEquals(Streaks.Result(current = 2, best = 2), out)
    }

    @Test
    fun `current streak walks across spring-forward boundary`() {
        // Streak of 5 days straddling the DST boundary (Mar 6-10).
        val ny = ZoneId.of("America/New_York")
        val runs = (6..10).map { day ->
            java.time.ZonedDateTime.of(2026, 3, day, 12, 0, 0, 0, ny)
                .toInstant().toEpochMilli()
        }
        val today = java.time.ZonedDateTime.of(2026, 3, 10, 12, 0, 0, 0, ny)
            .toInstant().toEpochMilli()
        val out = Streaks.compute(runs, today, ny)
        assertEquals(Streaks.Result(current = 5, best = 5), out)
    }
}

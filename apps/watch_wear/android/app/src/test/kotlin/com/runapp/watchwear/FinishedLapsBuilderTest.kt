package com.runapp.watchwear

import com.runapp.watchwear.recording.RecordingRepository
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// Coverage of `buildFinishedLapsList` — turns the recording
/// service's cumulative-mark laps into per-lap split rows for the
/// post-run table.
///
/// History: `docs/backend/metadata.md` notes a Wear OS bug where
/// `start_offset_s` was emitted as cumulative-AFTER instead of
/// cumulative-BEFORE in `buildRunMetadata`. The fix was in the
/// metadata builder, but the FinishedLap shape that builder reads
/// from also needs pinning so a future refactor can't reintroduce
/// the cumulative-vs-split mix-up at this layer either.
///
/// These tests pin:
///   - per-lap SPLIT math (delta from previous mark)
///   - per-lap CUMULATIVE math (absolute from start)
///   - lap numbering (1-indexed from the input Lap.number)
///   - the bonus-row gate (≥1 s AND ≥1 m to include)
///   - empty-laps short-circuit
///   - first-lap split anchors at zero (not negative)
class FinishedLapsBuilderTest {

    private fun lap(number: Int, atMs: Long, distanceM: Double) =
        RecordingRepository.Lap(number = number, atMs = atMs, distanceM = distanceM)

    @Test fun `empty laps returns empty list`() {
        val out = buildFinishedLapsList(
            laps = emptyList(),
            totalDistanceM = 5_000.0,
            totalDurationS = 1_800,
        )
        assertTrue(out.isEmpty())
    }

    @Test fun `single lap with no stop-bonus produces ONE row`() {
        // User pressed lap at exactly the stop point: no partial row.
        val out = buildFinishedLapsList(
            laps = listOf(lap(1, atMs = 600_000L, distanceM = 2_000.0)),
            totalDistanceM = 2_000.0,
            totalDurationS = 600,
        )
        assertEquals(1, out.size)
        val first = out[0]
        assertEquals(1, first.number)
        // First lap split = atMs / 1000 (delta from 0).
        assertEquals(600, first.splitSeconds)
        assertEquals(2_000.0, first.splitDistanceM, 0.0)
        assertEquals(600, first.cumulativeSeconds)
        assertEquals(2_000.0, first.cumulativeDistanceM, 0.0)
    }

    @Test fun `three laps - split math is delta, cumulative math is absolute`() {
        // Critical regression guard: distinguishing split (per-lap
        // delta) from cumulative (absolute since start). Mixing them
        // up was the bug type that hit Wear OS's WatchRunMetadata.
        val out = buildFinishedLapsList(
            laps = listOf(
                lap(1, atMs = 300_000L, distanceM = 1_000.0),
                lap(2, atMs = 620_000L, distanceM = 2_000.0),
                lap(3, atMs = 960_000L, distanceM = 3_000.0),
            ),
            totalDistanceM = 3_000.0,
            totalDurationS = 960,
        )
        assertEquals(3, out.size)

        // Lap 1: split = 300, cumulative = 300
        assertEquals(300, out[0].splitSeconds)
        assertEquals(300, out[0].cumulativeSeconds)
        assertEquals(1_000.0, out[0].splitDistanceM, 0.0)
        assertEquals(1_000.0, out[0].cumulativeDistanceM, 0.0)

        // Lap 2: split = 320 (620-300), cumulative = 620
        assertEquals(320, out[1].splitSeconds)
        assertEquals(620, out[1].cumulativeSeconds)
        assertEquals(1_000.0, out[1].splitDistanceM, 0.0)
        assertEquals(2_000.0, out[1].cumulativeDistanceM, 0.0)

        // Lap 3: split = 340 (960-620), cumulative = 960
        assertEquals(340, out[2].splitSeconds)
        assertEquals(960, out[2].cumulativeSeconds)
        assertEquals(1_000.0, out[2].splitDistanceM, 0.0)
        assertEquals(3_000.0, out[2].cumulativeDistanceM, 0.0)
    }

    @Test fun `lap numbers preserved from input`() {
        // The input Lap.number is 1-indexed by the recording service;
        // the helper passes it through unchanged. Pin so a refactor
        // doesn't accidentally renumber.
        val out = buildFinishedLapsList(
            laps = listOf(
                lap(1, atMs = 300_000L, distanceM = 1_000.0),
                lap(2, atMs = 620_000L, distanceM = 2_000.0),
            ),
            totalDistanceM = 2_000.0,
            totalDurationS = 620,
        )
        assertEquals(listOf(1, 2), out.map { it.number })
    }

    // ───────────── bonus row ─────────────

    @Test fun `bonus row included when stop is gt 1 sec and gt 1 m past last lap`() {
        val out = buildFinishedLapsList(
            laps = listOf(lap(1, atMs = 300_000L, distanceM = 1_000.0)),
            totalDistanceM = 1_250.0,  // 250m past last lap
            totalDurationS = 380,      // 80s past last lap
        )
        assertEquals(2, out.size)
        val bonus = out[1]
        // Bonus row gets next-lap number.
        assertEquals(2, bonus.number)
        assertEquals(80, bonus.splitSeconds)
        assertEquals(250.0, bonus.splitDistanceM, 0.0)
        // Cumulative ends at totalDurationS.
        assertEquals(380, bonus.cumulativeSeconds)
        assertEquals(1_250.0, bonus.cumulativeDistanceM, 0.0)
    }

    @Test fun `bonus row OMITTED when partial is too short (lt 1 sec)`() {
        // User pressed Stop within a second of pressing Lap — no
        // meaningful partial to display.
        val out = buildFinishedLapsList(
            laps = listOf(lap(1, atMs = 300_000L, distanceM = 1_000.0)),
            totalDistanceM = 1_050.0,  // 50m extra
            totalDurationS = 300,      // 0s extra (matches lap mark)
        )
        // 0-second partial must be filtered — no phantom row.
        assertEquals(1, out.size)
    }

    @Test fun `bonus row OMITTED when partial is too short (lt 1 m)`() {
        // User stopped right after the lap mark — no distance to
        // record.
        val out = buildFinishedLapsList(
            laps = listOf(lap(1, atMs = 300_000L, distanceM = 1_000.0)),
            totalDistanceM = 1_000.5,  // 0.5m extra
            totalDurationS = 310,      // 10s extra
        )
        // Sub-1m partial must be filtered — measurement noise, not a meaningful split.
        assertEquals(1, out.size)
    }

    @Test fun `bonus row INCLUDED at exactly 1 sec and 1 m (gate is gte)`() {
        // Boundary: 1s elapsed AND 1m distance. The gate is `>= 1`
        // so this passes. Pin the boundary so a sloppy `> 1` change
        // doesn't drop legitimate partial rows.
        val out = buildFinishedLapsList(
            laps = listOf(lap(1, atMs = 300_000L, distanceM = 1_000.0)),
            totalDistanceM = 1_001.0,
            totalDurationS = 301,
        )
        // Bonus row gate is >= 1 (inclusive), not > 1.
        assertEquals(2, out.size)
    }

    // ───────────── defensive math ─────────────

    @Test fun `out-of-order laps don't produce negative splits (coerceAtLeast guards both)`() {
        // Theoretical: if the recording service ever passed laps in
        // a non-monotonic order (it shouldn't, but defence-in-depth),
        // we coerce both split fields to >= 0. A negative split
        // would otherwise render as "−42 s" on the table.
        val out = buildFinishedLapsList(
            laps = listOf(
                lap(1, atMs = 600_000L, distanceM = 2_000.0),
                // Lap 2 atMs goes BACKWARD — pathological input.
                lap(2, atMs = 500_000L, distanceM = 1_500.0),
            ),
            totalDistanceM = 2_500.0,
            totalDurationS = 700,
        )
        // 2 laps + a bonus row (the bonus check uses lap-2's
        // cumulative figures, not the lap-1 figures, so 500→700 +
        // 1500→2500 satisfies the bonus gate).
        assertTrue("Negative lap-2 split would render as a UI bug.", out[1].splitSeconds >= 0)
        assertTrue(out[1].splitDistanceM >= 0.0)
        assertEquals(0, out[1].splitSeconds)
        assertEquals(0.0, out[1].splitDistanceM, 0.0)
    }

    @Test fun `floor-divide on atMs - sub-second remainders truncated`() {
        // The lap atMs is in milliseconds; cumulativeSeconds /
        // splitSeconds are Int seconds. The math is `(atMs - prevMs) /
        // 1000` (integer division, truncates). 1500ms → 1s, 1999ms →
        // 1s, 2000ms → 2s. Pin so a sloppy refactor to round-half-up
        // doesn't shift every lap timestamp by half a second.
        val out = buildFinishedLapsList(
            laps = listOf(
                lap(1, atMs = 1_999L, distanceM = 100.0),
                lap(2, atMs = 3_500L, distanceM = 200.0),
            ),
            totalDistanceM = 200.0,
            totalDurationS = 4,
        )
        // 1999ms truncates to 1s, not 2.
        assertEquals(1, out[0].splitSeconds)
        // (3500-1999)=1501ms truncates to 1s.
        assertEquals(1, out[1].splitSeconds)
    }
}

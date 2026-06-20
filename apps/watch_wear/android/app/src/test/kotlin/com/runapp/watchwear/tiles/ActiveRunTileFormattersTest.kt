package com.runapp.watchwear.tiles

import com.runapp.watchwear.recording.DistanceUnit
import com.runapp.watchwear.recording.RecordingRepository
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Locale

/// Pure-Kotlin tests for the active-run tile's text formatters. The
/// ProtoLayout layouts themselves can't be unit-tested without a real
/// renderer (or Robolectric + the Tiles dependency), but the strings
/// they show are pure functions and worth pinning — a typo in the
/// pace formatter would surface only when the user adds the tile.
class ActiveRunTileFormattersTest {

    @Test
    fun `formatElapsed shows mm_ss under one hour`() {
        assertEquals("00:00", formatElapsed(0L))
        assertEquals("00:42", formatElapsed(42_000L))
        assertEquals("12:34", formatElapsed((12 * 60 + 34) * 1000L))
        assertEquals("59:59", formatElapsed((59 * 60 + 59) * 1000L))
    }

    @Test
    fun `formatElapsed crosses to h_mm_ss at one hour`() {
        assertEquals("1:00:00", formatElapsed(3_600_000L))
        assertEquals("1:23:45", formatElapsed(((1 * 3600) + (23 * 60) + 45) * 1000L))
        assertEquals("9:59:59", formatElapsed(((9 * 3600) + (59 * 60) + 59) * 1000L))
    }

    @Test
    fun `formatElapsed clamps negatives to zero rather than printing junk`() {
        // A clock skew or a paused-duration math error could in principle
        // hand a negative value to the formatter. Render zero rather
        // than `--:-15` or similar.
        assertEquals("00:00", formatElapsed(-5_000L))
    }

    @Test
    fun `formatPaceSecPerUnit renders min_ss_km`() {
        assertEquals("5:30/km", formatPaceSecPerUnit(330.0, DistanceUnit.KM))
        assertEquals("4:00/km", formatPaceSecPerUnit(240.0, DistanceUnit.KM))
        assertEquals("12:34/km", formatPaceSecPerUnit(754.0, DistanceUnit.KM))
    }

    @Test
    fun `formatPaceSecPerUnit scales the km pace to min_ss_mi`() {
        // A 5:00/km runner covers a (longer) mile in ~8:02. The per-mile
        // pace is the km pace × 1.609344, truncated to whole seconds.
        assertEquals("8:02/mi", formatPaceSecPerUnit(300.0, DistanceUnit.MI))
        // 330 s/km → 531.08 s/mi → truncates to 8:51/mi.
        assertEquals("8:51/mi", formatPaceSecPerUnit(330.0, DistanceUnit.MI))
    }

    @Test
    fun `formatPaceSecPerUnit guards null and non-positive and non-finite`() {
        assertEquals("—:—/km", formatPaceSecPerUnit(null, DistanceUnit.KM))
        assertEquals("—:—/km", formatPaceSecPerUnit(0.0, DistanceUnit.KM))
        assertEquals("—:—/km", formatPaceSecPerUnit(-30.0, DistanceUnit.KM))
        assertEquals("—:—/km", formatPaceSecPerUnit(Double.NaN, DistanceUnit.KM))
        assertEquals("—:—/km", formatPaceSecPerUnit(Double.POSITIVE_INFINITY, DistanceUnit.KM))
        // The guard still emits the runner's unit word for the blank pace.
        assertEquals("—:—/mi", formatPaceSecPerUnit(null, DistanceUnit.MI))
    }

    @Test
    fun `formatStatRow uses two decimals under 10 km and one decimal beyond`() {
        // Why: at 5 km a runner cares about the difference between 5.12
        // and 5.18 (a tenth of a km is a sprint or a recovery jog). At
        // 21 km a runner cares about "21" vs "21.5", not "21.07" vs
        // "21.13" — the second decimal is noise on a small screen.
        val under = makeMetrics(distanceM = 5_120.0, paceSecPerKm = 330.0)
        assertEquals("5.12 km · 5:30/km", formatStatRow(under, Locale.US))

        val over = makeMetrics(distanceM = 21_100.0, paceSecPerKm = 320.0)
        assertEquals("21.1 km · 5:20/km", formatStatRow(over, Locale.US))
    }

    @Test
    fun `formatStatRow renders distance and pace in miles when the unit is mi`() {
        // 5120 m = 3.18 mi (under the 10-unit decimal cutoff → 2 decimals);
        // 330 s/km → ~8:51/mi.
        val under = makeMetrics(distanceM = 5_120.0, paceSecPerKm = 330.0, unit = DistanceUnit.MI)
        assertEquals("3.18 mi · 8:51/mi", formatStatRow(under, Locale.US))

        // 21100 m = 13.11 mi → over the 10-unit cutoff → 1 decimal "13.1";
        // 320 s/km → ~8:34/mi.
        val over = makeMetrics(distanceM = 21_100.0, paceSecPerKm = 320.0, unit = DistanceUnit.MI)
        assertEquals("13.1 mi · 8:34/mi", formatStatRow(over, Locale.US))
    }

    @Test
    fun `formatStatRow handles a fresh start with zero distance and no pace`() {
        val fresh = makeMetrics(distanceM = 0.0, paceSecPerKm = null)
        assertEquals("0.00 km · —:—/km", formatStatRow(fresh, Locale.US))
    }

    @Test
    fun `formatStatRow honours the locale decimal separator`() {
        // German uses a comma decimal separator — the distance figure must
        // follow the device locale ("5,12 km") even though the unit word
        // and the pace digits don't change.
        val under = makeMetrics(distanceM = 5_120.0, paceSecPerKm = 330.0)
        assertEquals("5,12 km · 5:30/km", formatStatRow(under, Locale.GERMANY))
    }

    private fun makeMetrics(
        distanceM: Double,
        paceSecPerKm: Double?,
        unit: DistanceUnit = DistanceUnit.KM,
    ) = RecordingRepository.Metrics(
        stage = RecordingRepository.Stage.Recording,
        distanceM = distanceM,
        paceSecPerKm = paceSecPerKm,
        preferredUnit = unit,
    )
}

package com.runapp.watchwear.tiles

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
    fun `formatPaceSecPerKm renders min_ss_km`() {
        assertEquals("5:30/km", formatPaceSecPerKm(330.0))
        assertEquals("4:00/km", formatPaceSecPerKm(240.0))
        assertEquals("12:34/km", formatPaceSecPerKm(754.0))
    }

    @Test
    fun `formatPaceSecPerKm guards null and non-positive and non-finite`() {
        assertEquals("—:—/km", formatPaceSecPerKm(null))
        assertEquals("—:—/km", formatPaceSecPerKm(0.0))
        assertEquals("—:—/km", formatPaceSecPerKm(-30.0))
        assertEquals("—:—/km", formatPaceSecPerKm(Double.NaN))
        assertEquals("—:—/km", formatPaceSecPerKm(Double.POSITIVE_INFINITY))
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
    ) = RecordingRepository.Metrics(
        stage = RecordingRepository.Stage.Recording,
        distanceM = distanceM,
        paceSecPerKm = paceSecPerKm,
    )
}

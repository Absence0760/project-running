package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// Unit tests for the BPM validity gate hoisted out of
/// `HeartRateMonitor.onDataReceived`.
///
/// The gate is the only thing protecting `RunViewModel`'s rolling HR
/// average from sensor noise — a real Health Services sample stream
/// briefly emits absurd values during wrist motion / wrist-off lag /
/// startup acquire. A regression that tightened the range (e.g. to
/// the typical-runner 60..180 window) would silently drop a
/// recovering-athlete's resting floor and a sprint-finish ceiling
/// from `avg_bpm`; a regression that loosened it would let single-
/// frame 500-bpm spikes inflate every saved run's average.
///
/// Pinned at the inclusive bounds 30 and 230 (per the original
/// comment that lived inline in onDataReceived).
class HeartRateMonitorTest {

    @Test
    fun `constants document the inclusive bounds`() {
        // A regression in the constants alone (no usage change)
        // would mis-document the gate without breaking it
        // immediately, but the next time someone copy-edited the
        // comment they'd derive the wrong range. Pin both.
        assertEquals(30, HeartRateMonitor.MIN_VALID_BPM)
        assertEquals(230, HeartRateMonitor.MAX_VALID_BPM)
    }

    @Test
    fun `typical resting and active rates pass`() {
        // Resting ~60, easy run ~140, hard interval ~180 — all
        // should land in the rolling average. A regression to a
        // tighter range would surface here as one of these
        // commonly-observed values failing.
        for (bpm in listOf(45.0, 60.0, 80.0, 120.0, 140.0, 160.0, 180.0, 200.0)) {
            assertTrue("$bpm should be valid", HeartRateMonitor.isValidBpm(bpm))
        }
    }

    @Test
    fun `inclusive lower bound at 30 passes`() {
        // 30 itself is the lower bound — INCLUSIVE per the gate's
        // `>= MIN_VALID_BPM` form. A regression to `>` would drop
        // the bound value itself.
        assertTrue(HeartRateMonitor.isValidBpm(30.0))
    }

    @Test
    fun `just below the lower bound fails`() {
        // 29.9 is sensor floor noise (wrist-off acquiring). Reject.
        assertFalse(HeartRateMonitor.isValidBpm(29.9))
        assertFalse(HeartRateMonitor.isValidBpm(29.0))
    }

    @Test
    fun `inclusive upper bound at 230 passes`() {
        // 230 is the anaerobic ceiling — INCLUSIVE so an extreme-
        // effort sprint finish that legitimately hits 230 lands in
        // the rolling average rather than getting dropped.
        assertTrue(HeartRateMonitor.isValidBpm(230.0))
    }

    @Test
    fun `just above the upper bound fails`() {
        // 230.1 is sensor wrist-motion noise. Reject.
        assertFalse(HeartRateMonitor.isValidBpm(230.1))
        assertFalse(HeartRateMonitor.isValidBpm(250.0))
        assertFalse(HeartRateMonitor.isValidBpm(500.0))
    }

    @Test
    fun `zero is rejected (wrist-off lag)`() {
        // Health Services can briefly emit 0 during the moment
        // between "sensor available" and the first real sample.
        // Rejecting 0 keeps that startup garbage out of avg_bpm.
        assertFalse(HeartRateMonitor.isValidBpm(0.0))
    }

    @Test
    fun `negative values are rejected`() {
        // A raw sensor frame can occasionally produce a small
        // negative value (the sample is a Float internally; a
        // delta-from-baseline interpretation can briefly underflow).
        // Reject defensively.
        assertFalse(HeartRateMonitor.isValidBpm(-1.0))
        assertFalse(HeartRateMonitor.isValidBpm(-100.0))
    }

    @Test
    fun `non-finite doubles are rejected`() {
        // The Health Services API returns Float on the wire, which
        // can be NaN / Infinity if a sample's calculation went
        // wrong. NaN comparisons return false in Kotlin, so the
        // `bpm >= 30 && bpm <= 230` form drops NaN automatically.
        // Pin this defensively — a regression that switched to
        // `!(bpm < 30 || bpm > 230)` (logically equivalent for
        // real numbers but NOT for NaN) would let NaN through:
        // `!(NaN < 30 || NaN > 230)` = `!(false || false)` = true.
        assertFalse(HeartRateMonitor.isValidBpm(Double.NaN))
        assertFalse(HeartRateMonitor.isValidBpm(Double.POSITIVE_INFINITY))
        assertFalse(HeartRateMonitor.isValidBpm(Double.NEGATIVE_INFINITY))
    }

    // ─────────── bpmFromSampleValue (Health Services value coercion) ───────────

    @Test
    fun `bpmFromSampleValue returns null on null input`() {
        // The SDK's `.value` accessor can return null on a
        // degenerate frame. Pin the null short-circuit so the
        // callback can `?: continue` without an NPE.
        assertEquals(null, HeartRateMonitor.bpmFromSampleValue(null))
    }

    @Test
    fun `bpmFromSampleValue parses Double sample`() {
        // Most Health Services emitters use Double on the wire.
        assertEquals(142, HeartRateMonitor.bpmFromSampleValue(142.0))
        assertEquals(60, HeartRateMonitor.bpmFromSampleValue(60.0))
    }

    @Test
    fun `bpmFromSampleValue parses Float sample`() {
        // Some SDK versions use Float — the same `.toString().toDoubleOrNull()`
        // cascade handles both.
        assertEquals(142, HeartRateMonitor.bpmFromSampleValue(142.0f))
    }

    @Test
    fun `bpmFromSampleValue parses Int sample (whole-number HR)`() {
        // A few emitters round to Int before delivery. Confirm
        // the parser handles that shape too.
        assertEquals(142, HeartRateMonitor.bpmFromSampleValue(142))
    }

    @Test
    fun `bpmFromSampleValue parses String sample`() {
        // Defence-in-depth: if a future SDK shape stringifies
        // before delivery, the parser still produces an Int.
        assertEquals(142, HeartRateMonitor.bpmFromSampleValue("142"))
        assertEquals(142, HeartRateMonitor.bpmFromSampleValue("142.0"))
    }

    @Test
    fun `bpmFromSampleValue truncates fractional readings`() {
        // 142.7 → 142, not 143. The watch's avg_bpm averaging
        // works in integer space (the Int conversion is canonical
        // before averaging starts).
        assertEquals(142, HeartRateMonitor.bpmFromSampleValue(142.7))
    }

    @Test
    fun `bpmFromSampleValue rejects out-of-range values`() {
        // The validity gate (30..230) applies before the Int
        // conversion. A 500-bpm spike returns null, not 500.
        assertEquals(null, HeartRateMonitor.bpmFromSampleValue(500.0))
        assertEquals(null, HeartRateMonitor.bpmFromSampleValue(20.0))
        assertEquals(null, HeartRateMonitor.bpmFromSampleValue(0.0))
    }

    @Test
    fun `bpmFromSampleValue rejects non-numeric Strings`() {
        // A "0xff" or "n/a" can't parse to Double — null out.
        assertEquals(null, HeartRateMonitor.bpmFromSampleValue("n/a"))
        assertEquals(null, HeartRateMonitor.bpmFromSampleValue("nope"))
        assertEquals(null, HeartRateMonitor.bpmFromSampleValue(""))
    }

    @Test
    fun `bpmFromSampleValue rejects NaN`() {
        // Same NaN-trap as isValidBpm — explicitly pin it survives
        // the parse + clamp cascade.
        assertEquals(null, HeartRateMonitor.bpmFromSampleValue(Double.NaN))
    }
}

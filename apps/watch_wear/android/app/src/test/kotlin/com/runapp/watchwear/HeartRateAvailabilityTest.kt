package com.runapp.watchwear

import androidx.health.services.client.data.DataTypeAvailability
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/// A null bpm is four different situations and the running screen used to
/// render all four as the same blank space (decisions § 1052). These pin
/// the two pure halves of telling them apart: what Health Services'
/// sensor state means, and what the screen says about it.
class HeartRateAvailabilityTest {

    // ───────────── sensor state → recorder state ─────────────

    @Test
    fun `a reporting sensor is available`() {
        assertEquals(
            HeartRateAvailability.Available,
            HeartRateMonitor.availabilityOf(DataTypeAvailability.AVAILABLE),
        )
    }

    @Test
    fun `acquiring and unknown both read as acquiring`() {
        // UNKNOWN is what the sensor reports before it has decided.
        // Grading it as a failure tells a runner there will be no heart
        // rate a second before the first sample lands.
        assertEquals(
            HeartRateAvailability.Acquiring,
            HeartRateMonitor.availabilityOf(DataTypeAvailability.ACQUIRING),
        )
        assertEquals(
            HeartRateAvailability.Acquiring,
            HeartRateMonitor.availabilityOf(DataTypeAvailability.UNKNOWN),
        )
    }

    @Test
    fun `off-body is not folded into unavailable`() {
        // The whole reason the two are separate: pushing the watch back
        // up the wrist is the one thing a runner can do about a missing
        // heart rate mid-run. Fold them and the caption loses its only
        // useful instruction.
        val offBody =
            HeartRateMonitor.availabilityOf(DataTypeAvailability.UNAVAILABLE_DEVICE_OFF_BODY)
        assertEquals(HeartRateAvailability.OffWrist, offBody)
        assertNotEquals(
            HeartRateAvailability.Unavailable,
            offBody,
        )
    }

    @Test
    fun `an unavailable sensor is unavailable`() {
        assertEquals(
            HeartRateAvailability.Unavailable,
            HeartRateMonitor.availabilityOf(DataTypeAvailability.UNAVAILABLE),
        )
    }

    @Test
    fun `every value the SDK ships maps to something`() {
        // `DataTypeAvailability.VALUES` is the SDK's own list. A version
        // that adds a sixth state must not silently reach the `else`
        // without anyone deciding what it means — this fails when the
        // list grows past the five the mapping was written against.
        assertEquals(
            "DataTypeAvailability gained a value; decide what it means " +
                "in HeartRateMonitor.availabilityOf before widening this",
            5,
            DataTypeAvailability.VALUES.size,
        )
        for (v in DataTypeAvailability.VALUES) {
            // No assertion beyond "it returns" — the point is that the
            // when is total over the SDK's own set.
            HeartRateMonitor.availabilityOf(v)
        }
    }

    // ───────────── recorder state → what the screen says ─────────────

    @Test
    fun `a build with heart rate off says nothing`() {
        // ENABLE_HR is a build-time flag. A build that deliberately has
        // no heart rate must not caption every run with its absence.
        assertEquals(
            HeartRateCaptionKind.None,
            heartRateCaption(HeartRateAvailability.Off, null),
        )
        assertEquals(
            HeartRateCaptionKind.None,
            heartRateCaption(HeartRateAvailability.Off, 146),
        )
    }

    @Test
    fun `available with a sample renders the reading`() {
        assertEquals(
            HeartRateCaptionKind.Reading,
            heartRateCaption(HeartRateAvailability.Available, 146),
        )
    }

    @Test
    fun `available with no sample yet is acquiring, not blank`() {
        // Between registration and the first sample the sensor is
        // working. The runner is owed the difference between "wait" and
        // "there will be none".
        assertEquals(
            HeartRateCaptionKind.Acquiring,
            heartRateCaption(HeartRateAvailability.Available, null),
        )
    }

    @Test
    fun `the state wins over a stale reading`() {
        // Nothing ever cleared `bpm` once it had been set, so a watch
        // that went off the wrist at minute three kept rendering that
        // figure for the rest of a twelve-hour run. The service clears
        // it now; this is the guard that the caption would be right even
        // if it did not.
        assertEquals(
            HeartRateCaptionKind.OffWrist,
            heartRateCaption(HeartRateAvailability.OffWrist, 146),
        )
        assertEquals(
            HeartRateCaptionKind.Unavailable,
            heartRateCaption(HeartRateAvailability.Unavailable, 146),
        )
        assertEquals(
            HeartRateCaptionKind.Acquiring,
            heartRateCaption(HeartRateAvailability.Acquiring, 146),
        )
    }

    @Test
    fun `every availability produces a caption decision`() {
        // A sixth availability added without a caption would compile
        // (the `when` is exhaustive, so it would not) — but a sixth
        // CAPTION kind that no availability reaches is dead copy in
        // seven catalogues. Both directions are covered: every
        // availability maps, and every kind except None is reachable.
        val reached = HeartRateAvailability.entries
            .flatMap { listOf(heartRateCaption(it, null), heartRateCaption(it, 146)) }
            .toSet()
        assertEquals(HeartRateCaptionKind.entries.toSet(), reached)
    }
}

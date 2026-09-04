package com.runapp.watchwear.recording

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// `avg_bpm` used to be saved as the run's average heart rate with no record of
/// how much of the run produced it (decisions § 1083). These pin what the
/// finished run may now claim.
class HeartRateCoverageTest {

    @Test
    fun `full coverage keeps the mean`() {
        val claim = heartRateClaim(bpmSum = 1500, bpmCount = 10, hrAvailableMs = 600_000, activeElapsedMs = 600_000)
        assertEquals(150.0, claim.avgBpm!!, 0.0001)
        assertEquals(1.0, claim.coverage!!, 0.0001)
    }

    @Test
    fun `a mean over a minority of the run is not the run's average`() {
        // The case the entry exists for: twenty minutes of a twelve-hour ultra.
        val claim = heartRateClaim(
            bpmSum = 1500,
            bpmCount = 10,
            hrAvailableMs = 20 * 60_000L,
            activeElapsedMs = 12 * 3_600_000L,
        )
        assertNull("a 3 % sample must not be saved as the run's average", claim.avgBpm)
        assertEquals(0.03, claim.coverage!!, 0.0001)
    }

    @Test
    fun `the threshold is exactly half and is inclusive`() {
        val at = heartRateClaim(bpmSum = 300, bpmCount = 2, hrAvailableMs = 500, activeElapsedMs = 1_000)
        assertEquals(150.0, at.avgBpm!!, 0.0001)
        val below = heartRateClaim(bpmSum = 300, bpmCount = 2, hrAvailableMs = 494, activeElapsedMs = 1_000)
        assertNull(below.avgBpm)
        assertEquals(0.49, below.coverage!!, 0.0001)
    }

    @Test
    fun `the stored figure and the decision cannot contradict each other`() {
        // Graded on the rounded value, so a run never persists a coverage that
        // reads as at-threshold beside an average the grading suppressed.
        val claim = heartRateClaim(bpmSum = 300, bpmCount = 2, hrAvailableMs = 4_999, activeElapsedMs = 10_000)
        assertEquals(0.5, claim.coverage!!, 0.0001)
        assertEquals(
            "a stored coverage of 0.50 beside a suppressed average is a record that contradicts itself",
            150.0,
            claim.avgBpm!!,
            0.0001,
        )
    }

    @Test
    fun `an unmeasured coverage claims nothing and keeps the average`() {
        // A checkpoint written by a build predating the field. Absence of a
        // measurement is no evidence of absent coverage — grading it as zero
        // would silently drop an average that build would have saved.
        val claim = heartRateClaim(bpmSum = 1500, bpmCount = 10, hrAvailableMs = null, activeElapsedMs = 600_000)
        assertEquals(150.0, claim.avgBpm!!, 0.0001)
        assertNull(claim.coverage)
    }

    @Test
    fun `a run with no elapsed time is not divided by zero`() {
        val claim = heartRateClaim(bpmSum = 150, bpmCount = 1, hrAvailableMs = 0, activeElapsedMs = 0)
        assertEquals(150.0, claim.avgBpm!!, 0.0001)
        assertNull(claim.coverage)
    }

    @Test
    fun `no samples means no average, and the coverage still reports`() {
        // Heart rate was on and delivered nothing — a permission refusal, a
        // watch with no optical sensor. `hr_coverage: 0` with no `avg_bpm` is
        // the honest record of that, and is distinct from heart rate being off.
        val claim = heartRateClaim(bpmSum = 0, bpmCount = 0, hrAvailableMs = 0, activeElapsedMs = 600_000)
        assertNull(claim.avgBpm)
        assertEquals(0.0, claim.coverage!!, 0.0001)
    }

    @Test
    fun `coverage cannot exceed the run`() {
        // The accumulator advances on the ticker against active elapsed, so it
        // cannot outrun the clock — but a clamp is cheaper than a run that
        // reports 140 % sensor coverage if one ever does.
        val claim = heartRateClaim(bpmSum = 150, bpmCount = 1, hrAvailableMs = 900_000, activeElapsedMs = 600_000)
        assertEquals(1.0, claim.coverage!!, 0.0001)
    }

    private val serviceSrc: String by lazy {
        File("src/main/kotlin/com/runapp/watchwear/recording/RunRecordingService.kt").readText()
    }

    @Test
    fun `coverage is advanced on the ticker, not by closing an interval on an event`() {
        // The gap being measured is a stream that has gone QUIET. Health
        // Services need not report `UNAVAILABLE` when the platform stops
        // feeding a foreground-only client, so there is no emission to close an
        // interval on and an open one credits the whole silence as covered.
        assertTrue(
            "advanceHrCoverage must be called from the recording ticker",
            Regex(
                """delay\(500\).{0,200}?advanceHrCoverage\(""",
                RegexOption.DOT_MATCHES_ALL,
            ).containsMatchIn(serviceSrc),
        )
        assertTrue(
            "advanceHrCoverage must gate on the AGE of the last sample",
            Regex(
                """elapsedRealtime\(\)\s*-\s*lastHrSampleAtMs\s*<=\s*HR_SAMPLE_FRESH_MS""",
            ).containsMatchIn(serviceSrc),
        )
    }

    /// The body of a named function, up to the next declaration at the same
    /// indent. Enough to ask what one function does without parsing Kotlin.
    private fun bodyOf(src: String, signature: String): String {
        val start = src.indexOf(signature)
        assertTrue("`$signature` not found — this guard is reading nothing", start >= 0)
        val rest = src.substring(start)
        val end = Regex("""\n    (?:private |internal |public )?fun """).find(rest, 1)?.range?.first
        return if (end == null) rest else rest.substring(0, end)
    }

    @Test
    fun `the finished run is graded once, where the average is born`() {
        // Both producers of a SAVED `avg_bpm` — the normal stop and the crash
        // recovery — go through the same grader, or a recovered run keeps a
        // claim the stop path would have refused. The rolling mean inside the
        // HR collect is deliberately out of scope: that is the live figure on
        // the running screen, and `stopRecording` overwrites it.
        val stop = bodyOf(serviceSrc, "private fun stopRecording()")
        val vm = File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()
        val recover = bodyOf(vm, "fun recoverCheckpoint()")
        for ((name, body) in listOf("stopRecording" to stop, "recoverCheckpoint" to recover)) {
            assertTrue("$name must grade through heartRateClaim", body.contains("heartRateClaim("))
            assertEquals(
                "an `avg_bpm` divided out of the rolling pair inside $name is a claim " +
                    "nothing measured — hand the pair to heartRateClaim instead",
                0,
                Regex("""bpmSum\.toDouble\(\)""").findAll(body).count(),
            )
        }
        assertTrue(
            "stopRecording must publish the GRADED pair — the live rolling mean is " +
                "still on Metrics.avgBpm until this overwrites it",
            Regex("""avgBpm = hr\.avgBpm,\s*\n\s*hrCoverage = hr\.coverage,""")
                .containsMatchIn(stop),
        )
    }
}

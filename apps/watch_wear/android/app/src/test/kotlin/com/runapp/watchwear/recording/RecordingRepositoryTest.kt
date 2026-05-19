package com.runapp.watchwear.recording

import com.runapp.watchwear.GpsPoint
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/// Unit tests for `RecordingRepository` — the process-wide singleton
/// that decouples the recording loop's state from the UI lifecycle.
///
/// `RunRecordingService` writes; `RunViewModel` reads. The decoupling
/// is the load-bearing invariant — a run survives the activity being
/// destroyed (ambient, screen-off, low memory) because the state
/// lives in this singleton, not in any ViewModel scope.
///
/// `Metrics.isActive` is the gate that controls UI rendering: the
/// Running screen mounts when isActive is true, the PreRun screen
/// when it's false. A regression in that contract would either
/// surface the recording UI mid-Idle (confusing — no run is going)
/// or hide it mid-Recording (catastrophic — runner can't see their
/// pace).
class RecordingRepositoryTest {

    // The singleton survives across tests — reset before AND after so
    // a test that errors mid-update doesn't bleed state into the next.
    @Before fun setUp() = RecordingRepository.reset()

    @After fun tearDown() = RecordingRepository.reset()

    // ───────────────────── Metrics.isActive ─────────────────────

    @Test
    fun `isActive is true for Recording stage`() {
        val m = RecordingRepository.Metrics(stage = RecordingRepository.Stage.Recording)
        assertTrue(m.isActive)
    }

    @Test
    fun `isActive is true for Paused stage (run continues during pause)`() {
        // A paused run is still "active" from the UI's perspective —
        // the Running screen stays mounted, the runner sees the
        // pause/resume control. A regression that made Paused
        // inactive would surface as the UI dropping back to PreRun
        // mid-run on any pause tap.
        val m = RecordingRepository.Metrics(stage = RecordingRepository.Stage.Paused)
        assertTrue(m.isActive)
    }

    @Test
    fun `isActive is false for Idle stage`() {
        val m = RecordingRepository.Metrics(stage = RecordingRepository.Stage.Idle)
        assertFalse(m.isActive)
    }

    @Test
    fun `isActive is false for Finished stage`() {
        // Finished is the post-run summary state — PostRun screen,
        // not Running. The UI must NOT treat it as active.
        val m = RecordingRepository.Metrics(stage = RecordingRepository.Stage.Finished)
        assertFalse(m.isActive)
    }

    // ──────────────────────── default state ────────────────────

    @Test
    fun `default Metrics is Idle with no run id and zero counters`() {
        // The reset state must be unambiguously "no run in progress"
        // — the PreRun screen reads this and a regression that
        // shipped a non-Idle default would flash the Running UI on
        // every cold launch.
        val m = RecordingRepository.Metrics()
        assertEquals(RecordingRepository.Stage.Idle, m.stage)
        assertNull(m.runId)
        assertEquals(0L, m.startedAtMs)
        assertEquals(0L, m.elapsedMs)
        assertEquals(0.0, m.distanceM, 0.0)
        assertNull(m.paceSecPerKm)
        assertNull(m.bpm)
        assertNull(m.avgBpm)
        assertEquals(0, m.trackPointCount)
        assertNull(m.latestPoint)
        assertNull(m.trackFilePath)
        assertEquals("run", m.activityType)
        assertTrue(m.laps.isEmpty())
        assertNull(m.offRouteDistanceM)
        assertNull(m.routeRemainingM)
        assertTrue(m.routeWaypoints.isEmpty())
        assertTrue(m.trackOverlayPoints.isEmpty())
        assertNull(m.steps)
    }

    @Test
    fun `default locationAvailable is true (recording starts assuming GPS works)`() {
        // The negative ("GPS lost") banner only shows after the
        // recording loop downgrades this. Default-true means a
        // fresh recording flashes "GPS lost" only if it actually
        // loses GPS; default-false would flash it on every start
        // before the first fix lands.
        assertTrue(RecordingRepository.Metrics().locationAvailable)
    }

    // ───────────────────── update + reset ──────────────────────

    @Test
    fun `update applies the transform to the current state`() {
        // The service writes through update(); the contract is that
        // the transform receives the CURRENT state and the result
        // replaces it. A regression that passed Metrics() instead
        // of _metrics.value would silently reset on every write —
        // every GPS sample would wipe the distance + run-id.
        RecordingRepository.update { it.copy(distanceM = 100.0, runId = "test-run") }
        val after1 = RecordingRepository.metrics.value
        assertEquals(100.0, after1.distanceM, 0.0)
        assertEquals("test-run", after1.runId)

        // Second update sees the first's output, not Metrics().
        RecordingRepository.update { it.copy(distanceM = it.distanceM + 50.0) }
        val after2 = RecordingRepository.metrics.value
        assertEquals(150.0, after2.distanceM, 0.0)
        assertEquals("runId must persist across updates", "test-run", after2.runId)
    }

    @Test
    fun `reset clears every field back to the default`() {
        // The post-stop / cancel path calls reset() to clear the
        // singleton. A regression that left fields stale would
        // surface as the next run inheriting the previous run's
        // distance / runId / latestPoint.
        RecordingRepository.update {
            it.copy(
                stage = RecordingRepository.Stage.Recording,
                runId = "previous-run",
                distanceM = 5000.0,
                latestPoint = GpsPoint(lat = 51.5, lng = -0.1, ele = null, epochMs = 1L),
                trackPointCount = 100,
                laps = listOf(RecordingRepository.Lap(1, 1L, 1000.0)),
            )
        }
        // Sanity — state actually updated.
        assertNotEquals(RecordingRepository.Stage.Idle, RecordingRepository.metrics.value.stage)

        RecordingRepository.reset()
        val after = RecordingRepository.metrics.value
        assertEquals(RecordingRepository.Stage.Idle, after.stage)
        assertNull(after.runId)
        assertEquals(0.0, after.distanceM, 0.0)
        assertNull(after.latestPoint)
        assertEquals(0, after.trackPointCount)
        assertTrue(after.laps.isEmpty())
    }

    @Test
    fun `metrics StateFlow exposes the latest value to observers`() {
        // ViewModel collects from the StateFlow. The flow's `.value`
        // accessor must reflect the most recent update — a
        // regression to a non-conflating Flow would buffer updates
        // and ship stale data to the UI mid-run.
        RecordingRepository.update { it.copy(distanceM = 42.0) }
        assertEquals(42.0, RecordingRepository.metrics.value.distanceM, 0.0)
    }

    // ──────────────────────── Stage enum ───────────────────────

    @Test
    fun `Stage declares exactly the four lifecycle values`() {
        // Adding a new Stage (e.g. "Recovering" for crash-recovery)
        // would require updating isActive to decide whether it
        // counts. Pin the value set so a future addition forces a
        // deliberate review of the isActive contract.
        assertEquals(4, RecordingRepository.Stage.values().size)
        assertEquals(
            setOf("Idle", "Recording", "Paused", "Finished"),
            RecordingRepository.Stage.values().map { it.name }.toSet(),
        )
    }
}

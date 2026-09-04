import XCTest
import CoreLocation
@testable import WatchApp

/// What the app owes the runner when the `HKWorkoutSession` dies mid-run.
///
/// `didFailWithError` used to be empty and nothing nilled the session, so the
/// last reading stayed on the run screen as a plausible live heart rate for
/// the rest of the run, and the average of however many minutes the sensor
/// managed was stamped on the finished run as if it had covered all of it.
/// The failure is driven through `handleSessionFailure()` because a real
/// `HKWorkoutSession` cannot be constructed — or made to fail — in the test
/// host; the delegate method is a one-line call into it.
final class HealthKitFailureTests: XCTestCase {

    /// Run the one main-queue hop `handleSessionFailure` / `reset` post. The
    /// queue is FIFO, so this block cannot run before theirs.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    private func loc(_ lat: Double) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: -0.1),
            altitude: 10,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date()
        )
    }

    private func feed(_ wm: WorkoutManager, _ locations: [CLLocation]) {
        wm.locationManager(CLLocationManager(), didUpdateLocations: locations)
    }

    // MARK: - The live reading

    func testFailureClearsTheFrozenReadingAndSaysSo() {
        let hk = HealthKitManager()
        hk.currentBPM = 142
        hk.averageBPM = 138

        hk.handleSessionFailure()
        drainMainQueue()

        XCTAssertNil(hk.currentBPM, "a frozen plausible number is worse than no number")
        XCTAssertNil(hk.averageBPM)
        XCTAssertTrue(hk.heartRateUnavailable)
    }

    func testSampleAfterFailureIsRefused() {
        let hk = HealthKitManager()
        hk.handleSessionFailure()
        XCTAssertTrue(hk.sessionDidFail,
                      "the collect callback gates on this, so a late sample cannot put a number back on screen")
    }

    // MARK: - The stamped average

    func testSummaryAverageIsWithheldWithoutWaitingForTheMainQueue() {
        let hk = HealthKitManager()
        hk.averageBPM = 138

        hk.handleSessionFailure()

        // Deliberately no drain: HealthKit calls back on its own queue while
        // stop() reads the summary synchronously, so a guard that only takes
        // effect after the hop can land after the run has been stamped.
        XCTAssertNil(hk.summaryAverageBPM)
    }

    func testHealthySessionStillReportsItsAverage() {
        let hk = HealthKitManager()
        hk.averageBPM = 138
        XCTAssertEqual(hk.summaryAverageBPM, 138)
        XCTAssertFalse(hk.heartRateUnavailable)
    }

    func testResetClearsTheFailureForTheNextRun() {
        let hk = HealthKitManager()
        hk.averageBPM = 138
        hk.handleSessionFailure()
        drainMainQueue()

        hk.reset()
        drainMainQueue()

        XCTAssertFalse(hk.sessionDidFail)
        XCTAssertFalse(hk.heartRateUnavailable)
    }

    // MARK: - Losing the heart rate must not cost the run

    func testFinishedRunDropsThePartialAverageAndKeepsEverythingElse() {
        let wm = WorkoutManager()
        wm.state = .recording
        feed(wm, [loc(51.5000), loc(51.5001), loc(51.5002)])
        let bankedBeforeFailure = wm.distanceMetres
        XCTAssertGreaterThan(bankedBeforeFailure, 0)

        wm.healthKit.averageBPM = 138
        wm.healthKit.handleSessionFailure()

        // The GPS stream is untouched by a HealthKit failure.
        feed(wm, [loc(51.5003), loc(51.5004)])
        XCTAssertGreaterThan(wm.distanceMetres, bankedBeforeFailure)

        wm.stop()

        XCTAssertNil(wm.finishedRun?.averageBPM,
                     "an average that covered part of the run must not be recorded as the run's")
        XCTAssertEqual(wm.finishedRun?.distanceMetres ?? 0, wm.distanceMetres, accuracy: 0.0001)
        XCTAssertEqual(wm.finishedRun?.trackPointCount, 5)
    }

    func testFinishedRunKeepsTheAverageWhenTheSessionSurvives() {
        let wm = WorkoutManager()
        wm.state = .recording
        feed(wm, [loc(51.5000), loc(51.5001), loc(51.5002)])
        wm.healthKit.averageBPM = 138

        wm.stop()

        XCTAssertEqual(wm.finishedRun?.averageBPM, 138)
    }

    // MARK: - How much of the run the average covered

    // A real `HKWorkoutSession` cannot be constructed in the test host, so the
    // accumulator's own state is unreachable from here. The arithmetic it runs
    // is not: `creditedStep` and `claim` are pure for exactly that reason, and
    // they are what decides whether a run keeps its `avg_bpm`.

    func testAnUnmeasuredRunKeepsItsAverageUnqualified() {
        // The session never started — HealthKit unavailable, the entitlement
        // missing, a simulator. There is no sensor whose duty cycle this could
        // be, so the absence of a measurement must not read as zero coverage.
        let claim = HeartRateCoverage.claim(
            mean: 138,
            coveredSeconds: nil,
            activeElapsedSeconds: 3600
        )
        XCTAssertEqual(claim.averageBPM, 138)
        XCTAssertNil(claim.coverage)
    }

    func testAMinorityCoverageIsNotTheRunsAverage() {
        // Twenty minutes of a four-hour run.
        let claim = HeartRateCoverage.claim(
            mean: 138,
            coveredSeconds: 20 * 60,
            activeElapsedSeconds: 4 * 3600
        )
        XCTAssertNil(claim.averageBPM,
                     "a mean over 8% of the run is a wrong number, not a partial one")
        XCTAssertEqual(claim.coverage, 0.08)
    }

    func testCoverageIsRoundedBeforeItIsCompared() {
        // 0.4951 stores as 0.50. Grading the raw fraction would suppress the
        // average beside a stored coverage of 0.5 — a record contradicting
        // itself, which is worse than either answer.
        let claim = HeartRateCoverage.claim(
            mean: 138,
            coveredSeconds: 4951,
            activeElapsedSeconds: 10_000
        )
        XCTAssertEqual(claim.coverage, 0.5)
        XCTAssertEqual(claim.averageBPM, 138)
    }

    func testFullCoverageKeepsTheAverageAndClampsAboveOne() {
        let full = HeartRateCoverage.claim(mean: 138, coveredSeconds: 3600, activeElapsedSeconds: 3600)
        XCTAssertEqual(full.coverage, 1)
        XCTAssertEqual(full.averageBPM, 138)

        // A tick landing a fraction past the clock it is measured against
        // must not report 1.02 of a run.
        let over = HeartRateCoverage.claim(mean: 138, coveredSeconds: 3700, activeElapsedSeconds: 3600)
        XCTAssertEqual(over.coverage, 1)
        XCTAssertEqual(over.averageBPM, 138)
    }

    func testEveryUnusableClockFallsBackToNoClaimRatherThanToZero() {
        for elapsed: TimeInterval in [0, -1, .nan, .infinity] {
            let claim = HeartRateCoverage.claim(
                mean: 138,
                coveredSeconds: 10,
                activeElapsedSeconds: elapsed
            )
            XCTAssertNil(claim.coverage, "elapsed \(elapsed) is not a measurement")
            XCTAssertEqual(claim.averageBPM, 138,
                           "an unusable clock must not delete a good average: \(elapsed)")
        }
        let notANumber = HeartRateCoverage.claim(
            mean: 138,
            coveredSeconds: .nan,
            activeElapsedSeconds: 3600
        )
        XCTAssertNil(notANumber.coverage)
        XCTAssertEqual(notANumber.averageBPM, 138)
    }

    func testNoAverageStaysNoAverageWhateverTheCoverage() {
        let claim = HeartRateCoverage.claim(mean: nil, coveredSeconds: 3600, activeElapsedSeconds: 3600)
        XCTAssertNil(claim.averageBPM)
        XCTAssertEqual(claim.coverage, 1, "a run with no strap still records that the sensor was on")
    }

    func testATickCreditsOnlyWhileTheNewestSampleIsFresh() {
        // Fresh: the whole step counts.
        XCTAssertEqual(
            HeartRateCoverage.creditedStep(
                activeElapsedSeconds: 61, lastTickSeconds: 60, sampleAgeSeconds: 4
            ),
            1
        )
        // Quiet for longer than the freshness window: nothing counts. This is
        // the case the whole measurement exists for — a live session whose
        // sensor has stopped delivering.
        XCTAssertEqual(
            HeartRateCoverage.creditedStep(
                activeElapsedSeconds: 61, lastTickSeconds: 60,
                sampleAgeSeconds: HeartRateCoverage.sampleFreshInterval + 0.001
            ),
            0
        )
        // Exactly at the window is still fresh.
        XCTAssertEqual(
            HeartRateCoverage.creditedStep(
                activeElapsedSeconds: 61, lastTickSeconds: 60,
                sampleAgeSeconds: HeartRateCoverage.sampleFreshInterval
            ),
            1
        )
        // A clock that disagrees by a moment is not a stale sensor.
        XCTAssertEqual(
            HeartRateCoverage.creditedStep(
                activeElapsedSeconds: 61, lastTickSeconds: 60, sampleAgeSeconds: -0.5
            ),
            1
        )
    }

    func testATickCreditsNothingBeforeTheFirstSampleOrOnAStalledClock() {
        // No sample has ever arrived — the sensor has not started delivering,
        // so there is nothing to credit.
        XCTAssertEqual(
            HeartRateCoverage.creditedStep(
                activeElapsedSeconds: 61, lastTickSeconds: 60, sampleAgeSeconds: nil
            ),
            0
        )
        // A repeated or backwards reading of the active clock credits nothing
        // rather than crediting a negative.
        for elapsed: TimeInterval in [60, 59, .nan] {
            XCTAssertEqual(
                HeartRateCoverage.creditedStep(
                    activeElapsedSeconds: elapsed, lastTickSeconds: 60, sampleAgeSeconds: 1
                ),
                0,
                "elapsed \(elapsed) is not forward progress"
            )
        }
    }

    func testAnUnstartedSessionMakesNoCoverageClaim() {
        // The end-to-end shape of the fail-closed branch, through the manager
        // rather than through the pure helper: a `HealthKitManager` whose
        // session never started grades as unmeasured however many ticks it is
        // handed, so the run keeps the average it would have kept anyway.
        let hk = HealthKitManager()
        hk.averageBPM = 138
        for second in 1...5 {
            hk.advanceCoverage(activeElapsedSeconds: TimeInterval(second))
        }
        let claim = hk.heartRateClaim(activeElapsedSeconds: 5)
        XCTAssertNil(claim.coverage)
        XCTAssertEqual(claim.averageBPM, 138)
    }
}

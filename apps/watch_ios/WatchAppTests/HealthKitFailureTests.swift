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

    // A real `HKWorkoutSession` still cannot be constructed in the test host,
    // but the accumulator's state is no longer behind one: `begin` /
    // `noteSample` / `advance` are the three things the wrist does to it, and
    // `advance` takes the instant it is measured at rather than reading a
    // clock, so a whole run walks through here in a millisecond
    // (decisions § 1299). The `HeartRateCoverageAccumulator` section below is
    // that glue; these are the arithmetic it runs.

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

    // MARK: - The accumulator itself

    /// One second of run per tick, the shape the recorder drives.
    ///
    /// `deliveringThrough` is the last active second the sensor produces a
    /// sample for; after it the stream is silent for the rest of the run.
    /// Returns the credited seconds the run would end with.
    private func walkRun(
        activeSeconds: Int,
        deliveringFrom: Int = 1,
        deliveringThrough: Int
    ) -> TimeInterval? {
        // An arbitrary but realistic reference instant: the epoch is only ever
        // read as a difference, and a zero base would collide with the
        // "no sample yet" sentinel on the first tick.
        let base: TimeInterval = 800_000_000
        var acc = HeartRateCoverageAccumulator()
        acc.begin()
        for second in 1...activeSeconds {
            let now = base + TimeInterval(second)
            if second >= deliveringFrom && second <= deliveringThrough {
                acc.noteSample(atEpoch: now)
            }
            acc.advance(activeElapsedSeconds: TimeInterval(second), nowEpoch: now)
        }
        return acc.coveredSeconds
    }

    func testAnAccumulatorThatNeverBeganMeasuresNothingHoweverLongItRuns() {
        // The fail-safe branch, at the value level: no session, so no sensor
        // whose duty cycle this could be. Ticks are handed to it anyway
        // because the recorder's ticker does not know whether HealthKit
        // started.
        var acc = HeartRateCoverageAccumulator()
        acc.noteSample(atEpoch: 800_000_000)
        for second in 1...600 {
            acc.advance(activeElapsedSeconds: TimeInterval(second), nowEpoch: 800_000_000 + TimeInterval(second))
        }
        XCTAssertNil(acc.coveredSeconds, "unmeasured must never collapse to a measured zero")
    }

    func testASensorDeliveringThroughoutCoversTheWholeRun() {
        XCTAssertEqual(walkRun(activeSeconds: 600, deliveringThrough: 600), 600.0)
    }

    func testASensorThatQuitsPartWayGradesTheRunItActuallyCovered() {
        // Twenty minutes of an hour, then silence. The credited figure is the
        // twenty minutes plus exactly one freshness window: the last sample
        // stays evidence that the sensor is delivering for 30 s after it
        // arrives, and that tail is the measurement's stated resolution.
        let covered = walkRun(activeSeconds: 3600, deliveringThrough: 1200)
        XCTAssertEqual(covered, 1230.0)

        let claim = HeartRateCoverage.claim(
            mean: 150,
            coveredSeconds: covered,
            activeElapsedSeconds: 3600
        )
        XCTAssertEqual(claim.coverage, 0.34)
        XCTAssertNil(
            claim.averageBPM,
            "a mean over a third of the run is not the run's average — this is the whole path " +
            "from a quiet sensor to a suppressed avg_bpm, and until now no machine had run it"
        )
    }

    func testTicksBeforeTheFirstSampleAreNeverCreditedNorRecoveredLater() {
        // The sensor takes a minute to produce anything — a cold start, a
        // wrist that has not warmed up. Those sixty seconds are not covered,
        // and the first sample must not retroactively buy them.
        let covered = walkRun(activeSeconds: 600, deliveringFrom: 61, deliveringThrough: 600)
        XCTAssertEqual(covered, 540.0)
    }

    func testASilenceIsChargedOnceRatherThanRecreditedWhenTheSensorReturns() {
        let base: TimeInterval = 800_000_000
        var acc = HeartRateCoverageAccumulator()
        acc.begin()
        // Ten seconds delivering.
        for second in 1...10 {
            acc.noteSample(atEpoch: base + TimeInterval(second))
            acc.advance(activeElapsedSeconds: TimeInterval(second), nowEpoch: base + TimeInterval(second))
        }
        XCTAssertEqual(acc.coveredSeconds, 10.0)
        // Ninety seconds silent: the last sample carries 30 s of freshness and
        // nothing after it counts.
        for second in 11...100 {
            acc.advance(activeElapsedSeconds: TimeInterval(second), nowEpoch: base + TimeInterval(second))
        }
        XCTAssertEqual(acc.coveredSeconds, 40.0)
        // The sensor comes back. One tick, one second — not the sixty the run
        // spent uncovered, which is what an interval left open across the
        // silence would have credited.
        acc.noteSample(atEpoch: base + 101)
        acc.advance(activeElapsedSeconds: 101, nowEpoch: base + 101)
        XCTAssertEqual(acc.coveredSeconds, 41.0)
    }

    func testARepeatedTickCreditsNothingAndDoesNotStallTheNextOne() {
        let base: TimeInterval = 800_000_000
        var acc = HeartRateCoverageAccumulator()
        acc.begin()
        acc.noteSample(atEpoch: base + 10)
        acc.advance(activeElapsedSeconds: 10, nowEpoch: base + 10)
        XCTAssertEqual(acc.coveredSeconds, 10.0)
        acc.advance(activeElapsedSeconds: 10, nowEpoch: base + 10)
        XCTAssertEqual(acc.coveredSeconds, 10.0, "the same active second cannot be covered twice")
        acc.noteSample(atEpoch: base + 11)
        acc.advance(activeElapsedSeconds: 11, nowEpoch: base + 11)
        XCTAssertEqual(acc.coveredSeconds, 11.0)
    }

    func testANonFiniteTickNeitherCreditsNorMovesTheMark() {
        // The mark is only advanced on a finite reading. Were it not, a single
        // NaN would poison every subsequent step — the difference against NaN
        // is NaN, `creditedStep` refuses it, and the run would grade zero from
        // that tick on however long the sensor kept delivering.
        let base: TimeInterval = 800_000_000
        var acc = HeartRateCoverageAccumulator()
        acc.begin()
        acc.noteSample(atEpoch: base + 10)
        acc.advance(activeElapsedSeconds: 10, nowEpoch: base + 10)
        for bad: TimeInterval in [Double.nan, Double.infinity, -Double.infinity] {
            acc.noteSample(atEpoch: base + 11)
            acc.advance(activeElapsedSeconds: bad, nowEpoch: base + 11)
            XCTAssertEqual(acc.coveredSeconds, 10.0, "\(bad) is not a reading of the active clock")
        }
        acc.noteSample(atEpoch: base + 11)
        acc.advance(activeElapsedSeconds: 11, nowEpoch: base + 11)
        XCTAssertEqual(acc.coveredSeconds, 11.0, "the mark was still at 10, so this tick is worth one second")
    }

    func testBeginningDiscardsASamplePredatingTheRun() {
        // A delivery from the previous run's builder, landing while this run
        // is starting, is not evidence about this run's sensor. `begin` drops
        // the stamp, so the first ticks credit nothing until a sample of this
        // run's own arrives.
        let base: TimeInterval = 800_000_000
        var acc = HeartRateCoverageAccumulator()
        acc.noteSample(atEpoch: base)
        acc.begin()
        for second in 1...10 {
            acc.advance(activeElapsedSeconds: TimeInterval(second), nowEpoch: base + TimeInterval(second))
        }
        XCTAssertEqual(acc.coveredSeconds, 0.0, "a measured zero, not a credited ten")
    }

    func testResetReturnsAMeasuredRunToUnmeasured() {
        let base: TimeInterval = 800_000_000
        var acc = HeartRateCoverageAccumulator()
        acc.begin()
        acc.noteSample(atEpoch: base + 1)
        acc.advance(activeElapsedSeconds: 1, nowEpoch: base + 1)
        XCTAssertEqual(acc.coveredSeconds, 1.0)
        acc.reset()
        XCTAssertNil(acc.coveredSeconds, "the next run has no session yet — nothing is measuring")
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

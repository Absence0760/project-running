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
}

import XCTest
import CoreLocation
@testable import WatchApp

/// Distance accumulation on the watchOS run recorder — specifically the
/// pause -> wander -> resume case (issue #371). `pause()` stops location
/// updates and `resume()` restarts them; the per-fix distance delta must be
/// measured against a reference (`lastLocationForDistance`) that is CLEARED on
/// resume, NOT against the last stored track point. Otherwise a runner who
/// drifts 20-90 m while paused (aid-station wander, GPS reacquisition jitter)
/// has that movement misattributed as post-resume distance the instant the
/// first new fix lands — because a 40 m gap falls squarely inside the
/// `2..<100 m` filter band.
///
/// Constructing `WorkoutManager` is side-effect-free until `start()`, and
/// `didUpdateLocations` reads only `lastLocationForDistance` / `track` and
/// appends — it never touches the live `CLLocationManager`, HealthKit, or
/// timers — so it is safe to drive directly in the test host. Nil-ing
/// `lastLocationForDistance` between batches reproduces exactly what
/// `resume()` does at the pause boundary.
final class WorkoutManagerDistanceTests: XCTestCase {

    private func loc(_ lat: Double, _ lng: Double, accuracy: Double = 5) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            altitude: 10,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            timestamp: Date()
        )
    }

    private func feed(_ wm: WorkoutManager, _ locations: [CLLocation]) {
        wm.locationManager(CLLocationManager(), didUpdateLocations: locations)
    }

    // MARK: - distanceDelta pure function (the extracted, unit-testable core)

    func testDistanceDeltaInBandIsAdded() {
        // ~11 m apart (0.0001 deg latitude): inside the 2..<100 band.
        let a = loc(51.5000, -0.1000)
        let b = loc(51.5001, -0.1000)
        let delta = WorkoutManager.distanceDelta(from: a, to: b)
        XCTAssertGreaterThan(delta, 0)
        XCTAssertEqual(delta, a.distance(from: b), accuracy: 0.0001)
    }

    func testDistanceDeltaBelowFloorIsRejected() {
        // ~1.1 m apart: stationary GPS jitter, below the 2 m floor -> 0.
        let a = loc(51.5000, -0.1000)
        let b = loc(51.50001, -0.1000)
        XCTAssertLessThan(a.distance(from: b), 2)
        XCTAssertEqual(WorkoutManager.distanceDelta(from: a, to: b), 0)
    }

    func testDistanceDeltaAboveCeilingIsRejected() {
        // ~445 m apart: a reacquisition teleport, above the 100 m ceiling -> 0.
        let a = loc(51.5000, -0.1000)
        let b = loc(51.5040, -0.1000)
        XCTAssertGreaterThan(a.distance(from: b), 100)
        XCTAssertEqual(WorkoutManager.distanceDelta(from: a, to: b), 0)
    }

    // MARK: - Normal movement still accumulates

    func testConsecutiveFixesAccumulateDistance() {
        let wm = WorkoutManager()
        let a = loc(51.5000, -0.1000)
        let b = loc(51.5001, -0.1000)
        let c = loc(51.5002, -0.1000)
        feed(wm, [a, b, c])
        // First fix establishes the reference (adds nothing); the next two each
        // add their ~11 m leg.
        XCTAssertEqual(wm.distanceMetres, a.distance(from: b) + b.distance(from: c), accuracy: 0.01)
    }

    func testFirstFixEverAddsNoPhantomDistance() {
        // A run's very first fix has a nil reference, so it must add zero —
        // the same nil-reference contract resume() relies on.
        let wm = WorkoutManager()
        feed(wm, [loc(51.5000, -0.1000)])
        XCTAssertEqual(wm.distanceMetres, 0)
    }

    // MARK: - The pause -> wander -> resume regression (#371)

    func testWanderWhilePausedAddsNoDistanceOnResume() {
        let wm = WorkoutManager()

        // Recording: move ~11 m from A to B.
        let a = loc(51.5000, -0.1000)
        let b = loc(51.5001, -0.1000)
        feed(wm, [a, b])
        let bankedBeforePause = wm.distanceMetres
        XCTAssertGreaterThan(bankedBeforePause, 0)

        // resume() clears the delta reference at the pause boundary.
        wm.lastLocationForDistance = nil

        // The runner wandered ~44 m from B while paused. Were the delta still
        // measured against B (the bug), this 44 m sits inside the 2..<100 band
        // and would be added the instant the first post-resume fix lands.
        let c = loc(51.5005, -0.1000)
        XCTAssertGreaterThan(WorkoutManager.distanceDelta(from: b, to: c), 40,
                             "pre-fix behaviour would have added this phantom leg")
        feed(wm, [c])
        XCTAssertEqual(wm.distanceMetres, bankedBeforePause, accuracy: 0.0001,
                       "first fix after resume must establish a fresh reference, not bank the pause wander")

        // And normal accumulation resumes on the next real leg.
        let d = loc(51.5006, -0.1000)
        feed(wm, [d])
        XCTAssertEqual(wm.distanceMetres, bankedBeforePause + c.distance(from: d), accuracy: 0.01)
    }

    func testBadAccuracyFixIsIgnoredForDistanceAndReference() {
        let wm = WorkoutManager()
        let a = loc(51.5000, -0.1000)
        let b = loc(51.5001, -0.1000)
        feed(wm, [a, b])
        let banked = wm.distanceMetres

        // A fix with horizontalAccuracy >= 30 is rejected before it can move
        // the distance or the reference.
        feed(wm, [loc(51.5002, -0.1000, accuracy: 50)])
        XCTAssertEqual(wm.distanceMetres, banked, accuracy: 0.0001)

        // The reference is still B, so the next good fix measures against B.
        let c = loc(51.5002, -0.1000)
        feed(wm, [c])
        XCTAssertEqual(wm.distanceMetres, banked + b.distance(from: c), accuracy: 0.01)
    }
}

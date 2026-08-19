import XCTest
import CoreLocation
@testable import WatchApp

/// The rolling pace window across a pause boundary.
///
/// `updatePace` walks `track` backwards until ~200 m accumulate and divides
/// by the timestamp span of that segment. A pause puts an unbounded wall-clock
/// gap between two adjacent track points, so a window allowed to straddle it
/// charges the whole aid-station stop to the metres run after it: a 12-minute
/// stop makes the first ~200 m read on the order of an hour per kilometre.
/// That number is published to the complication and fed to `checkPaceAlert`,
/// so the error runs in the direction that fires a false "too slow" haptic.
/// `resume()` must therefore seal the window, not only re-anchor the distance
/// reference (issue #371 fixed the latter alone).
///
/// The state machine is driven directly rather than through `start()`:
/// `pause()` and `resume()` touch only the frozen-checkpoint guard (a no-op
/// without a `CheckpointStore`), the idle `CLLocationManager`, a nil HealthKit
/// session and the App-Group snapshot — none of which need a live run.
final class WorkoutManagerPaceTests: XCTestCase {

    private let legDegrees = 0.0001
    private let legSeconds: TimeInterval = 3.34

    private func loc(_ lat: Double, at timestamp: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: -0.1),
            altitude: 10,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: timestamp
        )
    }

    /// `count` fixes marching north one `legDegrees` step per `legSeconds`.
    private func leg(from lat: Double, at start: Date, count: Int) -> [CLLocation] {
        (0..<count).map {
            loc(lat + Double($0) * legDegrees, at: start.addingTimeInterval(Double($0) * legSeconds))
        }
    }

    private func feed(_ wm: WorkoutManager, _ locations: [CLLocation]) {
        wm.locationManager(CLLocationManager(), didUpdateLocations: locations)
    }

    /// Seconds per km implied by one leg — the honest pace of both halves of
    /// the run below, derived rather than hardcoded so it tracks whatever
    /// `CLLocation` measures a 0.0001° step to be.
    private func expectedPace() -> Double {
        let base = Date()
        let a = loc(51.5, at: base)
        let b = loc(51.5 + legDegrees, at: base)
        return (legSeconds / a.distance(from: b)) * 1000
    }

    func testPaceAfterResumeExcludesThePausedSpan() {
        let wm = WorkoutManager()
        wm.state = .recording
        let expected = expectedPace()
        let base = Date()

        feed(wm, leg(from: 51.5, at: base, count: 8))
        XCTAssertEqual(wm.currentPace ?? 0, expected, accuracy: 15,
                       "harness check: the pre-pause window reads the honest pace")

        wm.pause()
        let bankedBeforeResume = wm.distanceMetres
        wm.resume()

        XCTAssertNil(wm.currentPace,
                     "resume() must drop the pace it can no longer justify, not leave the pre-pause value published")
        XCTAssertEqual(wm.distanceMetres, bankedBeforeResume, accuracy: 0.0001,
                       "sealing the pace window must not cost the run any banked distance")

        // 12 minutes standing at an aid station, then the runner picks up
        // where they stopped and holds the same pace.
        let resumedAt = base.addingTimeInterval(7 * legSeconds + 720)
        feed(wm, leg(from: 51.5 + 8 * legDegrees, at: resumedAt, count: 8))

        XCTAssertEqual(wm.currentPace ?? 0, expected, accuracy: 15,
                       "the post-resume window must time only post-resume metres")
    }

    func testPaceIsWithheldUntilTheResumedWindowRefills() {
        let wm = WorkoutManager()
        wm.state = .recording
        let base = Date()

        feed(wm, leg(from: 51.5, at: base, count: 8))
        wm.pause()
        wm.resume()

        // Four fixes is one short of `updatePace`'s minimum, and with the
        // pre-pause tail still in the window it would have been enough.
        let resumedAt = base.addingTimeInterval(7 * legSeconds + 720)
        feed(wm, leg(from: 51.5 + 8 * legDegrees, at: resumedAt, count: 4))
        XCTAssertNil(wm.currentPace)
    }
}

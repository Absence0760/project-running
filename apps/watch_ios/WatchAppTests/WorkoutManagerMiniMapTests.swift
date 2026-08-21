import XCTest
import CoreLocation
@testable import WatchApp

/// The seam between the GPS stream and the mini-map. `didUpdateLocations` is
/// safe to drive directly in the test host (see `WorkoutManagerDistanceTests`),
/// so the wiring is checked without a live `CLLocationManager`: which fixes
/// reach the map, that the trail spans the whole run rather than the recorder's
/// rolling window, and that a run with nothing usable yet reports no position
/// instead of a default one.
final class WorkoutManagerMiniMapTests: XCTestCase {

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

    func testAFreshRecorderClaimsNoPositionAndNoTrail() {
        let wm = WorkoutManager()
        XCTAssertNil(wm.mapPosition)
        XCTAssertTrue(wm.mapTrail.points.isEmpty)
        XCTAssertTrue(wm.mapRoute.isEmpty)
        XCTAssertNil(
            MiniMapContent.make(
                route: wm.mapRoute,
                trail: wm.mapTrail.points,
                current: wm.mapPosition,
                sideLength: 160
            ),
            "nothing to draw before the first fix"
        )
    }

    func testTheLastAcceptedFixBecomesTheMapPosition() {
        let wm = WorkoutManager()
        feed(wm, [loc(51.5000, -0.1000), loc(51.5003, -0.1000)])
        XCTAssertEqual(wm.mapPosition, MiniMapPoint(latitude: 51.5003, longitude: -0.1000))
    }

    func testAnInaccurateFixNeverReachesTheMap() {
        let wm = WorkoutManager()
        feed(wm, [loc(51.5000, -0.1000, accuracy: 120)])
        XCTAssertNil(wm.mapPosition)
        XCTAssertTrue(wm.mapTrail.points.isEmpty)
    }

    func testTheTrailSpansTheWholeRunRatherThanTheRollingWindow() {
        let wm = WorkoutManager()
        // ~33 m per fix, well past the in-memory track window so the recorder's
        // own buffer no longer holds the start of the run.
        let fixes = (0..<1_200).map { loc(51.5 + Double($0) * 0.0003, -0.1) }
        feed(wm, fixes)
        XCTAssertGreaterThan(wm.trackPointCount, wm.track.count)
        XCTAssertEqual(
            wm.mapTrail.points.first,
            MiniMapPoint(latitude: 51.5, longitude: -0.1),
            "the map still knows where the run started"
        )
        XCTAssertLessThanOrEqual(wm.mapTrail.points.count, MiniMapTrail.capacity)
        XCTAssertGreaterThan(wm.mapTrail.points.count, 2)
    }

    func testResetClearsTheMapState() {
        let wm = WorkoutManager()
        feed(wm, [loc(51.5000, -0.1000), loc(51.5010, -0.1000)])
        XCTAssertNotNil(wm.mapPosition)
        wm.reset()
        XCTAssertNil(wm.mapPosition)
        XCTAssertTrue(wm.mapTrail.points.isEmpty)
        XCTAssertTrue(wm.mapRoute.isEmpty)
        XCTAssertEqual(wm.mapTrail.spacingMetres, MiniMapTrail.initialSpacingMetres)
    }
}

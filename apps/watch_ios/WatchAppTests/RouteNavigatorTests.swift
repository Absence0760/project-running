import XCTest
import CoreLocation
@testable import WatchApp

/// Mirrors the `distanceAlongRoute` cases in the web
/// `route_geometry.test.ts` (fixtures anchored in ground metres along the
/// equator, like `route_snap.test.ts` / the custom watch's `course.rs`
/// tests) plus the shared 40 m / 20 m off-route hysteresis cases.
final class RouteNavigatorTests: XCTestCase {
    private static let metresPerDegree = 6_371_000.0 * Double.pi / 180.0

    private func distPoint(_ metres: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 0, longitude: metres / Self.metresPerDegree)
    }

    private func offsetPoint(east: Double, north: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: north / Self.metresPerDegree,
            longitude: east / Self.metresPerDegree
        )
    }

    private var threeLegLine: [CLLocationCoordinate2D] {
        [distPoint(0), distPoint(100), distPoint(200), distPoint(300)]
    }

    private func project(
        _ position: CLLocationCoordinate2D, onto points: [CLLocationCoordinate2D]
    ) -> RouteProjection? {
        RouteGeometry.project(
            position,
            onto: points,
            totalLengthMetres: RouteGeometry.totalLengthMetres(points)
        )
    }

    // MARK: - Geometry

    func testProjectNilOnFewerThanTwoPoints() {
        XCTAssertNil(project(distPoint(0), onto: []))
        XCTAssertNil(project(distPoint(0), onto: [distPoint(0)]))
    }

    func testProjectNilOnNonFinitePoint() {
        let line = threeLegLine
        XCTAssertNil(project(
            CLLocationCoordinate2D(latitude: .nan, longitude: 0), onto: line))
        XCTAssertNil(project(
            CLLocationCoordinate2D(latitude: 0, longitude: .infinity), onto: line))
    }

    func testProjectNilOnNonFiniteRouteVertex() {
        let line = [distPoint(0), CLLocationCoordinate2D(latitude: .nan, longitude: 0.001)]
        XCTAssertNil(project(distPoint(50), onto: line))
    }

    func testTotalLengthOfHundredMetreEquatorSegment() {
        let total = RouteGeometry.totalLengthMetres([distPoint(0), distPoint(100)])
        XCTAssertEqual(total, 100, accuracy: 1)
        XCTAssertEqual(RouteGeometry.totalLengthMetres([]), 0)
        XCTAssertEqual(RouteGeometry.totalLengthMetres([distPoint(0)]), 0)
    }

    func testPointOnVertexReturnsCumulativeDistance() {
        let p = project(distPoint(200), onto: threeLegLine)!
        XCTAssertEqual(p.alongRouteMetres, 200, accuracy: 1)
        XCTAssertEqual(p.remainingMetres, 100, accuracy: 1)
        XCTAssertEqual(p.deviationMetres, 0, accuracy: 0.5)
    }

    func testPointMidSegmentReturnsInterpolatedDistance() {
        let p = project(distPoint(150), onto: threeLegLine)!
        XCTAssertEqual(p.alongRouteMetres, 150, accuracy: 1)
        XCTAssertEqual(p.remainingMetres, 150, accuracy: 1)
    }

    func testPerpendicularOffsetStillMapsToRightAlongDistance() {
        let p = project(offsetPoint(east: 150, north: 50), onto: threeLegLine)!
        XCTAssertEqual(p.deviationMetres, 50, accuracy: 1)
        XCTAssertEqual(p.alongRouteMetres, 150, accuracy: 1)
        XCTAssertEqual(p.remainingMetres, 150, accuracy: 1)
    }

    func testPointBeforeStartClampsToStart() {
        let p = project(offsetPoint(east: -80, north: 0), onto: threeLegLine)!
        XCTAssertEqual(p.alongRouteMetres, 0, accuracy: 0.001)
        XCTAssertEqual(p.remainingMetres, 300, accuracy: 1)
        XCTAssertEqual(p.deviationMetres, 80, accuracy: 1)
    }

    func testPointPastEndClampsToEnd() {
        let p = project(distPoint(10_000), onto: threeLegLine)!
        XCTAssertEqual(p.alongRouteMetres, 300, accuracy: 1)
        XCTAssertEqual(p.remainingMetres, 0, accuracy: 0.001)
        XCTAssertEqual(p.deviationMetres, 9_700, accuracy: 15)
    }

    func testPicksTheNearestOfTwoSegments() {
        // The web LINE fixture: a west-east leg at latitude 51.5, then a
        // leg turning north. A point just east of the corner is nearest
        // the second (vertical) leg, so along-distance includes the whole
        // first leg.
        let line = [
            CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12),
            CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1),
            CLLocationCoordinate2D(latitude: 51.51, longitude: -0.1),
        ]
        let firstLeg = RouteGeometry.totalLengthMetres(Array(line.prefix(2)))
        let p = project(
            CLLocationCoordinate2D(latitude: 51.505, longitude: -0.099), onto: line)!
        XCTAssertGreaterThan(p.alongRouteMetres, firstLeg)
    }

    func testDuplicateConsecutiveVerticesDoNotDivideByZero() {
        let line = [distPoint(0), distPoint(0), distPoint(200)]
        let p = project(offsetPoint(east: 100, north: 10), onto: line)!
        XCTAssertTrue(p.alongRouteMetres.isFinite)
        XCTAssertTrue(p.deviationMetres.isFinite)
        XCTAssertEqual(p.alongRouteMetres, 100, accuracy: 1)
    }

    func testFarOffPositionStaysFiniteAndClamped() {
        let p = project(
            CLLocationCoordinate2D(latitude: 10, longitude: 10), onto: threeLegLine)!
        XCTAssertTrue(p.deviationMetres.isFinite)
        XCTAssertGreaterThanOrEqual(p.alongRouteMetres, 0)
        XCTAssertLessThanOrEqual(p.alongRouteMetres, 301)
        XCTAssertGreaterThan(p.deviationMetres, OffRouteLatch.thresholdMetres)
    }

    // MARK: - Hysteresis latch

    func testLatchFiresOnceAndStaysLatchedWhileOut() {
        var latch = OffRouteLatch()
        XCTAssertFalse(latch.update(deviationMetres: 10))
        XCTAssertFalse(latch.isOffRoute)
        // Exactly at the threshold is still on route (strict >).
        XCTAssertFalse(latch.update(deviationMetres: OffRouteLatch.thresholdMetres))
        XCTAssertFalse(latch.isOffRoute)
        XCTAssertTrue(latch.update(deviationMetres: 41))
        XCTAssertTrue(latch.isOffRoute)
        XCTAssertFalse(latch.update(deviationMetres: 80))
        XCTAssertTrue(latch.isOffRoute)
    }

    func testLatchRearmsOnlyBelowHalfTheThreshold() {
        var latch = OffRouteLatch()
        XCTAssertTrue(latch.update(deviationMetres: 50))
        // Back inside the threshold but above the re-arm band: still
        // latched, and drifting out again does NOT re-fire.
        XCTAssertFalse(latch.update(deviationMetres: 30))
        XCTAssertTrue(latch.isOffRoute)
        XCTAssertFalse(latch.update(deviationMetres: 50))
        // Fully back on route re-arms; the next excursion fires again.
        XCTAssertFalse(latch.update(deviationMetres: 10))
        XCTAssertFalse(latch.isOffRoute)
        XCTAssertTrue(latch.update(deviationMetres: 45))
    }

    func testLatchDoesNotRearmExactlyAtTheRearmBoundary() {
        var latch = OffRouteLatch()
        XCTAssertTrue(latch.update(deviationMetres: 50))
        XCTAssertFalse(latch.update(deviationMetres: OffRouteLatch.rearmMetres))
        XCTAssertTrue(latch.isOffRoute)
        XCTAssertFalse(latch.update(deviationMetres: OffRouteLatch.rearmMetres - 0.001))
        XCTAssertFalse(latch.isOffRoute)
        XCTAssertTrue(latch.update(deviationMetres: 45))
    }

    func testLatchDoesNotFlapHoveringAtTheThreshold() {
        var latch = OffRouteLatch()
        var fires = 0
        for deviation in [39.999, 40.001, 39.999, 40.001, 40.0, 40.001] {
            if latch.update(deviationMetres: deviation) { fires += 1 }
        }
        XCTAssertEqual(fires, 1)
        XCTAssertTrue(latch.isOffRoute)
    }

    // MARK: - RouteNavigator wiring

    private func location(_ coordinate: CLLocationCoordinate2D) -> CLLocation {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    func testNavigatorPublishesProjectionAndFiresHapticOncePerTransition() {
        let navigator = RouteNavigator(
            routePoints: threeLegLine.map(location))
        var haptics = 0
        navigator.playOffRouteHaptic = { haptics += 1 }

        navigator.update(currentLocation: location(distPoint(150)))
        XCTAssertFalse(navigator.isOffRoute)
        XCTAssertEqual(navigator.deviationMetres ?? -1, 0, accuracy: 0.5)
        XCTAssertEqual(navigator.remainingMetres ?? -1, 150, accuracy: 1)
        XCTAssertEqual(haptics, 0)

        navigator.update(
            currentLocation: location(offsetPoint(east: 150, north: 50)))
        XCTAssertTrue(navigator.isOffRoute)
        XCTAssertEqual(haptics, 1)

        // Staying out does not re-fire.
        navigator.update(
            currentLocation: location(offsetPoint(east: 160, north: 60)))
        XCTAssertEqual(haptics, 1)

        // Fully back on route clears and re-arms.
        navigator.update(currentLocation: location(distPoint(170)))
        XCTAssertFalse(navigator.isOffRoute)
        XCTAssertEqual(haptics, 1)

        navigator.update(
            currentLocation: location(offsetPoint(east: 180, north: 50)))
        XCTAssertTrue(navigator.isOffRoute)
        XCTAssertEqual(haptics, 2)
    }

    func testNavigatorNeutralOnDegenerateRoute() {
        let navigator = RouteNavigator(routePoints: [location(distPoint(0))])
        var haptics = 0
        navigator.playOffRouteHaptic = { haptics += 1 }
        navigator.update(currentLocation: location(distPoint(500)))
        XCTAssertFalse(navigator.isOffRoute)
        XCTAssertNil(navigator.deviationMetres)
        XCTAssertNil(navigator.remainingMetres)
        XCTAssertEqual(haptics, 0)
    }

    func testNavigatorKeepsLatchAcrossANonFiniteFix() {
        let navigator = RouteNavigator(routePoints: threeLegLine.map(location))
        var haptics = 0
        navigator.playOffRouteHaptic = { haptics += 1 }

        navigator.update(
            currentLocation: location(offsetPoint(east: 150, north: 50)))
        XCTAssertTrue(navigator.isOffRoute)
        XCTAssertEqual(haptics, 1)

        // One bad fix publishes honest nils but neither clears the latch
        // nor re-fires the haptic on the next good off-route fix.
        navigator.update(
            currentLocation: location(
                CLLocationCoordinate2D(latitude: .nan, longitude: 0)))
        XCTAssertNil(navigator.deviationMetres)
        XCTAssertNil(navigator.remainingMetres)
        XCTAssertTrue(navigator.isOffRoute)

        navigator.update(
            currentLocation: location(offsetPoint(east: 155, north: 55)))
        XCTAssertTrue(navigator.isOffRoute)
        XCTAssertEqual(haptics, 1)
    }
}

import XCTest
import CoreLocation
@testable import WatchApp

/// The phone → watch route push is the only way a route reaches this device,
/// and `WCSession` payloads are untyped plists. These pin the fail-closed
/// decode: anything the watch would have to guess about is dropped whole
/// rather than half-loaded, because a shortened polyline would make the
/// runner "off route" against a line their route does not have.
final class ArmedRouteTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "ArmedRouteTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func payload(
        id: Any = "route-1",
        name: Any = "Riverside loop",
        distance: Any = 5120.0,
        lat: Any = [51.5, 51.51, 51.52],
        lng: Any = [-0.12, -0.11, -0.1]
    ) -> [String: Any] {
        [
            "route_id": id,
            "route_name": name,
            "route_distance_m": distance,
            "route_lat": lat,
            "route_lng": lng,
        ]
    }

    // MARK: - Decode, accepted

    func testDecodesAWellFormedPayload() {
        let route = ArmedRoute.decode(payload())
        XCTAssertEqual(route?.id, "route-1")
        XCTAssertEqual(route?.name, "Riverside loop")
        XCTAssertEqual(route?.distanceMetres, 5120)
        XCTAssertEqual(route?.latitudes.count, 3)
        XCTAssertEqual(route?.coordinates.count, 3)
        XCTAssertEqual(route?.locations.count, 3)
        XCTAssertEqual(route?.coordinates.last?.longitude ?? 0, -0.1, accuracy: 1e-9)
    }

    func testDecodesAtExactlyTwoPointsAndAtTheCap() {
        XCTAssertNotNil(ArmedRoute.decode(
            payload(lat: [0.0, 0.001], lng: [0.0, 0.001])))

        let capped = Array(repeating: 0.5, count: ArmedRoute.maxPoints)
        XCTAssertNotNil(ArmedRoute.decode(payload(lat: capped, lng: capped)))
    }

    func testDecodesAnEmptyName() {
        XCTAssertEqual(ArmedRoute.decode(payload(name: ""))?.name, "")
    }

    // MARK: - Decode, refused

    func testNilWhenThePayloadCarriesNoRoute() {
        XCTAssertNil(ArmedRoute.decode([:]))
        XCTAssertNil(ArmedRoute.decode(["preferred_unit": "mi"]))
    }

    func testNilOnMissingOrEmptyId() {
        var p = payload()
        p.removeValue(forKey: "route_id")
        XCTAssertNil(ArmedRoute.decode(p))
        XCTAssertNil(ArmedRoute.decode(payload(id: "")))
        XCTAssertNil(ArmedRoute.decode(payload(id: 7)))
    }

    func testNilOnMissingName() {
        var p = payload()
        p.removeValue(forKey: "route_name")
        XCTAssertNil(ArmedRoute.decode(p))
    }

    func testNilOnUnusableDistance() {
        XCTAssertNil(ArmedRoute.decode(payload(distance: Double.nan)))
        XCTAssertNil(ArmedRoute.decode(payload(distance: Double.infinity)))
        XCTAssertNil(ArmedRoute.decode(payload(distance: -1.0)))
        XCTAssertNil(ArmedRoute.decode(payload(distance: "5120")))
    }

    func testNilOnMismatchedCoordinateArrays() {
        XCTAssertNil(ArmedRoute.decode(
            payload(lat: [51.5, 51.51, 51.52], lng: [-0.12, -0.11])))
    }

    func testNilOnFewerThanTwoPoints() {
        XCTAssertNil(ArmedRoute.decode(payload(lat: [51.5], lng: [-0.12])))
        XCTAssertNil(ArmedRoute.decode(
            payload(lat: [Double](), lng: [Double]())))
    }

    func testNilOverThePointCapRatherThanTruncating() {
        let over = Array(repeating: 0.5, count: ArmedRoute.maxPoints + 1)
        XCTAssertNil(ArmedRoute.decode(payload(lat: over, lng: over)))
    }

    func testNilOnANonFiniteOrOutOfRangeCoordinate() {
        XCTAssertNil(ArmedRoute.decode(
            payload(lat: [51.5, Double.nan], lng: [-0.12, -0.11])))
        XCTAssertNil(ArmedRoute.decode(
            payload(lat: [51.5, 51.51], lng: [-0.12, Double.infinity])))
        XCTAssertNil(ArmedRoute.decode(
            payload(lat: [51.5, 91.0], lng: [-0.12, -0.11])))
        XCTAssertNil(ArmedRoute.decode(
            payload(lat: [51.5, 51.51], lng: [-0.12, 180.001])))
    }

    // MARK: - Store

    func testStoreRoundTripsAndClears() {
        let route = ArmedRoute.decode(payload())!
        XCTAssertNil(ArmedRouteStore.load(defaults: defaults))

        ArmedRouteStore.save(route, defaults: defaults)
        XCTAssertEqual(ArmedRouteStore.load(defaults: defaults), route)

        ArmedRouteStore.clear(defaults: defaults)
        XCTAssertNil(ArmedRouteStore.load(defaults: defaults))
    }

    func testStoreLoadIsNilOnGarbageRatherThanCrashing() {
        defaults.set(Data("not json".utf8), forKey: "armed_route_v1")
        XCTAssertNil(ArmedRouteStore.load(defaults: defaults))
    }

    func testStoreSaveReplacesThePreviousRoute() {
        ArmedRouteStore.save(ArmedRoute.decode(payload())!, defaults: defaults)
        let second = ArmedRoute.decode(payload(id: "route-2", name: "Hill repeats"))!
        ArmedRouteStore.save(second, defaults: defaults)
        XCTAssertEqual(ArmedRouteStore.load(defaults: defaults)?.id, "route-2")
    }

    // MARK: - Feeding the navigator

    func testDecodedRouteDrivesTheNavigator() {
        let metresPerDegree = 6_371_000.0 * Double.pi / 180.0
        let east = { (metres: Double) in metres / metresPerDegree }
        let route = ArmedRoute.decode(payload(
            lat: [0.0, 0.0, 0.0],
            lng: [0.0, east(100), east(200)]
        ))!

        let navigator = RouteNavigator(routePoints: route.locations)
        navigator.playOffRouteHaptic = {}
        navigator.update(currentLocation: CLLocation(latitude: 0, longitude: east(150)))

        XCTAssertFalse(navigator.isOffRoute)
        XCTAssertEqual(navigator.remainingMetres ?? -1, 50, accuracy: 1)
    }
}

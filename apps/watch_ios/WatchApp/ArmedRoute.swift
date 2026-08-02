import Foundation
import CoreLocation

/// A route the paired iPhone pushed for this watch to follow, and the
/// UserDefaults slot it survives in.
///
/// The phone sends it over `WCSession.transferUserInfo(_:)` — queued and
/// durable rather than immediate, because the runner picks a route on the
/// phone long before the watch app is on screen (see
/// `WatchConnectivityManager.session(_:didReceiveUserInfo:)`). A delivery
/// can therefore land while the app is backgrounded or freshly woken, so the
/// route is written to disk on arrival and read back at `WorkoutManager.start()`
/// rather than held only in memory.
///
/// The wire shape is five flat plist values — `route_id`, `route_name`,
/// `route_distance_m`, and two parallel `[Double]` coordinate arrays. Flat
/// arrays rather than an array of dictionaries: a per-point dictionary costs
/// more in the plist than the two doubles it carries, and this frame rides a
/// transport with a hard payload ceiling.
struct ArmedRoute: Codable, Equatable {
    let id: String
    let name: String
    let distanceMetres: Double
    let latitudes: [Double]
    let longitudes: [Double]

    /// Positions a `WCSession` push may carry. The phone thins a denser route
    /// to this budget before sending (`appleWatchRouteFromWaypoints` in
    /// `apple_watch_route_bridge.dart`); anything over it is a payload this
    /// side never agreed to and is dropped whole. 512 keeps the frame around
    /// 8 KB of coordinate data — far inside the transport's ceiling — while
    /// leaving the per-fix projection in `RouteGeometry.project` (linear in
    /// the point count, run at ~1 Hz) inconsequential on a watch CPU.
    static let maxPoints = 512

    var coordinates: [CLLocationCoordinate2D] {
        zip(latitudes, longitudes).map { lat, lng in
            CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }

    var locations: [CLLocation] {
        zip(latitudes, longitudes).map { lat, lng in
            CLLocation(latitude: lat, longitude: lng)
        }
    }

    /// Read a route out of a `WCSession` payload, or nil when the payload
    /// carries no route or one this watch will not follow.
    ///
    /// Every rejection drops the whole push. A truncated or partly-decoded
    /// polyline is worse than none: the runner would be measured off-route
    /// against a line the route does not have, and told they had arrived while
    /// the real course kept going.
    static func decode(_ payload: [String: Any]) -> ArmedRoute? {
        guard let id = payload["route_id"] as? String, !id.isEmpty,
              let name = payload["route_name"] as? String,
              let distance = payload["route_distance_m"] as? Double,
              distance.isFinite, distance >= 0,
              let latitudes = payload["route_lat"] as? [Double],
              let longitudes = payload["route_lng"] as? [Double],
              latitudes.count == longitudes.count,
              latitudes.count >= 2, latitudes.count <= maxPoints
        else { return nil }

        for (lat, lng) in zip(latitudes, longitudes) {
            guard lat.isFinite, lng.isFinite,
                  lat >= -90, lat <= 90, lng >= -180, lng <= 180
            else { return nil }
        }

        return ArmedRoute(
            id: id,
            name: name,
            distanceMetres: distance,
            latitudes: latitudes,
            longitudes: longitudes
        )
    }
}

/// The armed route's home between a phone push and the run that follows it.
enum ArmedRouteStore {
    private static let key = "armed_route_v1"

    static func load(defaults: UserDefaults = .standard) -> ArmedRoute? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ArmedRoute.self, from: data)
    }

    static func save(_ route: ArmedRoute, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(route) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

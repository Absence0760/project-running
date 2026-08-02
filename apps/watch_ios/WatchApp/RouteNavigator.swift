import Foundation
import CoreLocation
import WatchKit

/// One position's projection onto the route polyline. Swift port of the
/// web `route_snap.ts` `snapToPolyline` / `route_geometry.ts`
/// `distanceAlongRoute` contract (also mirrored by Wear's `RouteMath.kt`
/// and the custom watch's `course.rs`): the nearest perpendicular foot on
/// the closest segment — not merely the nearest vertex — in a local
/// planar frame per segment, with along-distance accumulated over
/// haversine segment lengths.
struct RouteProjection: Equatable {
    let deviationMetres: Double
    let alongRouteMetres: Double
    let remainingMetres: Double
}

enum RouteGeometry {
    private static let earthRadiusMetres = 6_371_000.0
    private static let degToRad = Double.pi / 180.0
    private static let metresPerDegree = earthRadiusMetres * degToRad

    static func totalLengthMetres(_ points: [CLLocationCoordinate2D]) -> Double {
        var total = 0.0
        for i in 1..<max(points.count, 1) {
            total += haversineMetres(points[i - 1], points[i])
        }
        return total
    }

    /// Nil when there is no line to project onto (< 2 points, a
    /// non-finite fix, or any non-finite route vertex) — never a bogus
    /// zero, matching `distanceAlongRoute`'s null contract.
    static func project(
        _ position: CLLocationCoordinate2D,
        onto points: [CLLocationCoordinate2D],
        totalLengthMetres total: Double
    ) -> RouteProjection? {
        guard points.count >= 2 else { return nil }
        guard position.latitude.isFinite, position.longitude.isFinite else { return nil }

        var seen = 0.0
        var bestAlong = 0.0
        var bestPerp = Double.infinity
        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]
            guard a.latitude.isFinite, a.longitude.isFinite,
                  b.latitude.isFinite, b.longitude.isFinite else { return nil }
            let segLen = haversineMetres(a, b)
            let cosLat = cos(a.latitude * degToRad)
            let bx = (b.longitude - a.longitude) * cosLat * metresPerDegree
            let by = (b.latitude - a.latitude) * metresPerDegree
            let px = (position.longitude - a.longitude) * cosLat * metresPerDegree
            let py = (position.latitude - a.latitude) * metresPerDegree
            let lenSq = bx * bx + by * by
            let t = lenSq <= 0 ? 0 : min(1, max(0, (px * bx + py * by) / lenSq))
            let dx = px - bx * t
            let dy = py - by * t
            let perp = (dx * dx + dy * dy).squareRoot()
            if perp < bestPerp {
                bestPerp = perp
                bestAlong = seen + t * segLen
            }
            seen += segLen
        }
        let along = min(seen, max(0, bestAlong))
        return RouteProjection(
            deviationMetres: bestPerp,
            alongRouteMetres: along,
            remainingMetres: max(0, total - along)
        )
    }

    private static func haversineMetres(
        _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D
    ) -> Double {
        let dLat = (b.latitude - a.latitude) * degToRad
        let dLng = (b.longitude - a.longitude) * degToRad
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * degToRad) * cos(b.latitude * degToRad)
                * sin(dLng / 2) * sin(dLng / 2)
        return earthRadiusMetres * 2 * asin(min(1, h.squareRoot()))
    }
}

/// The cross-platform off-route hysteresis: alert past 40 m, re-arm only
/// once back within 20 m, so hovering at the boundary can't flap the
/// alert on GPS jitter. Same constants + edges as the mobile run
/// screen's `_offRouteThresholdMetres` block, Wear's banner, and the
/// custom watch's `OffCourseAlert`.
struct OffRouteLatch {
    static let thresholdMetres = 40.0
    static let rearmMetres = thresholdMetres / 2

    private(set) var isOffRoute = false

    /// Feed the latest deviation; true exactly on the off-route rising edge.
    mutating func update(deviationMetres: Double) -> Bool {
        if deviationMetres > Self.thresholdMetres {
            if !isOffRoute {
                isOffRoute = true
                return true
            }
        } else if deviationMetres < Self.rearmMetres {
            isOffRoute = false
        }
        return false
    }
}

/// Detects off-route deviation and provides distance-remaining feedback.
class RouteNavigator: ObservableObject {
    @Published var isOffRoute = false
    @Published var deviationMetres: Double?
    @Published var remainingMetres: Double?

    private let coordinates: [CLLocationCoordinate2D]
    private let totalLengthMetres: Double
    private var latch = OffRouteLatch()

    /// Auxiliary effect seam: fired once per off-route transition, after
    /// every published value is already set, so nothing it does can
    /// disturb the core update (layered-resilience contract).
    var playOffRouteHaptic: () -> Void = {
        WKInterfaceDevice.current().play(.notification)
    }

    init(routePoints: [CLLocation]) {
        coordinates = routePoints.map(\.coordinate)
        totalLengthMetres = RouteGeometry.totalLengthMetres(coordinates)
    }

    func update(currentLocation: CLLocation) {
        guard let projection = RouteGeometry.project(
            currentLocation.coordinate,
            onto: coordinates,
            totalLengthMetres: totalLengthMetres
        ) else {
            // No line, or a non-finite fix: publish honest nils. The
            // latch is left alone so one bad fix can't clear a real
            // off-route state and re-fire the haptic on the next good one.
            deviationMetres = nil
            remainingMetres = nil
            if coordinates.count < 2 { isOffRoute = false }
            return
        }
        deviationMetres = projection.deviationMetres
        remainingMetres = projection.remainingMetres
        let fired = latch.update(deviationMetres: projection.deviationMetres)
        isOffRoute = latch.isOffRoute
        if fired { playOffRouteHaptic() }
    }
}

// MARK: - Display shaping

/// Turns the navigator's published values into what the run screen renders.
/// Pure and unit-tested separately from the SwiftUI view.
enum RouteGuidance {
    enum Status: Equatable {
        case onRoute
        case offRoute
        /// No projection is available — a degenerate route, or a fix the
        /// geometry refused. Distinct from `onRoute` on purpose: a runner
        /// shown nothing cannot tell "you are on the line" from "the watch
        /// has lost track of the line".
        case unknown
    }

    /// A latched off-route state outranks a missing deviation, so one bad fix
    /// cannot downgrade a live alert to "unknown" and back.
    static func status(isOffRoute: Bool, deviationMetres: Double?) -> Status {
        if isOffRoute { return .offRoute }
        return deviationMetres == nil ? .unknown : .onRoute
    }

    /// Distance still to run, in the user's preferred unit. Nil when the
    /// navigator has no projection to report.
    static func remainingText(metres: Double?) -> String? {
        guard let metres, metres.isFinite, metres >= 0 else { return nil }
        return RunFormat.distance(metres: metres, fractionDigits: 2)
    }

    /// How far off the line the runner is, always in metres — a deviation
    /// rendered in miles (`0.04 mi`) tells a runner nothing they can act on,
    /// so this one readout stays metric in both unit modes, matching Wear OS.
    static func deviationText(metres: Double?) -> String? {
        guard let metres, metres.isFinite, metres >= 0 else { return nil }
        let formatter = MeasurementFormatter()
        formatter.locale = Locale.current
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter.string(
            from: Measurement(value: metres.rounded(), unit: UnitLength.meters)
        )
    }
}

import Foundation
import CoreLocation

/// Detects off-route deviation and provides distance-remaining feedback.
class RouteNavigator: ObservableObject {
    @Published var isOffRoute = false
    @Published var deviationMetres: Double = 0
    @Published var remainingMetres: Double = 0

    private let routePoints: [CLLocation]
    private let offRouteThreshold: Double = 50.0

    init(routePoints: [CLLocation]) {
        self.routePoints = routePoints
    }

    func update(currentLocation: CLLocation) {
        // TODO: Find nearest point on route
        // TODO: Calculate deviation distance
        // TODO: Update remaining distance
        // TODO: Trigger haptic if off-route
    }
}

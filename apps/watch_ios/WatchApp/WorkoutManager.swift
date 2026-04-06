import Foundation
import HealthKit
import CoreLocation

/// Manages the HealthKit workout session and GPS tracking on Apple Watch.
class WorkoutManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var distanceMetres: Double = 0
    @Published var currentPace: Double? = nil
    @Published var heartRate: Double? = nil

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    var formattedElapsed: String {
        let minutes = Int(elapsedSeconds) / 60
        let seconds = Int(elapsedSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedDistance: String {
        String(format: "%.2f km", distanceMetres / 1000)
    }

    var formattedPace: String {
        guard let pace = currentPace, pace > 0 else { return "--:--" }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    func start() {
        // TODO: Request HealthKit authorization
        // TODO: Create and start HKWorkoutSession
        // TODO: Begin GPS location tracking
        isRecording = true
    }

    func stop() {
        // TODO: End workout session
        // TODO: Save HKWorkout
        // TODO: Transfer run data to iPhone via WCSession
        isRecording = false
    }
}

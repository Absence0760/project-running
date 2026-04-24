import Foundation
import CoreLocation

/// Manages run recording: timer, GPS tracking, distance and pace calculation.
class WorkoutManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State {
        case idle
        case recording
        case finished
    }

    @Published var state: State = .idle
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var distanceMetres: Double = 0
    @Published var currentPace: Double? = nil

    /// Raw GPS track recorded during the run.
    @Published var track: [CLLocation] = []

    /// The completed run data, available after stop().
    private(set) var finishedRun: FinishedRun?

    let healthKit = HealthKitManager()

    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var startDate: Date?

    struct FinishedRun {
        let id: String
        let startedAt: Date
        let durationSeconds: Int
        let distanceMetres: Double
        let track: [TrackPoint]
        let averageBPM: Double?
    }

    struct TrackPoint: Codable {
        let lat: Double
        let lng: Double
        let ele: Double?
        let ts: String?
    }

    /// Write the finished run's track to a JSON file in the app's caches
    /// directory and return the URL, suitable for `WCSession.transferFile`.
    /// The phone gzips + uploads to Supabase Storage on receipt.
    func writeTrackJSON() throws -> URL {
        guard let run = finishedRun else {
            throw NSError(domain: "WorkoutManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No finished run"])
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = caches.appendingPathComponent("\(run.id).json")
        try JSONEncoder().encode(run.track).write(to: url, options: .atomic)
        return url
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.allowsBackgroundLocationUpdates = true
    }

    // MARK: - Controls

    func start() {
        track = []
        distanceMetres = 0
        elapsedSeconds = 0
        currentPace = nil
        finishedRun = nil
        healthKit.reset()

        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        healthKit.startWorkout()

        startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let startDate = self.startDate else { return }
            self.elapsedSeconds = Date().timeIntervalSince(startDate)
        }

        state = .recording
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        healthKit.stopWorkout()

        let duration = Int(elapsedSeconds)
        let trackPoints = track.map { loc in
            TrackPoint(
                lat: loc.coordinate.latitude,
                lng: loc.coordinate.longitude,
                ele: loc.altitude > -999 ? loc.altitude : nil,
                ts: ISO8601DateFormatter().string(from: loc.timestamp)
            )
        }

        finishedRun = FinishedRun(
            id: UUID().uuidString.lowercased(),
            startedAt: startDate ?? Date(),
            durationSeconds: duration,
            distanceMetres: distanceMetres,
            track: trackPoints,
            averageBPM: healthKit.averageBPM
        )

        state = .finished
    }

    func reset() {
        track = []
        distanceMetres = 0
        elapsedSeconds = 0
        currentPace = nil
        finishedRun = nil
        state = .idle
    }

    // MARK: - Formatting

    var formattedElapsed: String {
        let h = Int(elapsedSeconds) / 3600
        let m = (Int(elapsedSeconds) % 3600) / 60
        let s = Int(elapsedSeconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
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

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            // Filter out inaccurate readings
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 30 else { continue }

            if let last = track.last {
                let delta = location.distance(from: last)
                // Ignore tiny movements (GPS jitter) and implausible jumps
                if delta > 2 && delta < 100 {
                    distanceMetres += delta
                }
            }

            track.append(location)
        }

        // Calculate current pace (seconds per km) from last ~200m
        updatePace()
    }

    private func updatePace() {
        let minPoints = 5
        guard track.count >= minPoints else { return }

        // Look back to find a segment of ~200m
        var segmentDistance: Double = 0
        var segmentStart = track.count - 1
        for i in stride(from: track.count - 2, through: 0, by: -1) {
            segmentDistance += track[i + 1].distance(from: track[i])
            segmentStart = i
            if segmentDistance >= 200 { break }
        }

        guard segmentDistance > 50 else { return }

        let segmentTime = track.last!.timestamp.timeIntervalSince(track[segmentStart].timestamp)
        guard segmentTime > 0 else { return }

        // seconds per km
        currentPace = (segmentTime / segmentDistance) * 1000
    }
}

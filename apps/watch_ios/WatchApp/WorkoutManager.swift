import Foundation
import CoreLocation
import WatchKit

/// Manages run recording: timer, GPS tracking, distance and pace calculation.
class WorkoutManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State {
        case idle
        case recovering
        case recording
        case paused
        case finished
    }

    @Published var state: State = .idle
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var distanceMetres: Double = 0
    @Published var currentPace: Double? = nil

    /// Raw GPS track recorded during the run.
    @Published var track: [CLLocation] = []

    /// The completed run data, available after stop() or recovery.
    var finishedRun: FinishedRun?

    let healthKit = HealthKitManager()

    var targetPaceSecondsPerKm: Double? = nil
    let paceToleranceSeconds: Double = 15

    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var checkpointTimer: Timer?
    private var startDate: Date?
    private var pausedAt: Date?
    private var totalPausedInterval: TimeInterval = 0
    private var lastTooFastHaptic: Date? = nil
    private var lastTooSlowHaptic: Date? = nil
    private var currentRunId: String?
    private var checkpointStore: CheckpointStore?
    private var writtenPointCount: Int = 0

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

    func checkForPendingRecovery() {
        guard CheckpointStore.peekCheckpoint() != nil else { return }
        state = .recovering
    }

    func start() {
        let runId = UUID().uuidString.lowercased()
        currentRunId = runId
        track = []
        distanceMetres = 0
        elapsedSeconds = 0
        currentPace = nil
        finishedRun = nil
        pausedAt = nil
        totalPausedInterval = 0
        writtenPointCount = 0
        lastTooFastHaptic = nil
        lastTooSlowHaptic = nil
        healthKit.reset()

        let store = CheckpointStore(runId: runId)
        checkpointStore = store

        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        healthKit.startWorkout()

        let start = Date()
        startDate = start
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let startDate = self.startDate else { return }
            guard self.state == .recording else { return }
            self.elapsedSeconds = Date().timeIntervalSince(startDate) - self.totalPausedInterval
        }

        checkpointTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.writeCheckpoint()
        }

        state = .recording
    }

    func pause() {
        guard state == .recording else { return }
        pausedAt = Date()
        locationManager.stopUpdatingLocation()
        healthKit.pauseSession()
        state = .paused
    }

    func resume() {
        guard state == .paused, let pausedAt else { return }
        totalPausedInterval += Date().timeIntervalSince(pausedAt)
        self.pausedAt = nil
        locationManager.startUpdatingLocation()
        healthKit.resumeSession()
        state = .recording
    }

    func stop() {
        if state == .paused, let pausedAt {
            totalPausedInterval += Date().timeIntervalSince(pausedAt)
            self.pausedAt = nil
        }
        checkpointTimer?.invalidate()
        checkpointTimer = nil
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        healthKit.stopWorkout()
        checkpointStore?.clear()
        checkpointStore = nil

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
        checkpointTimer?.invalidate()
        checkpointTimer = nil
        track = []
        distanceMetres = 0
        elapsedSeconds = 0
        currentPace = nil
        finishedRun = nil
        pausedAt = nil
        totalPausedInterval = 0
        writtenPointCount = 0
        lastTooFastHaptic = nil
        lastTooSlowHaptic = nil
        checkpointStore = nil
        currentRunId = nil
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
        var newPoints: [TrackPointRecord] = []
        for location in locations {
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 30 else { continue }

            if let last = track.last {
                let delta = location.distance(from: last)
                if delta > 2 && delta < 100 {
                    distanceMetres += delta
                }
            }

            track.append(location)
            newPoints.append(TrackPointRecord(
                lat: location.coordinate.latitude,
                lng: location.coordinate.longitude,
                ele: location.altitude > -999 ? location.altitude : nil,
                ts: ISO8601DateFormatter().string(from: location.timestamp)
            ))
        }

        if !newPoints.isEmpty {
            checkpointStore?.appendTrackPoints(newPoints)
        }

        updatePace()
    }

    private func writeCheckpoint() {
        guard let store = checkpointStore,
              let runId = currentRunId,
              let start = startDate else { return }
        let cp = RunCheckpoint(
            id: runId,
            startedAt: start,
            distanceMetres: distanceMetres,
            activeDurationSeconds: elapsedSeconds,
            pausedIntervalSeconds: totalPausedInterval,
            trackPointCount: track.count,
            cacheFileURL: store.trackFileURL
        )
        store.write(checkpoint: cp)
    }

    func recoverRun() -> FinishedRun? {
        guard let cp = CheckpointStore.peekCheckpoint() else { return nil }
        let store = CheckpointStore(runId: cp.id)
        let pts = store.loadTrackPoints()
        let trackPoints = pts.map { p in
            TrackPoint(lat: p.lat, lng: p.lng, ele: p.ele, ts: p.ts)
        }
        return FinishedRun(
            id: cp.id,
            startedAt: cp.startedAt,
            durationSeconds: Int(cp.activeDurationSeconds),
            distanceMetres: cp.distanceMetres,
            track: trackPoints,
            averageBPM: nil
        )
    }

    func clearRecovery() {
        CheckpointStore.clearStatic()
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
        let pace = (segmentTime / segmentDistance) * 1000
        currentPace = pace
        checkPaceAlert(pace: pace)
    }

    private func checkPaceAlert(pace: Double) {
        guard let target = targetPaceSecondsPerKm, distanceMetres > 200 else { return }
        let now = Date()
        let debounce: TimeInterval = 30
        if pace < target - paceToleranceSeconds {
            if lastTooFastHaptic.map({ now.timeIntervalSince($0) > debounce }) ?? true {
                WKInterfaceDevice.current().play(.notification)
                lastTooFastHaptic = now
            }
        } else if pace > target + paceToleranceSeconds {
            if lastTooSlowHaptic.map({ now.timeIntervalSince($0) > debounce }) ?? true {
                WKInterfaceDevice.current().play(.notification)
                lastTooSlowHaptic = now
            }
        }
    }
}

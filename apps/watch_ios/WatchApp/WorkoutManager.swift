import Foundation
import CoreLocation
import WatchKit
import WidgetKit

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

    /// Rolling window of the most recent GPS fixes, kept only to compute
    /// live pace and the per-fix distance delta. The full track is
    /// streamed to disk by `CheckpointStore`; holding the whole thing in
    /// memory would grow without bound on an all-day ultra (a 100-hour
    /// run at 1 Hz is ~360k points). Capped at `maxInMemoryTrackPoints`.
    @Published var track: [CLLocation] = []

    /// Authoritative count of every GPS fix recorded this run. Unlike
    /// `track.count` (now bounded), this never resets mid-run, so the UI
    /// and the crash checkpoint report the true number of points.
    @Published var trackPointCount: Int = 0

    /// Upper bound on the in-memory rolling window. 600 fixes comfortably
    /// covers the ~200 m pace look-back even at dense sampling, while
    /// keeping memory flat regardless of run length.
    private let maxInMemoryTrackPoints = 600

    /// The completed run data, available after stop() or recovery.
    var finishedRun: FinishedRun?

    let healthKit = HealthKitManager()

    var targetPaceSecondsPerKm: Double? = nil
    let paceToleranceSeconds: Double = 15

    private let locationManager = CLLocationManager()
    // Reused across every GPS fix — ISO8601DateFormatter is expensive to
    // construct (backing NSDateFormatter + ICU state), so allocating one per
    // point in the ~1 Hz didUpdateLocations callback churned the allocator on
    // the recording hot path over a long run. Mirrors CheckpointStore's static
    // encoder/decoder reuse; the serial CoreLocation delegate makes it safe.
    private let iso8601 = ISO8601DateFormatter()
    private var timer: Timer?
    private var checkpointTimer: Timer?
    private var startDate: Date?
    private var pausedAt: Date?
    private var totalPausedInterval: TimeInterval = 0
    private var lastTooFastHaptic: Date? = nil
    private var lastTooSlowHaptic: Date? = nil
    private var currentRunId: String?
    private var checkpointStore: CheckpointStore?

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
        // allowsBackgroundLocationUpdates is set in start(), not here:
        // CoreLocation traps (CLClientIsBackgroundable) if it's enabled before
        // the app is actually running a backgroundable session, which crashes
        // the app the instant WorkoutManager is constructed (e.g. the XCTest
        // host launch). Enable it only when we begin background updates.
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
        trackPointCount = 0
        distanceMetres = 0
        elapsedSeconds = 0
        currentPace = nil
        finishedRun = nil
        pausedAt = nil
        totalPausedInterval = 0
        lastTooFastHaptic = nil
        lastTooSlowHaptic = nil
        healthKit.reset()

        let store = CheckpointStore(runId: runId)
        checkpointStore = store

        locationManager.requestWhenInUseAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
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
        publishComplicationSnapshot()
    }

    func pause() {
        guard state == .recording else { return }
        // Capture the frozen state once, while still .recording, so a crash
        // during a long pause recovers the exact pause-boundary values. The
        // periodic timer then skips writes until resume (see writeCheckpoint).
        writeCheckpoint()
        pausedAt = Date()
        locationManager.stopUpdatingLocation()
        healthKit.pauseSession()
        state = .paused
        publishComplicationSnapshot()
    }

    func resume() {
        guard state == .paused, let pausedAt else { return }
        totalPausedInterval += Date().timeIntervalSince(pausedAt)
        self.pausedAt = nil
        locationManager.startUpdatingLocation()
        healthKit.resumeSession()
        state = .recording
        publishComplicationSnapshot()
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

        // The in-memory `track` is a bounded rolling window, so the full
        // run is read back from the streamed NDJSON file. Close the append
        // handle first to flush every fix to disk, read, then clear.
        let store = checkpointStore
        store?.closeAppendHandle()
        let trackPoints = (store?.loadTrackPoints() ?? []).map { p in
            TrackPoint(lat: p.lat, lng: p.lng, ele: p.ele, ts: p.ts)
        }
        store?.clear()
        checkpointStore = nil

        let duration = Int(elapsedSeconds)

        // One UUID per run: the finished run reuses the id assigned at
        // start() — the same id the checkpoint and the on-disk track file
        // are keyed under — instead of minting a fresh one here, which
        // previously orphaned the streamed track from the run row.
        finishedRun = FinishedRun(
            id: currentRunId ?? UUID().uuidString.lowercased(),
            startedAt: startDate ?? Date(),
            durationSeconds: duration,
            distanceMetres: distanceMetres,
            track: trackPoints,
            averageBPM: healthKit.averageBPM
        )

        state = .finished
        publishComplicationSnapshot()
    }

    func reset() {
        checkpointTimer?.invalidate()
        checkpointTimer = nil
        checkpointStore?.closeAppendHandle()
        track = []
        trackPointCount = 0
        distanceMetres = 0
        elapsedSeconds = 0
        currentPace = nil
        finishedRun = nil
        pausedAt = nil
        totalPausedInterval = 0
        lastTooFastHaptic = nil
        lastTooSlowHaptic = nil
        checkpointStore = nil
        currentRunId = nil
        state = .idle
        publishComplicationSnapshot()
    }

    /// Push the active-run snapshot to the App-Group container that
    /// the complication widget extension reads from. The widget
    /// extension lives in its own process and can't observe
    /// `@Published` properties directly, so this is the handoff
    /// point. After writing we also nudge `WidgetCenter` so the
    /// platform replaces the previous timeline immediately rather
    /// than waiting up to ~30 minutes for the next natural refresh.
    /// Called on every state transition (start / pause / resume /
    /// stop / reset) — see ActiveRunComplicationBundle for the
    /// reader side.
    private func publishComplicationSnapshot() {
        let isActive = state == .recording || state == .paused
        let snapshot = ActiveRunSnapshot(
            isActive: isActive,
            elapsedSeconds: Int(elapsedSeconds),
            distanceMeters: distanceMetres,
            paceSecPerKm: currentPace,
            lastUpdatedEpoch: Date().timeIntervalSince1970,
        )
        ActiveRunBridge.write(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: "ActiveRunComplication")
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
        RunFormat.distance(metres: distanceMetres, fractionDigits: 2)
    }

    var formattedPace: String {
        RunFormat.pace(secondsPerKm: currentPace)
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
                ts: iso8601.string(from: location.timestamp)
            ))
        }

        if !newPoints.isEmpty {
            checkpointStore?.appendTrackPoints(newPoints)
            trackPointCount += newPoints.count
        }

        // Keep the in-memory window bounded — the full track lives on disk.
        if track.count > maxInMemoryTrackPoints {
            track.removeFirst(track.count - maxInMemoryTrackPoints)
        }

        updatePace()
    }

    private func writeCheckpoint() {
        // While paused nothing in the checkpoint changes — distance and the
        // active-duration clock are both frozen — so the 15s timer would
        // re-write (and fsync) identical bytes every tick across a long
        // pause. The pause boundary is captured once by pause() before the
        // state flips; skip the no-op churn until recording resumes.
        guard state == .recording else { return }
        guard let store = checkpointStore,
              let runId = currentRunId,
              let start = startDate else { return }
        let cp = RunCheckpoint(
            id: runId,
            startedAt: start,
            distanceMetres: distanceMetres,
            activeDurationSeconds: elapsedSeconds,
            pausedIntervalSeconds: totalPausedInterval,
            trackPointCount: trackPointCount,
            cacheFileURL: store.trackFileURL,
            averageBPM: healthKit.averageBPM
        )
        store.write(checkpoint: cp)
        // Match the track's crash-durability window to the checkpoint's.
        store.syncTrack()
    }

    func recoverRun() -> FinishedRun? {
        guard let cp = CheckpointStore.peekCheckpoint() else { return nil }
        let store = CheckpointStore(runId: cp.id)
        let pts = store.loadTrackPoints()
        let trackPoints = pts.map { p in
            TrackPoint(lat: p.lat, lng: p.lng, ele: p.ele, ts: p.ts)
        }
        trackPointCount = trackPoints.count
        return FinishedRun(
            id: cp.id,
            startedAt: cp.startedAt,
            durationSeconds: Int(cp.activeDurationSeconds),
            distanceMetres: cp.distanceMetres,
            track: trackPoints,
            // Restored from the checkpoint so a recovered run keeps its
            // heart-rate summary instead of dropping to "— bpm".
            averageBPM: cp.averageBPM
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

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

    /// Off-route guidance for the route the phone armed, or nil when this run
    /// is unguided. Built once at `start()` and fed from the GPS stream as an
    /// auxiliary (L4) effect — see `didUpdateLocations`.
    @Published var routeNavigator: RouteNavigator?

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
    // Reference fix for the per-update distance delta, kept SEPARATE from the
    // bounded `track` window. Cleared on resume() so the first fix after a
    // pause establishes a fresh reference: without this, distance() would be
    // measured against the pre-pause fix (minutes and any aid-station wander
    // ago) and that stale gap misattributed as post-resume distance. Mirrors
    // Wear OS's `lastLocation = null` on resume.
    var lastLocationForDistance: CLLocation?

    struct FinishedRun {
        let id: String
        let startedAt: Date
        let durationSeconds: Int
        let distanceMetres: Double
        /// The run's NDJSON track file. The trace is carried as a path, not
        /// as an array: a 100-hour ultra is ~360k points, and a resident
        /// array of them (plus the encode that follows) is what made the old
        /// finish path an OOM risk. Every consumer streams from here.
        let trackFileURL: URL
        let trackPointCount: Int
        let averageBPM: Double?
    }

    /// A track point in the wire shape the phone, web and mobile clients
    /// read — distinct from the on-disk `TrackPointRecord` only in that `ts`
    /// is nullable there. Produced one at a time by `writeTrackJSON()`.
    struct TrackPoint: Codable {
        let lat: Double
        let lng: Double
        let ele: Double?
        let ts: String?
    }

    /// Bytes buffered before `writeTrackJSON` flushes to the output handle.
    private static let trackJSONFlushBytes = 64 * 1024

    /// Write the finished run's track to a JSON file in the app's caches
    /// directory and return the URL, suitable for `WCSession.transferFile`.
    /// The phone gzips + uploads to Supabase Storage on receipt.
    ///
    /// Streams NDJSON line → wire point → output handle, so the peak is one
    /// buffer rather than the whole track plus its encoding. Assembled in a
    /// `.tmp` sibling and renamed, which keeps the all-or-nothing guarantee
    /// the previous `Data.write(options: .atomic)` gave.
    func writeTrackJSON() throws -> URL {
        guard let run = finishedRun else {
            throw NSError(domain: "WorkoutManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No finished run"])
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = caches.appendingPathComponent("\(run.id).json")
        let tmp = caches.appendingPathComponent("\(run.id).json.tmp")

        try? FileManager.default.removeItem(at: tmp)
        guard FileManager.default.createFile(atPath: tmp.path, contents: nil) else {
            throw NSError(
                domain: "WorkoutManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not create \(tmp.lastPathComponent)"]
            )
        }
        let out = try FileHandle(forWritingTo: tmp)
        let encoder = JSONEncoder()
        let comma = Data(",".utf8)
        var buffer = Data("[".utf8)
        var wroteAny = false
        var failure: Error?

        CheckpointStore.forEachTrackPoint(in: run.trackFileURL) { record in
            guard failure == nil else { return }
            let point = TrackPoint(lat: record.lat, lng: record.lng, ele: record.ele, ts: record.ts)
            guard let encoded = try? encoder.encode(point) else { return }
            if wroteAny { buffer.append(comma) }
            buffer.append(encoded)
            wroteAny = true
            guard buffer.count >= WorkoutManager.trackJSONFlushBytes else { return }
            do {
                try out.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            } catch {
                failure = error
            }
        }

        if failure == nil {
            do {
                buffer.append(Data("]".utf8))
                try out.write(contentsOf: buffer)
                try out.synchronize()
            } catch {
                failure = error
            }
        }
        try? out.close()

        if let failure {
            try? FileManager.default.removeItem(at: tmp)
            throw failure
        }
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: tmp, to: url)
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
        lastLocationForDistance = nil
        routeNavigator = ArmedRouteStore.load()
            .map { RouteNavigator(routePoints: $0.locations) }
        healthKit.reset()

        let store = CheckpointStore(runId: runId)
        checkpointStore = store
        CheckpointStore.purgeTrackFiles(except: store.trackFileURL)

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
        lastLocationForDistance = nil
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

        // The in-memory `track` is a bounded rolling window and the full run
        // stays on disk — nothing here materialises it. Close the append
        // handle so every fix is flushed, then hand the finished run the
        // file; `writeTrackJSON` streams from it at sync time.
        let store = checkpointStore
        store?.closeAppendHandle()
        // Only the metadata checkpoint is dropped: leaving it would offer
        // "Recover unsaved run?" for a run the user has just finished. The
        // NDJSON survives until reset(), because it IS the finished run's
        // payload.
        CheckpointStore.clearStatic()
        checkpointStore = nil

        let duration = Int(elapsedSeconds)

        // One UUID per run: the finished run reuses the id assigned at
        // start() — the same id the checkpoint and the on-disk track file
        // are keyed under — instead of minting a fresh one here, which
        // previously orphaned the streamed track from the run row.
        let runId = currentRunId ?? UUID().uuidString.lowercased()
        finishedRun = FinishedRun(
            id: runId,
            startedAt: startDate ?? Date(),
            durationSeconds: duration,
            distanceMetres: distanceMetres,
            trackFileURL: store?.trackFileURL ?? CheckpointStore.trackFile(runId: runId),
            trackPointCount: trackPointCount,
            averageBPM: healthKit.averageBPM
        )

        state = .finished
        publishComplicationSnapshot()
    }

    func reset() {
        checkpointTimer?.invalidate()
        checkpointTimer = nil
        checkpointStore?.closeAppendHandle()
        // The finished run's NDJSON is its payload and outlived stop(); back
        // at idle nothing can still want it.
        if let trackFileURL = finishedRun?.trackFileURL {
            try? FileManager.default.removeItem(at: trackFileURL)
        }
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
        lastLocationForDistance = nil
        routeNavigator = nil
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

    /// Metres to add to the running distance for one consecutive pair of fixes.
    /// The `2..<100 m` band rejects stationary GPS jitter (<2 m) and physically
    /// impossible jumps (>=100 m, e.g. a reacquisition teleport); anything
    /// outside contributes zero. Pure so the pause->wander->resume behaviour
    /// can be unit-tested without a live `CLLocationManager`.
    static func distanceDelta(from: CLLocation, to: CLLocation) -> Double {
        let delta = to.distance(from: from)
        return (delta > 2 && delta < 100) ? delta : 0
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        var newPoints: [TrackPointRecord] = []
        var lastAcceptedFix: CLLocation?
        for location in locations {
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 30 else { continue }

            if let last = lastLocationForDistance {
                distanceMetres += Self.distanceDelta(from: last, to: location)
            }
            lastLocationForDistance = location
            lastAcceptedFix = location

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

        // Route guidance runs last, after the distance, the on-disk track and
        // the pace have all been committed — an auxiliary L4 effect that a
        // core L1 recording step never waits on and never shares state with,
        // so a route with no usable geometry costs the run nothing.
        if let navigator = routeNavigator, let fix = lastAcceptedFix {
            navigator.update(currentLocation: fix)
        }
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
        // Counted off the file rather than taken from `cp.trackPointCount`:
        // fixes appended since the last 15 s checkpoint are on disk but not
        // in the checkpoint's own figure.
        let count = store.countTrackPoints()
        trackPointCount = count
        return FinishedRun(
            id: cp.id,
            startedAt: cp.startedAt,
            durationSeconds: Int(cp.activeDurationSeconds),
            distanceMetres: cp.distanceMetres,
            trackFileURL: store.trackFileURL,
            trackPointCount: count,
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

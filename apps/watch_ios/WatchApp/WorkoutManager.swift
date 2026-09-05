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

    /// The armed route as the mini-map draws it, empty for an unguided run.
    /// Held apart from `routeNavigator`, which consumes the line and publishes
    /// only its projection of the current fix.
    @Published var mapRoute: [MiniMapPoint] = []

    /// The mini-map's own bounded breadcrumb of the run — see `MiniMapTrail`
    /// for why the map cannot be fed from `track`.
    @Published var mapTrail = MiniMapTrail()

    /// The last accepted fix, or nil while this run has none.
    @Published var mapPosition: MiniMapPoint?

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
        /// The share of the run's active time the heart-rate sensor was
        /// delivering, or nil when nothing measured it. Taken from the SAME
        /// `heartRateClaim` call as `averageBPM` — the two are one statement
        /// about one run, and grading twice could publish a coverage that
        /// contradicts the average it suppressed.
        let hrCoverage: Double?
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

    /// Write the finished run's track to a JSON file in the durable payload
    /// directory and return the URL, suitable for `WCSession.transferFile`.
    /// The phone gzips + uploads to Supabase Storage on receipt.
    ///
    /// Durable rather than `Caches` because `WCSession` reads this file off
    /// disk for as long as the transfer is outstanding — which can be days
    /// with the phone switched off — and by then `reset()` has deleted the
    /// NDJSON it was built from, so a purge here loses the run.
    ///
    /// Streams NDJSON line → wire point → output handle, so the peak is one
    /// buffer rather than the whole track plus its encoding. Assembled in a
    /// `.tmp` sibling and renamed, which keeps the all-or-nothing guarantee
    /// the previous `Data.write(options: .atomic)` gave.
    func writeTrackJSON() throws -> URL {
        guard let run = finishedRun else {
            throw NSError(domain: "WorkoutManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No finished run"])
        }
        let dir = RunPayloadStorage.directory
        RunPayloadStorage.createDirectory(at: dir)
        let url = dir.appendingPathComponent("\(run.id).json")
        let tmp = dir.appendingPathComponent("\(run.id).json.tmp")

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
        // Before anything reads a payload: create the durable directory and
        // carry across whatever an older build left in Caches, so an upgrade
        // over an install with an unsynced run does not orphan it.
        RunPayloadStorage.prepare()
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
        let armedRoute = ArmedRouteStore.load()
        routeNavigator = armedRoute.map { RouteNavigator(routePoints: $0.locations) }
        mapRoute = armedRoute?.coordinates.map {
            MiniMapPoint(latitude: $0.latitude, longitude: $0.longitude)
        } ?? []
        mapTrail.reset()
        mapPosition = nil
        healthKit.reset()

        let store = CheckpointStore(runId: runId)
        checkpointStore = store
        CheckpointStore.purgeTrackFiles(except: store.trackFileURL)
        RunPayloadStorage.sweepStaleExports(
            pending: WatchConnectivityManager.shared.pendingTransferURLs()
        )

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
            // Heart-rate coverage advances on THIS clock, not on HealthKit's
            // deliveries: the gap it measures is a stream that has gone quiet,
            // and a quiet stream emits nothing to hang the measurement on.
            // Inside the `.recording` guard, so a pause neither credits
            // coverage nor charges the run for it (decisions § 1156).
            self.healthKit.advanceCoverage(activeElapsedSeconds: self.elapsedSeconds)
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
        sealPaceWindow()
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
        // Graded, never the raw mean: a mean taken over less of the run than
        // not is not the run's average, and every reader of `avg_bpm` treats
        // it as though it were (decisions § 1083). Taken once — the claim's
        // two halves have to describe the same grading or the row can say the
        // sensor covered a third of the run while carrying that third's mean
        // as the run's average.
        let claim = healthKit.heartRateClaim(activeElapsedSeconds: elapsedSeconds)
        finishedRun = FinishedRun(
            id: runId,
            startedAt: startDate ?? Date(),
            durationSeconds: duration,
            distanceMetres: distanceMetres,
            trackFileURL: store?.trackFileURL ?? CheckpointStore.trackFile(runId: runId),
            trackPointCount: trackPointCount,
            averageBPM: claim.averageBPM,
            hrCoverage: claim.coverage
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
        mapRoute = []
        mapTrail.reset()
        mapPosition = nil
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
        WidgetCenter.shared.reloadTimelines(ofKind: ActiveRunBridge.complicationKind)
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
    /// Drop the pace look-back so it cannot span a discontinuity.
    ///
    /// `updatePace` walks `track` backwards until 200 m accumulate and divides
    /// by the timestamp span, so any gap the distance accumulator refused to
    /// credit would be timed against metres it never counted. Two places create
    /// that gap and BOTH must seal: a pause (a 20-minute aid-station stop read
    /// 1:48:35 /km and fired a false "too slow" alert — issue #371's defect,
    /// fixed for distance and never applied to pace), and the re-anchor escape
    /// below, where dropped fixes mean the same thing. The canonical Flutter
    /// recorder seals `_paceFloorIdx` at both, noting that the error "runs in
    /// the direction that SUPPRESSES a safety warning".
    ///
    /// Clearing `track` loses nothing: it is a bounded in-memory window used
    /// only for pace and the per-fix delta — the trace itself streams to disk.
    private func sealPaceWindow() {
        track.removeAll(keepingCapacity: true)
        currentPace = nil
    }

    /// Rebase the distance anchor once a genuine interval has passed without
    /// an accepted fix, WITHOUT crediting the un-sampled gap. Mirrors the
    /// Flutter recorder's `_gpsReanchorAfterSeconds`.
    static let gpsReanchorSeconds: TimeInterval = 10

    /// Monotonic stamp of the last accepted/rebased anchor. See the re-anchor
    /// escape in didUpdateLocations.
    private var lastAnchorUptime: TimeInterval = 0

    static func distanceDelta(from: CLLocation, to: CLLocation) -> Double {
        let delta = to.distance(from: from)
        return (delta > 2 && delta < 100) ? delta : 0
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        var newPoints: [TrackPointRecord] = []
        var lastAcceptedFix: CLLocation?
        for location in locations {
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 30 else { continue }

            // The anchor advances ONLY on an accepted delta, or after a real
            // gap. Advancing it after a REJECTED sub-2 m hop discards that
            // ground for good: at a 1 Hz fix rate a walker at 1.4 m/s produces
            // ~1.4 m per fix, every one under the floor, so a long hike accrued
            // 0.00 km. Holding the anchor is what lets two such fixes sum past
            // the floor and count. The canonical Flutter recorder assigns its
            // anchor inside the accepted branch for this reason, with the same
            // re-anchor escape so a >100 m hop after dropped fixes cannot
            // freeze the anchor for the rest of the run instead.
            let nowUptime = ProcessInfo.processInfo.systemUptime
            if let last = lastLocationForDistance {
                let delta = Self.distanceDelta(from: last, to: location)
                let rawMetres = location.distance(from: last)
                if delta > 0 {
                    distanceMetres += delta
                    lastLocationForDistance = location
                    lastAnchorUptime = nowUptime
                } else if rawMetres >= 100,
                          nowUptime - lastAnchorUptime >= Self.gpsReanchorSeconds {
                    // Over-ceiling ONLY, and on a MONOTONIC clock.
                    //
                    // The escape exists for the >100 m case: fixes were dropped,
                    // the runner really moved, and a fixed cap never scales — so
                    // without it the stale anchor only recedes and distance
                    // freezes for the rest of the run (#330). It must NOT fire
                    // for a sub-2 m hop: that ground is DEFERRED, and discarding
                    // the deferral is the 0.00 km bug this branch shipped
                    // alongside. The firmware re-anchors inside its
                    // over-ceiling branch only and holds the anchor below the
                    // floor; this now matches.
                    //
                    // systemUptime, not the fix's own Date: a wall clock can
                    // step backwards on an NTP sync, and a negative delta means
                    // the escape never fires — freezing distance exactly the way
                    // the escape exists to prevent.
                    //
                    // Rebasing without crediting the gap's metres is the SAME
                    // discontinuity a pause creates, so it seals the pace window
                    // too — the canonical Flutter recorder does both.
                    lastLocationForDistance = location
                    lastAnchorUptime = nowUptime
                    sealPaceWindow()
                }
            } else {
                lastLocationForDistance = location
                lastAnchorUptime = nowUptime
            }
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

        // The mini-map is the last auxiliary read, and a read only: pure value
        // maths over points the steps above have already committed, with no
        // framework call to fail and nothing the recording stack waits on.
        for record in newPoints {
            mapTrail.append(MiniMapPoint(latitude: record.lat, longitude: record.lng))
        }
        if let fix = lastAcceptedFix {
            mapPosition = MiniMapPoint(
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude
            )
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
        // Graded against coverage SO FAR, on the same clock the checkpoint
        // stamps its own duration from — so a crash-recovered run carries the
        // claim it would have carried had it been stopped here, rather than an
        // ungraded mean the recovery path has no way to grade.
        let claim = healthKit.heartRateClaim(activeElapsedSeconds: elapsedSeconds)
        let cp = RunCheckpoint(
            id: runId,
            startedAt: start,
            distanceMetres: distanceMetres,
            activeDurationSeconds: elapsedSeconds,
            pausedIntervalSeconds: totalPausedInterval,
            trackPointCount: trackPointCount,
            cacheFileURL: store.trackFileURL,
            averageBPM: claim.averageBPM,
            hrCoverage: claim.coverage
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
            averageBPM: cp.averageBPM,
            // A checkpoint from a build that never carried the field decodes
            // as nil, and nil rides through to the row as an OMITTED key —
            // never as a zero, which would claim the sensor delivered nothing.
            hrCoverage: cp.hrCoverage
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

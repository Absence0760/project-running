import Foundation

struct RunCheckpoint: Codable {
    /// On-disk schema version. Bumped whenever a field is added/changed in
    /// a way a reader must branch on. A checkpoint written before this
    /// field existed decodes as `1` (see the custom `init(from:)`), so a
    /// build upgrade mid-run never throws on the older shape.
    static let currentVersion = 1

    let version: Int
    let id: String
    let startedAt: Date
    let distanceMetres: Double
    let activeDurationSeconds: Double
    let pausedIntervalSeconds: Double
    let trackPointCount: Int
    let cacheFileURL: URL
    // Added after v1: the rolling HR average at checkpoint time so a
    // crash-recovered run keeps its heart-rate summary instead of
    // surfacing "— bpm" (the recovery path used to hardcode nil). Optional
    // so a checkpoint written by an older build — no `averageBPM` key —
    // still decodes: a synthesised Codable treats an absent key for an
    // Optional as nil, which is exactly the recover-an-in-flight-run-
    // after-app-upgrade path we must not break.
    let averageBPM: Double?

    init(
        id: String,
        startedAt: Date,
        distanceMetres: Double,
        activeDurationSeconds: Double,
        pausedIntervalSeconds: Double,
        trackPointCount: Int,
        cacheFileURL: URL,
        averageBPM: Double?,
        version: Int = RunCheckpoint.currentVersion
    ) {
        self.version = version
        self.id = id
        self.startedAt = startedAt
        self.distanceMetres = distanceMetres
        self.activeDurationSeconds = activeDurationSeconds
        self.pausedIntervalSeconds = pausedIntervalSeconds
        self.trackPointCount = trackPointCount
        self.cacheFileURL = cacheFileURL
        self.averageBPM = averageBPM
    }

    /// Every field is decoded with a fallback default rather than the
    /// synthesised all-or-nothing decode, so a checkpoint written by a
    /// *different* build (an older shape after an app upgrade, or a newer
    /// shape after a downgrade) still recovers as much of the in-flight run
    /// as it can instead of throwing and dropping the whole recovery. The
    /// only field with no safe default is `cacheFileURL`, which recovery
    /// doesn't actually consult — it rebuilds the track path from `id`
    /// (see `WorkoutManager.recoverRun`) — so a placeholder is harmless.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        distanceMetres = try c.decodeIfPresent(Double.self, forKey: .distanceMetres) ?? 0
        activeDurationSeconds = try c.decodeIfPresent(Double.self, forKey: .activeDurationSeconds) ?? 0
        pausedIntervalSeconds = try c.decodeIfPresent(Double.self, forKey: .pausedIntervalSeconds) ?? 0
        trackPointCount = try c.decodeIfPresent(Int.self, forKey: .trackPointCount) ?? 0
        cacheFileURL = try c.decodeIfPresent(URL.self, forKey: .cacheFileURL)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        averageBPM = try c.decodeIfPresent(Double.self, forKey: .averageBPM)
    }
}

class CheckpointStore {
    private static let defaultsKey = "run_checkpoint"
    private static let decoder = JSONDecoder()
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// fsync backstop. The 15s metadata checkpoint also forces a track
    /// fsync (see `WorkoutManager.writeCheckpoint`), so the crash-
    /// durability window is ~15s regardless; this bounds it further
    /// between checkpoints on a fast-sampling device.
    private static let fsyncEvery = 32

    let trackFileURL: URL

    /// Held open for the lifetime of the run. Appending through one
    /// long-lived handle (rather than re-opening per GPS batch) is what
    /// keeps a 100-hour ultra from paying an open/seek/close on every
    /// fix.
    private var appendHandle: FileHandle?
    private var pointsSinceSync = 0

    init(runId: String) {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("run_checkpoint", isDirectory: true)
        // A failure here means every subsequent track append silently drops
        // (the file can't be created), so surface it rather than swallowing
        // with `try?` — matches the logging in `appendTrackPoints`.
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
            print("CheckpointStore: failed to create checkpoint dir \(dir.path): \(error)")
            #endif
        }
        trackFileURL = dir.appendingPathComponent("\(runId).ndjson")
    }

    func write(checkpoint: RunCheckpoint) {
        guard let data = try? Self.encoder.encode(checkpoint) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    /// Append GPS points as newline-delimited JSON. Each point is one
    /// self-contained line, so a crash mid-write can only ever truncate
    /// the final partial line — which `loadTrackPoints` skips — and never
    /// corrupt an already-written point. Wrapped so a transient I/O
    /// failure degrades to "this batch isn't persisted" rather than
    /// killing the recording (layered-resilience: a checkpoint-write
    /// failure must not cancel the core distance/clock loop).
    func appendTrackPoints(_ points: [TrackPointRecord]) {
        guard !points.isEmpty else { return }
        do {
            let handle = try openHandle()
            var buffer = Data()
            for p in points {
                if let d = try? Self.encoder.encode(p) {
                    buffer.append(d)
                    buffer.append(0x0A)
                }
            }
            try handle.write(contentsOf: buffer)
            pointsSinceSync += points.count
            if pointsSinceSync >= Self.fsyncEvery {
                try handle.synchronize()
                pointsSinceSync = 0
            }
        } catch {
            // Drop the handle so the next batch re-opens cleanly.
            appendHandle = nil
            #if DEBUG
            print("CheckpointStore.appendTrackPoints failed: \(error)")
            #endif
        }
    }

    private func openHandle() throws -> FileHandle {
        if let handle = appendHandle { return handle }
        if !FileManager.default.fileExists(atPath: trackFileURL.path) {
            FileManager.default.createFile(atPath: trackFileURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: trackFileURL)
        try handle.seekToEnd()
        appendHandle = handle
        return handle
    }

    /// Force buffered track bytes to stable storage. Called from the 15s
    /// metadata checkpoint so the track's crash-durability window matches
    /// the checkpoint's.
    func syncTrack() {
        guard let handle = appendHandle else { return }
        try? handle.synchronize()
        pointsSinceSync = 0
    }

    /// Close the append handle, flushing to disk. Call before reading the
    /// track back at stop/finish so `loadTrackPoints` sees every appended
    /// point.
    func closeAppendHandle() {
        guard let handle = appendHandle else { return }
        try? handle.synchronize()
        try? handle.close()
        appendHandle = nil
        pointsSinceSync = 0
    }

    func loadCheckpoint() -> RunCheckpoint? {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else { return nil }
        Self.decoder.dateDecodingStrategy = .iso8601
        return try? Self.decoder.decode(RunCheckpoint.self, from: data)
    }

    func loadTrackPoints() -> [TrackPointRecord] {
        guard let raw = try? String(contentsOf: trackFileURL, encoding: .utf8) else { return [] }
        Self.decoder.dateDecodingStrategy = .iso8601
        return raw.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            try? Self.decoder.decode(TrackPointRecord.self, from: Data(line.utf8))
        }
    }

    func clear() {
        closeAppendHandle()
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        try? FileManager.default.removeItem(at: trackFileURL)
    }

    static func peekCheckpoint() -> RunCheckpoint? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RunCheckpoint.self, from: data)
    }

    static func clearStatic() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

struct TrackPointRecord: Codable {
    let lat: Double
    let lng: Double
    let ele: Double?
    let ts: String
}

import Foundation

struct RunCheckpoint: Codable {
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
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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

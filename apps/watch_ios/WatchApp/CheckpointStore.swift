import Foundation

struct RunCheckpoint: Codable {
    let id: String
    let startedAt: Date
    let distanceMetres: Double
    let activeDurationSeconds: Double
    let pausedIntervalSeconds: Double
    let trackPointCount: Int
    let cacheFileURL: URL
}

class CheckpointStore {
    private static let defaultsKey = "run_checkpoint"
    private static let decoder = JSONDecoder()
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    let trackFileURL: URL

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

    func appendTrackPoints(_ points: [TrackPointRecord]) {
        guard let handle = try? FileHandle(forWritingTo: trackFileURL) else {
            let lines = points.compactMap { p -> Data? in
                guard let d = try? Self.encoder.encode(p) else { return nil }
                return d + Data([0x0A])
            }
            try? lines.reduce(Data(), +).write(to: trackFileURL, options: .atomic)
            return
        }
        handle.seekToEndOfFile()
        for p in points {
            if let d = try? Self.encoder.encode(p) {
                handle.write(d + Data([0x0A]))
            }
        }
        handle.closeFile()
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

import XCTest
@testable import WatchApp

/// `WorkoutManager.writeTrackJSON()` serialises a finished run's track to a
/// file in Caches keyed by the run id — the exact file the watch hands to the
/// phone via `WCSession.transferFile`. The phone gzips + uploads it, so the
/// on-disk shape is a cross-device contract. Since the read path became
/// streaming, the source is the run's NDJSON file rather than an in-memory
/// array: these tests stage a real NDJSON track, set a synthetic
/// `finishedRun` pointing at it, and assert the written file (a) is named
/// `<run-id>.json`, (b) decodes back into the canonical track-point array —
/// including across the internal flush boundary a long run crosses — and
/// (c) the guard throws when there's no finished run.
///
/// Constructing `WorkoutManager` is cheap and side-effect-free until `start()`
/// — the embedded `CLLocationManager` is allocated but no authorization is
/// requested and no timers run — so this is safe in the test host.
final class WorkoutManagerTrackJSONTests: XCTestCase {

    private var stores: [CheckpointStore] = []

    override func tearDown() {
        for store in stores { store.clear() }
        stores = []
        super.tearDown()
    }

    /// Stage the run's NDJSON track and describe it as a finished run.
    private func makeRun(id: String, points: [TrackPointRecord]) -> WorkoutManager.FinishedRun {
        let store = CheckpointStore(runId: id)
        stores.append(store)
        store.appendTrackPoints(points)
        store.closeAppendHandle()
        return WorkoutManager.FinishedRun(
            id: id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 1800,
            distanceMetres: 5230.5,
            trackFileURL: store.trackFileURL,
            trackPointCount: points.count,
            averageBPM: 152
        )
    }

    func testWriteTrackJSONThrowsWithoutFinishedRun() {
        let wm = WorkoutManager()
        wm.finishedRun = nil
        XCTAssertThrowsError(try wm.writeTrackJSON()) { error in
            XCTAssertTrue("\(error)".contains("No finished run") || (error as NSError).code == 1)
        }
    }

    func testWriteTrackJSONNamesFileByRunId() throws {
        let id = "json-\(UUID().uuidString.lowercased())"
        let wm = WorkoutManager()
        wm.finishedRun = makeRun(id: id, points: [
            TrackPointRecord(lat: 51.4513, lng: -0.1962, ele: 12.0, ts: "2026-04-15T07:30:01Z"),
        ])
        let url = try wm.writeTrackJSON()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.lastPathComponent, "\(id).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path + ".tmp"),
            "The staging file must be renamed away, never left behind"
        )
    }

    func testWrittenFileDecodesToCanonicalTrack() throws {
        let id = "json-\(UUID().uuidString.lowercased())"
        let wm = WorkoutManager()
        wm.finishedRun = makeRun(id: id, points: [
            TrackPointRecord(lat: 51.4513, lng: -0.1962, ele: 12.0, ts: "2026-04-15T07:30:01Z"),
            TrackPointRecord(lat: 51.4514, lng: -0.1961, ele: nil, ts: "2026-04-15T07:30:11Z"),
        ])
        let url = try wm.writeTrackJSON()
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        let back = try JSONDecoder().decode([WorkoutManager.TrackPoint].self, from: data)
        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back[0].lat, 51.4513, accuracy: 0.00001)
        XCTAssertEqual(back[0].ele, 12.0)
        XCTAssertNil(back[1].ele, "nil elevation must survive the round-trip as null")
        XCTAssertEqual(back[1].ts, "2026-04-15T07:30:11Z")
    }

    func testEmptyTrackWritesValidEmptyArray() throws {
        // Indoor / no-GPS run: zero points must still produce a valid `[]`
        // file the phone can upload without special-casing.
        let id = "json-empty-\(UUID().uuidString.lowercased())"
        let wm = WorkoutManager()
        wm.finishedRun = makeRun(id: id, points: [])
        let url = try wm.writeTrackJSON()
        defer { try? FileManager.default.removeItem(at: url) }
        let back = try JSONDecoder().decode([WorkoutManager.TrackPoint].self, from: Data(contentsOf: url))
        XCTAssertEqual(back.count, 0)
    }

    func testLongTrackCrossesTheFlushBoundaryAndStaysValidJSON() throws {
        // The writer flushes its buffer every 64 KiB; a missing separator or
        // a dropped tail across a flush would produce a file the phone can't
        // decode at all. This track crosses the boundary several times.
        let count = 5_000
        let id = "json-long-\(UUID().uuidString.lowercased())"
        let wm = WorkoutManager()
        wm.finishedRun = makeRun(id: id, points: (0..<count).map { i in
            TrackPointRecord(
                lat: 51.0 + Double(i) / 100_000.0,
                lng: -0.1,
                ele: Double(i),
                ts: "2026-04-15T07:30:01Z"
            )
        })
        let url = try wm.writeTrackJSON()
        defer { try? FileManager.default.removeItem(at: url) }

        let back = try JSONDecoder().decode([WorkoutManager.TrackPoint].self, from: Data(contentsOf: url))
        XCTAssertEqual(back.count, count)
        XCTAssertEqual(back[0].ele, 0)
        XCTAssertEqual(back[count - 1].ele, Double(count - 1))
    }

    func testTruncatedNdjsonTailDoesNotPoisonTheWrittenArray() throws {
        // A crash-truncated final NDJSON line is skipped by the reader, so
        // the emitted array must still be well-formed rather than carrying a
        // half object the phone would reject.
        let id = "json-trunc-\(UUID().uuidString.lowercased())"
        let wm = WorkoutManager()
        let run = makeRun(id: id, points: [
            TrackPointRecord(lat: 1, lng: 1, ele: nil, ts: "2026-04-15T07:30:01Z"),
        ])
        wm.finishedRun = run
        let handle = try FileHandle(forWritingTo: run.trackFileURL)
        try handle.seekToEnd()
        handle.write(Data("{\"lat\":2.0,\"lng\":2".utf8))
        try handle.close()

        let url = try wm.writeTrackJSON()
        defer { try? FileManager.default.removeItem(at: url) }
        let back = try JSONDecoder().decode([WorkoutManager.TrackPoint].self, from: Data(contentsOf: url))
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].lat, 1, accuracy: 0.00001)
    }

    // MARK: - TrackPoint codec edge cases

    func testTrackPointNilTimestampAndElevation() throws {
        let p = WorkoutManager.TrackPoint(lat: 1, lng: 2, ele: nil, ts: nil)
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(WorkoutManager.TrackPoint.self, from: data)
        XCTAssertEqual(back.lat, 1, accuracy: 0.00001)
        XCTAssertEqual(back.lng, 2, accuracy: 0.00001)
        XCTAssertNil(back.ele)
        XCTAssertNil(back.ts)
    }

    func testTrackPointNegativeCoordinatesPreserved() throws {
        // Southern + western hemisphere — sign must not be dropped.
        let p = WorkoutManager.TrackPoint(lat: -33.8688, lng: -70.6693, ele: -5.0, ts: "2026-04-15T07:30:01Z")
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(WorkoutManager.TrackPoint.self, from: data)
        XCTAssertEqual(back.lat, -33.8688, accuracy: 0.00001)
        XCTAssertEqual(back.lng, -70.6693, accuracy: 0.00001)
        XCTAssertEqual(back.ele, -5.0)
    }
}

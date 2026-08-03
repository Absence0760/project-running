import XCTest
@testable import WatchApp

/// `CheckpointStore` streams GPS points to a per-run NDJSON file through one
/// long-lived `FileHandle`, one self-contained JSON object per line, and reads
/// them back the same way through `forEachTrackPoint`. The crash-durability
/// guarantee is: a crash mid-write can only ever truncate the final partial
/// line, which the reader skips, so at most the last in-flight point is lost.
/// These tests exercise the real file I/O against a throwaway runId in the
/// Caches dir and clear it afterwards. Mirrors the Wear OS twin's
/// `TrackWriterTest.kt`.
final class CheckpointStoreTrackTests: XCTestCase {
    private var runId: String = ""
    private var store: CheckpointStore!

    override func setUp() {
        super.setUp()
        runId = "test-\(UUID().uuidString.lowercased())"
        store = CheckpointStore(runId: runId)
    }

    override func tearDown() {
        store.clear()
        store = nil
        super.tearDown()
    }

    private func point(_ lat: Double, _ lng: Double, ele: Double? = nil, ts: String = "2026-04-15T07:30:00Z") -> TrackPointRecord {
        TrackPointRecord(lat: lat, lng: lng, ele: ele, ts: ts)
    }

    /// Collect the streamed points. Only the tests materialise a track; the
    /// production callers consume it a point at a time.
    private func collect(_ from: CheckpointStore? = nil) -> [TrackPointRecord] {
        var out: [TrackPointRecord] = []
        let target: CheckpointStore = from ?? store
        target.forEachTrackPoint { out.append($0) }
        return out
    }

    // MARK: - Round-trip

    func testAppendThenLoadRoundTrips() {
        let pts = [
            point(51.4513, -0.1962, ele: 12.0, ts: "2026-04-15T07:30:01Z"),
            point(51.4514, -0.1961, ele: 12.5, ts: "2026-04-15T07:30:11Z"),
            point(51.4516, -0.1957, ele: 13.0, ts: "2026-04-15T07:30:21Z"),
        ]
        store.appendTrackPoints(pts)
        store.closeAppendHandle()

        let loaded = collect()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded[0].lat, 51.4513, accuracy: 0.00001)
        XCTAssertEqual(loaded[0].lng, -0.1962, accuracy: 0.00001)
        XCTAssertEqual(loaded[0].ele, 12.0)
        XCTAssertEqual(loaded[0].ts, "2026-04-15T07:30:01Z")
        XCTAssertEqual(loaded[2].lat, 51.4516, accuracy: 0.00001)
    }

    func testMultipleAppendBatchesAccumulate() {
        store.appendTrackPoints([point(1, 1), point(2, 2)])
        store.appendTrackPoints([point(3, 3)])
        store.appendTrackPoints([point(4, 4), point(5, 5)])
        store.closeAppendHandle()
        XCTAssertEqual(collect().count, 5)
        XCTAssertEqual(store.countTrackPoints(), 5)
    }

    func testEmptyBatchIsNoOp() {
        store.appendTrackPoints([])
        store.closeAppendHandle()
        XCTAssertEqual(collect().count, 0)
    }

    func testNilElevationOmittedAndDecodesNil() {
        store.appendTrackPoints([point(51.0, -0.1, ele: nil)])
        store.closeAppendHandle()
        let loaded = collect()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(loaded[0].ele)
    }

    // MARK: - Streaming across read-chunk boundaries

    func testLongTrackSurvivesEveryChunkBoundary() {
        // The reader pulls 64 KiB at a time, so a track this size straddles
        // several boundaries and lines land mid-chunk. Every point must come
        // back, in order — a dropped carry would silently truncate an ultra's
        // track at the first boundary.
        let count = 5_000
        let pts = (0..<count).map { i in
            point(51.0 + Double(i) / 100_000.0, -0.1 - Double(i) / 100_000.0, ele: Double(i))
        }
        store.appendTrackPoints(pts)
        store.closeAppendHandle()

        let loaded = collect()
        XCTAssertEqual(loaded.count, count)
        XCTAssertEqual(loaded[0].ele, 0)
        XCTAssertEqual(loaded[count - 1].ele, Double(count - 1))
        XCTAssertEqual(
            loaded[count - 1].lat,
            51.0 + Double(count - 1) / 100_000.0,
            accuracy: 0.0000001
        )
        XCTAssertEqual(store.countTrackPoints(), count)
    }

    // MARK: - Crash-truncation tolerance

    func testTruncatedFinalLineIsSkipped() throws {
        // Simulate a crash mid-write: a valid line, then a half-written one
        // with no trailing newline. The reader must yield the good point
        // and silently drop the corrupt tail.
        store.appendTrackPoints([point(51.4513, -0.1962, ele: 12.0)])
        store.closeAppendHandle()

        let handle = try FileHandle(forWritingTo: store.trackFileURL)
        try handle.seekToEnd()
        handle.write(Data("{\"lat\":51.4514,\"lng\":-0.196".utf8)) // truncated, no newline
        try handle.close()

        let loaded = collect()
        XCTAssertEqual(loaded.count, 1, "Truncated final line must be skipped, the good point kept")
        XCTAssertEqual(loaded[0].lat, 51.4513, accuracy: 0.00001)
    }

    func testCompleteFinalLineWithoutNewlineIsKept() throws {
        // The mirror case: the crash landed between the object and its
        // newline. That line is whole, so it must NOT be dropped along with
        // the genuinely truncated ones.
        store.appendTrackPoints([point(1, 1)])
        store.closeAppendHandle()

        let handle = try FileHandle(forWritingTo: store.trackFileURL)
        try handle.seekToEnd()
        handle.write(Data("{\"lat\":9.0,\"lng\":9.0,\"ts\":\"2026-04-15T07:30:00Z\"}".utf8))
        try handle.close()

        let loaded = collect()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[1].lat, 9.0, accuracy: 0.00001)
    }

    func testGarbageLineInMiddleIsSkippedRestKept() throws {
        store.appendTrackPoints([point(1, 1)])
        store.closeAppendHandle()
        // Inject a non-JSON line then a valid one.
        let handle = try FileHandle(forWritingTo: store.trackFileURL)
        try handle.seekToEnd()
        handle.write(Data("not json at all\n".utf8))
        handle.write(Data("{\"lat\":3.0,\"lng\":3.0,\"ele\":null,\"ts\":\"2026-04-15T07:30:00Z\"}\n".utf8))
        try handle.close()

        let loaded = collect()
        XCTAssertEqual(loaded.count, 2, "Garbage line skipped, both valid points kept")
        XCTAssertEqual(loaded[0].lat, 1.0, accuracy: 0.00001)
        XCTAssertEqual(loaded[1].lat, 3.0, accuracy: 0.00001)
    }

    func testLoadMissingFileReturnsEmpty() {
        // Fresh store, nothing appended — no file yet.
        let fresh = CheckpointStore(runId: "test-missing-\(UUID().uuidString)")
        XCTAssertEqual(collect(fresh).count, 0)
        XCTAssertEqual(fresh.countTrackPoints(), 0)
        fresh.clear()
    }

    // MARK: - File paths and lifetime

    func testTrackFileStaticMatchesTheInstancePath() {
        XCTAssertEqual(CheckpointStore.trackFile(runId: runId), store.trackFileURL)
    }

    func testClearRemovesTrackFile() {
        store.appendTrackPoints([point(1, 1)])
        store.closeAppendHandle()
        XCTAssertEqual(collect().count, 1)
        store.clear()
        XCTAssertEqual(collect().count, 0, "After clear the NDJSON file must be gone")
    }

    func testPurgeRemovesOtherRunsButKeepsTheCurrentOne() {
        // The NDJSON now outlives the UserDefaults checkpoint, so a discarded
        // recovery can strand one. Starting a run sweeps the rest.
        let stale = CheckpointStore(runId: "test-stale-\(UUID().uuidString.lowercased())")
        stale.appendTrackPoints([point(1, 1)])
        stale.closeAppendHandle()
        store.appendTrackPoints([point(2, 2)])
        store.closeAppendHandle()

        CheckpointStore.purgeTrackFiles(except: store.trackFileURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.trackFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.trackFileURL.path))
        XCTAssertEqual(collect().count, 1)
    }

    // MARK: - Metadata checkpoint via UserDefaults

    func testWriteAndPeekCheckpointRoundTrips() {
        let cp = RunCheckpoint(
            id: runId,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            distanceMetres: 4200,
            activeDurationSeconds: 1500,
            pausedIntervalSeconds: 30,
            trackPointCount: 200,
            cacheFileURL: store.trackFileURL,
            averageBPM: 150
        )
        store.write(checkpoint: cp)
        defer { CheckpointStore.clearStatic() }

        let peeked = CheckpointStore.peekCheckpoint()
        XCTAssertNotNil(peeked)
        XCTAssertEqual(peeked?.id, runId)
        XCTAssertEqual(peeked?.distanceMetres ?? -1, 4200, accuracy: 0.0001)
        XCTAssertEqual(peeked?.averageBPM, 150)
    }

    func testClearStaticRemovesCheckpoint() {
        let cp = RunCheckpoint(
            id: runId, startedAt: Date(), distanceMetres: 1, activeDurationSeconds: 1,
            pausedIntervalSeconds: 0, trackPointCount: 1, cacheFileURL: store.trackFileURL, averageBPM: nil
        )
        store.write(checkpoint: cp)
        XCTAssertNotNil(CheckpointStore.peekCheckpoint())
        CheckpointStore.clearStatic()
        XCTAssertNil(CheckpointStore.peekCheckpoint())
    }

    func testClearStaticLeavesTheTrackFileInPlace() {
        // What `stop()` now does: drop the recovery prompt, keep the payload.
        store.appendTrackPoints([point(1, 1)])
        store.closeAppendHandle()
        store.write(checkpoint: RunCheckpoint(
            id: runId, startedAt: Date(), distanceMetres: 1, activeDurationSeconds: 1,
            pausedIntervalSeconds: 0, trackPointCount: 1, cacheFileURL: store.trackFileURL, averageBPM: nil
        ))
        CheckpointStore.clearStatic()
        XCTAssertNil(CheckpointStore.peekCheckpoint())
        XCTAssertEqual(collect().count, 1, "The finished run still needs its track")
    }
}

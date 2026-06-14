import XCTest
@testable import WatchApp

/// `CheckpointStore` streams GPS points to a per-run NDJSON file through one
/// long-lived `FileHandle`, one self-contained JSON object per line. The
/// crash-durability guarantee is: a crash mid-write can only ever truncate
/// the final partial line, which `loadTrackPoints` skips, so at most the last
/// in-flight point is lost. These tests exercise the real file I/O against a
/// throwaway runId in the Caches dir and clear it afterwards. Mirrors the
/// Wear OS twin's `TrackWriterTest.kt`.
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

    // MARK: - Round-trip

    func testAppendThenLoadRoundTrips() {
        let pts = [
            point(51.4513, -0.1962, ele: 12.0, ts: "2026-04-15T07:30:01Z"),
            point(51.4514, -0.1961, ele: 12.5, ts: "2026-04-15T07:30:11Z"),
            point(51.4516, -0.1957, ele: 13.0, ts: "2026-04-15T07:30:21Z"),
        ]
        store.appendTrackPoints(pts)
        store.closeAppendHandle()

        let loaded = store.loadTrackPoints()
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
        XCTAssertEqual(store.loadTrackPoints().count, 5)
    }

    func testEmptyBatchIsNoOp() {
        store.appendTrackPoints([])
        store.closeAppendHandle()
        XCTAssertEqual(store.loadTrackPoints().count, 0)
    }

    func testNilElevationOmittedAndDecodesNil() {
        store.appendTrackPoints([point(51.0, -0.1, ele: nil)])
        store.closeAppendHandle()
        let loaded = store.loadTrackPoints()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(loaded[0].ele)
    }

    // MARK: - Crash-truncation tolerance

    func testTruncatedFinalLineIsSkipped() throws {
        // Simulate a crash mid-write: a valid line, then a half-written one
        // with no trailing newline. The loader must return the good point
        // and silently drop the corrupt tail.
        store.appendTrackPoints([point(51.4513, -0.1962, ele: 12.0)])
        store.closeAppendHandle()

        let handle = try FileHandle(forWritingTo: store.trackFileURL)
        try handle.seekToEnd()
        handle.write(Data("{\"lat\":51.4514,\"lng\":-0.196".utf8)) // truncated, no newline
        try handle.close()

        let loaded = store.loadTrackPoints()
        XCTAssertEqual(loaded.count, 1, "Truncated final line must be skipped, the good point kept")
        XCTAssertEqual(loaded[0].lat, 51.4513, accuracy: 0.00001)
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

        let loaded = store.loadTrackPoints()
        XCTAssertEqual(loaded.count, 2, "Garbage line skipped, both valid points kept")
        XCTAssertEqual(loaded[0].lat, 1.0, accuracy: 0.00001)
        XCTAssertEqual(loaded[1].lat, 3.0, accuracy: 0.00001)
    }

    func testLoadMissingFileReturnsEmpty() {
        // Fresh store, nothing appended — no file yet.
        let fresh = CheckpointStore(runId: "test-missing-\(UUID().uuidString)")
        XCTAssertEqual(fresh.loadTrackPoints().count, 0)
        fresh.clear()
    }

    // MARK: - clear()

    func testClearRemovesTrackFile() {
        store.appendTrackPoints([point(1, 1)])
        store.closeAppendHandle()
        XCTAssertEqual(store.loadTrackPoints().count, 1)
        store.clear()
        XCTAssertEqual(store.loadTrackPoints().count, 0, "After clear the NDJSON file must be gone")
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
}

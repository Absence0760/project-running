import XCTest
@testable import WatchApp

/// Crash-recovery wiring and the elapsed-time formatter on `WorkoutManager`.
///
/// `recoverRun()` reconstructs a `FinishedRun` from a persisted checkpoint
/// (metadata in UserDefaults) plus the streamed NDJSON track file — it must
/// carry the SAME run id end-to-end (the id minted at start keys the
/// checkpoint, the track file, and the recovered run) and must restore the
/// average HR from the checkpoint rather than dropping it. `formattedElapsed`
/// is the watch's headline clock string; its h:mm:ss / mm:ss crossover is the
/// elapsed equivalent the Wear OS twin pins in `ElapsedMathTest.kt`.
final class WorkoutManagerRecoveryTests: XCTestCase {

    override func tearDown() {
        CheckpointStore.clearStatic()
        super.tearDown()
    }

    // MARK: - recoverRun()

    func testRecoverRunRebuildsFinishedRunFromCheckpointAndTrack() {
        let id = "recover-\(UUID().uuidString.lowercased())"
        let store = CheckpointStore(runId: id)
        store.appendTrackPoints([
            TrackPointRecord(lat: 51.4513, lng: -0.1962, ele: 12.0, ts: "2026-04-15T07:30:01Z"),
            TrackPointRecord(lat: 51.4514, lng: -0.1961, ele: 12.5, ts: "2026-04-15T07:30:11Z"),
        ])
        store.closeAppendHandle()
        store.write(checkpoint: RunCheckpoint(
            id: id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            distanceMetres: 4321.0,
            activeDurationSeconds: 1500,
            pausedIntervalSeconds: 60,
            trackPointCount: 2,
            cacheFileURL: store.trackFileURL,
            averageBPM: 148.0
        ))
        defer { store.clear() }

        let wm = WorkoutManager()
        let recovered = wm.recoverRun()
        XCTAssertNotNil(recovered)
        XCTAssertEqual(recovered?.id, id, "Recovered run must keep the checkpoint's id end-to-end")
        XCTAssertEqual(recovered?.distanceMetres ?? -1, 4321.0, accuracy: 0.0001)
        XCTAssertEqual(recovered?.durationSeconds, 1500)
        XCTAssertEqual(recovered?.track.count, 2)
        XCTAssertEqual(recovered?.averageBPM, 148.0, "avg HR must survive recovery, not drop to nil")
        XCTAssertEqual(wm.trackPointCount, 2, "trackPointCount is set from the recovered track")
    }

    func testRecoverRunReturnsNilWithNoCheckpoint() {
        CheckpointStore.clearStatic()
        let wm = WorkoutManager()
        XCTAssertNil(wm.recoverRun())
    }

    func testRecoverRunWithMissingHRDecodesNilBPM() {
        let id = "recover-nohr-\(UUID().uuidString.lowercased())"
        let store = CheckpointStore(runId: id)
        store.appendTrackPoints([TrackPointRecord(lat: 1, lng: 1, ele: nil, ts: "2026-04-15T07:30:01Z")])
        store.closeAppendHandle()
        store.write(checkpoint: RunCheckpoint(
            id: id, startedAt: Date(), distanceMetres: 100, activeDurationSeconds: 60,
            pausedIntervalSeconds: 0, trackPointCount: 1, cacheFileURL: store.trackFileURL, averageBPM: nil
        ))
        defer { store.clear() }

        let recovered = WorkoutManager().recoverRun()
        XCTAssertNotNil(recovered)
        XCTAssertNil(recovered?.averageBPM)
    }

    // MARK: - formattedElapsed

    func testFormattedElapsedUnderOneHourIsMMSS() {
        let wm = WorkoutManager()
        wm.elapsedSeconds = 0
        XCTAssertEqual(wm.formattedElapsed, "00:00")
        wm.elapsedSeconds = 42
        XCTAssertEqual(wm.formattedElapsed, "00:42")
        wm.elapsedSeconds = TimeInterval(12 * 60 + 34)
        XCTAssertEqual(wm.formattedElapsed, "12:34")
        wm.elapsedSeconds = TimeInterval(59 * 60 + 59)
        XCTAssertEqual(wm.formattedElapsed, "59:59")
    }

    func testFormattedElapsedAtAndOverOneHourIsHMMSS() {
        let wm = WorkoutManager()
        wm.elapsedSeconds = 3600
        XCTAssertEqual(wm.formattedElapsed, "1:00:00")
        wm.elapsedSeconds = TimeInterval(1 * 3600 + 23 * 60 + 45)
        XCTAssertEqual(wm.formattedElapsed, "1:23:45")
        wm.elapsedSeconds = TimeInterval(9 * 3600 + 59 * 60 + 59)
        XCTAssertEqual(wm.formattedElapsed, "9:59:59")
    }

    func testFormattedElapsedUltraLength() {
        let wm = WorkoutManager()
        // 27h 03m 07s ultra — must not wrap or overflow.
        wm.elapsedSeconds = TimeInterval(27 * 3600 + 3 * 60 + 7)
        XCTAssertEqual(wm.formattedElapsed, "27:03:07")
    }

    func testFormattedElapsedTruncatesFractionalSeconds() {
        let wm = WorkoutManager()
        // 90.9 s truncates (Int) to 90 -> 01:30, not rounds to 01:31.
        wm.elapsedSeconds = 90.9
        XCTAssertEqual(wm.formattedElapsed, "01:30")
    }
}

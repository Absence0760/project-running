import XCTest
@testable import WatchApp

/// `RunCheckpoint` is the 15s crash-recovery snapshot. Its hand-written
/// `init(from:)` decodes every field with a fallback default so a checkpoint
/// written by a *different* build (older shape after an app upgrade, newer
/// shape after a downgrade) still recovers the in-flight run instead of
/// throwing and dropping it entirely. These tests pin that
/// recover-across-build-skew contract — the whole reason the custom decoder
/// exists. Mirrors the Wear OS twin's `CheckpointSerializationTest.kt`.
final class RunCheckpointCodableTests: XCTestCase {

    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Full round-trip

    func testFullRoundTrip() throws {
        let cp = RunCheckpoint(
            id: "9c4dca1e-cf7a-4f12-9f19-e29c70bdf101",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            distanceMetres: 5230.5,
            activeDurationSeconds: 1800,
            pausedIntervalSeconds: 120,
            trackPointCount: 312,
            cacheFileURL: URL(fileURLWithPath: "/tmp/run.ndjson"),
            averageBPM: 152.0
        )
        let data = try encoder().encode(cp)
        let back = try decoder().decode(RunCheckpoint.self, from: data)
        XCTAssertEqual(back.version, RunCheckpoint.currentVersion)
        XCTAssertEqual(back.id, cp.id)
        XCTAssertEqual(back.startedAt.timeIntervalSince1970, cp.startedAt.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(back.distanceMetres, 5230.5, accuracy: 0.0001)
        XCTAssertEqual(back.activeDurationSeconds, 1800, accuracy: 0.0001)
        XCTAssertEqual(back.pausedIntervalSeconds, 120, accuracy: 0.0001)
        XCTAssertEqual(back.trackPointCount, 312)
        XCTAssertEqual(back.averageBPM, 152.0)
    }

    func testCurrentVersionIsOne() {
        XCTAssertEqual(RunCheckpoint.currentVersion, 1)
    }

    func testDefaultInitStampsCurrentVersion() {
        let cp = RunCheckpoint(
            id: "x", startedAt: Date(), distanceMetres: 0, activeDurationSeconds: 0,
            pausedIntervalSeconds: 0, trackPointCount: 0,
            cacheFileURL: URL(fileURLWithPath: "/tmp/x"), averageBPM: nil
        )
        XCTAssertEqual(cp.version, RunCheckpoint.currentVersion)
    }

    // MARK: - Forward/backward compat decode

    func testDecodesPreVersionCheckpointAsVersionOne() throws {
        // An older build wrote no `version` key — must decode as 1, not throw.
        let json = """
        {
          "id": "abc",
          "startedAt": "2026-04-15T07:30:00Z",
          "distanceMetres": 1000.0,
          "activeDurationSeconds": 600.0,
          "pausedIntervalSeconds": 0.0,
          "trackPointCount": 50,
          "cacheFileURL": "file:///tmp/abc.ndjson"
        }
        """.data(using: .utf8)!
        let cp = try decoder().decode(RunCheckpoint.self, from: json)
        XCTAssertEqual(cp.version, 1)
        XCTAssertEqual(cp.id, "abc")
        XCTAssertEqual(cp.distanceMetres, 1000.0, accuracy: 0.0001)
        XCTAssertNil(cp.averageBPM, "Absent averageBPM (older build) must decode as nil")
    }

    func testDecodesWithMissingAverageBPMKeepsRestOfRun() throws {
        let json = """
        {
          "version": 1,
          "id": "no-hr",
          "startedAt": "2026-04-15T07:30:00Z",
          "distanceMetres": 4200.0,
          "activeDurationSeconds": 1500.0,
          "pausedIntervalSeconds": 30.0,
          "trackPointCount": 200,
          "cacheFileURL": "file:///tmp/no-hr.ndjson"
        }
        """.data(using: .utf8)!
        let cp = try decoder().decode(RunCheckpoint.self, from: json)
        XCTAssertNil(cp.averageBPM)
        XCTAssertEqual(cp.distanceMetres, 4200.0, accuracy: 0.0001)
        XCTAssertEqual(cp.trackPointCount, 200)
    }

    func testDecodesAlmostEmptyObjectWithSafeDefaults() throws {
        // A truncated / partially-written checkpoint must not crash recovery:
        // every absent field falls back rather than throwing. The only field
        // with no safe default is cacheFileURL, which recovery rebuilds from
        // `id` anyway, so a placeholder is fine.
        let json = "{}".data(using: .utf8)!
        let cp = try decoder().decode(RunCheckpoint.self, from: json)
        XCTAssertEqual(cp.version, 1)
        XCTAssertEqual(cp.id, "")
        XCTAssertEqual(cp.distanceMetres, 0)
        XCTAssertEqual(cp.activeDurationSeconds, 0)
        XCTAssertEqual(cp.pausedIntervalSeconds, 0)
        XCTAssertEqual(cp.trackPointCount, 0)
        XCTAssertNil(cp.averageBPM)
    }

    func testDecodesNewerShapeWithUnknownFutureKeys() throws {
        // A downgrade: a newer build wrote extra keys this build doesn't know.
        // Unknown keys are ignored; the known ones decode normally.
        let json = """
        {
          "version": 2,
          "id": "future",
          "startedAt": "2026-04-15T07:30:00Z",
          "distanceMetres": 8000.0,
          "activeDurationSeconds": 2400.0,
          "pausedIntervalSeconds": 0.0,
          "trackPointCount": 400,
          "cacheFileURL": "file:///tmp/future.ndjson",
          "averageBPM": 161.0,
          "cadenceSpm": 178,
          "someFutureField": "ignored"
        }
        """.data(using: .utf8)!
        let cp = try decoder().decode(RunCheckpoint.self, from: json)
        XCTAssertEqual(cp.version, 2)
        XCTAssertEqual(cp.averageBPM, 161.0)
        XCTAssertEqual(cp.trackPointCount, 400)
    }
}

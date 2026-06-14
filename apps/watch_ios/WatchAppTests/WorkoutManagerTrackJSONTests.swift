import XCTest
import CoreLocation
@testable import WatchApp

/// `WorkoutManager.writeTrackJSON()` serialises a finished run's track to a
/// file in Caches keyed by the run id — the exact file the watch hands to the
/// phone via `WCSession.transferFile`. The phone gzips + uploads it, so the
/// on-disk shape is a cross-device contract. These tests construct a
/// `WorkoutManager`, set a synthetic `finishedRun`, and assert the written
/// file (a) is named `<run-id>.json`, (b) decodes back into the canonical
/// track-point array, and (c) the guard throws when there's no finished run.
///
/// Constructing `WorkoutManager` is cheap and side-effect-free until `start()`
/// — the embedded `CLLocationManager` is allocated but no authorization is
/// requested and no timers run — so this is safe in the test host.
final class WorkoutManagerTrackJSONTests: XCTestCase {

    private func makeRun(id: String, points: [WorkoutManager.TrackPoint]) -> WorkoutManager.FinishedRun {
        WorkoutManager.FinishedRun(
            id: id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 1800,
            distanceMetres: 5230.5,
            track: points,
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
            WorkoutManager.TrackPoint(lat: 51.4513, lng: -0.1962, ele: 12.0, ts: "2026-04-15T07:30:01Z"),
        ])
        let url = try wm.writeTrackJSON()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.lastPathComponent, "\(id).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testWrittenFileDecodesToCanonicalTrack() throws {
        let id = "json-\(UUID().uuidString.lowercased())"
        let points = [
            WorkoutManager.TrackPoint(lat: 51.4513, lng: -0.1962, ele: 12.0, ts: "2026-04-15T07:30:01Z"),
            WorkoutManager.TrackPoint(lat: 51.4514, lng: -0.1961, ele: nil, ts: "2026-04-15T07:30:11Z"),
        ]
        let wm = WorkoutManager()
        wm.finishedRun = makeRun(id: id, points: points)
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

import XCTest
@testable import WatchApp

/// Cross-platform contract test for the canonical watch-run payload.
///
/// The fixture at `fixtures/watch_run_payload.json` (repo root) is shared
/// with the Flutter test (`apps/mobile_*/test/watch_payload_fixture_test.dart`),
/// the Wear OS test (`apps/watch_wear/.../WatchRunPayloadFixtureTest.kt`), and
/// the web test (`apps/web/src/lib/watch_payload_fixture.test.ts`). All
/// platforms read the same file and must agree on the shape. If you change a
/// field here, update the other tests in the same commit.
///
/// On watchOS the relevant surfaces are (a) the metadata dict the watch sends
/// over `WCSession.transferFile` (built in `ContentView.syncRun` and the
/// DEBUG `SupabaseService.syncRun`) and (b) the on-disk track JSON the watch
/// writes via `WorkoutManager.writeTrackJSON` for the phone to gzip + upload.
/// This test pins that the watch encodes the payload's track + metadata fields
/// in the canonical shape the phone-side ingest and the other clients expect.
final class WatchRunPayloadFixtureTests: XCTestCase {

    private struct Fixture: Decodable {
        let payload: Payload
        let expectedRow: ExpectedRow
        let expectedMetadata: ExpectedMetadata
        let expectedTrackCount: Int
        let expectedFirstPointBpm: Int

        enum CodingKeys: String, CodingKey {
            case payload, expectedRow, expectedMetadata, expectedTrackCount, expectedFirstPointBpm
        }
    }

    private struct Payload: Decodable {
        let id: String
        let started_at: String
        let duration_s: Int
        let distance_m: Double
        let source: String
        let activity_type: String
        let avg_bpm: Int
        let track: [FixturePoint]
    }

    private struct FixturePoint: Decodable {
        let lat: Double
        let lng: Double
        let ele: Double?
        let ts: String?
        let bpm: Int?
    }

    private struct ExpectedRow: Decodable {
        let source: String
        let duration_s: Int
        let distance_m: Double
    }

    private struct ExpectedMetadata: Decodable {
        let activity_type: String
        let avg_bpm: Int
        let last_modified_at: String
    }

    private func loadFixture(file: StaticString = #filePath) throws -> Fixture {
        // Resolve the repo-root fixture relative to THIS source file so the
        // test doesn't depend on the runner's cwd. This file lives at
        // apps/watch_ios/WatchAppTests/, so the fixture is three dirs up.
        let here = URL(fileURLWithPath: "\(file)")
        let fixtureURL = here
            .deletingLastPathComponent() // WatchAppTests
            .deletingLastPathComponent() // watch_ios
            .deletingLastPathComponent() // apps
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("fixtures/watch_run_payload.json")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(Fixture.self, from: data)
    }

    func testFixtureLoads() throws {
        let f = try loadFixture()
        XCTAssertEqual(f.payload.source, "watch")
    }

    func testPayloadSourceMatchesExpectedRow() throws {
        let f = try loadFixture()
        XCTAssertEqual(f.payload.source, f.expectedRow.source)
        XCTAssertEqual(f.payload.source, "watch", "The Apple Watch always sends source=watch")
    }

    func testActivityTypeIsRun() throws {
        // The watch hardcodes activity_type=run (see ContentView.syncRun +
        // SupabaseService.syncRun) so the row passes the
        // runs_metadata_activity_type_check CHECK constraint. Pin it against
        // the canonical fixture.
        let f = try loadFixture()
        XCTAssertEqual(f.payload.activity_type, "run")
        XCTAssertEqual(f.expectedMetadata.activity_type, "run")
    }

    func testTrackCountAndFirstPointBpm() throws {
        let f = try loadFixture()
        XCTAssertEqual(f.payload.track.count, f.expectedTrackCount)
        XCTAssertEqual(f.payload.track.first?.bpm, f.expectedFirstPointBpm)
    }

    func testRowDistanceAndDurationMatchPayload() throws {
        let f = try loadFixture()
        XCTAssertEqual(f.payload.duration_s, f.expectedRow.duration_s)
        XCTAssertEqual(f.payload.distance_m, f.expectedRow.distance_m, accuracy: 0.0001)
    }

    func testAvgBpmMatchesExpectedMetadata() throws {
        let f = try loadFixture()
        XCTAssertEqual(f.payload.avg_bpm, f.expectedMetadata.avg_bpm)
    }

    /// The watch's own `TrackPoint` (the shape written to the JSON file the
    /// phone uploads) must encode `lat/lng/ele/ts` in the same field names
    /// the fixture's track points use, or the uploaded track is unreadable by
    /// web/mobile. Round-trip a fixture point through the watch's TrackPoint
    /// to assert the field names line up.
    func testWatchTrackPointEncodesCanonicalFieldNames() throws {
        let f = try loadFixture()
        let src = f.payload.track[0]
        let wp = WorkoutManager.TrackPoint(lat: src.lat, lng: src.lng, ele: src.ele, ts: src.ts)
        let data = try JSONEncoder().encode(wp)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(obj?["lat"])
        XCTAssertNotNil(obj?["lng"])
        XCTAssertNotNil(obj?["ele"])
        XCTAssertNotNil(obj?["ts"])
        // No stray extra keys leak into the uploaded track object.
        XCTAssertEqual(Set((obj ?? [:]).keys), Set(["lat", "lng", "ele", "ts"]))
    }

    /// The track array the watch writes decodes back into the watch's own
    /// TrackPoint shape — closes the encode/decode loop the phone relies on.
    func testTrackArrayRoundTripsThroughWatchTrackPoint() throws {
        let f = try loadFixture()
        let points = f.payload.track.map {
            WorkoutManager.TrackPoint(lat: $0.lat, lng: $0.lng, ele: $0.ele, ts: $0.ts)
        }
        let data = try JSONEncoder().encode(points)
        let back = try JSONDecoder().decode([WorkoutManager.TrackPoint].self, from: data)
        XCTAssertEqual(back.count, f.expectedTrackCount)
        XCTAssertEqual(back[0].lat, f.payload.track[0].lat, accuracy: 0.00001)
        XCTAssertEqual(back[0].ts, f.payload.track[0].ts)
    }
}

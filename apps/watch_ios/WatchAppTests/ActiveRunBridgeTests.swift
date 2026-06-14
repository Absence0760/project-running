import XCTest
@testable import WatchApp

/// `ActiveRunSnapshot` is the on-wire shape the host app writes to the
/// App-Group `UserDefaults` and the complication widget extension reads.
/// A field drift here silently breaks the watch-face complication (the two
/// processes don't share memory — JSON in shared defaults is the whole
/// contract), so the Codable round-trip and the `.empty` fallback are worth
/// pinning. The 24h staleness ceiling consumed by the provider's
/// `snapshotEntry` is replicated here as a guard against a phantom run
/// surviving a host-app crash.
final class ActiveRunBridgeTests: XCTestCase {

    // MARK: - Codable round-trip

    func testSnapshotRoundTrip() throws {
        let snap = ActiveRunSnapshot(
            isActive: true,
            elapsedSeconds: 1830,
            distanceMeters: 5230.5,
            paceSecPerKm: 330.0,
            lastUpdatedEpoch: 1_700_000_000.0
        )
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(ActiveRunSnapshot.self, from: data)
        XCTAssertEqual(back.isActive, snap.isActive)
        XCTAssertEqual(back.elapsedSeconds, snap.elapsedSeconds)
        XCTAssertEqual(back.distanceMeters, snap.distanceMeters, accuracy: 0.0001)
        XCTAssertEqual(back.paceSecPerKm, snap.paceSecPerKm)
        XCTAssertEqual(back.lastUpdatedEpoch, snap.lastUpdatedEpoch, accuracy: 0.0001)
    }

    func testSnapshotNilPaceRoundTrip() throws {
        // A fresh run with no pace yet: nil must survive encode/decode, not
        // become 0 (which the complication would render as a real pace).
        let snap = ActiveRunSnapshot(
            isActive: true,
            elapsedSeconds: 3,
            distanceMeters: 0,
            paceSecPerKm: nil,
            lastUpdatedEpoch: 1_700_000_000.0
        )
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(ActiveRunSnapshot.self, from: data)
        XCTAssertNil(back.paceSecPerKm)
    }

    func testEmptySnapshotIsInactiveZeroed() {
        let e = ActiveRunSnapshot.empty
        XCTAssertFalse(e.isActive)
        XCTAssertEqual(e.elapsedSeconds, 0)
        XCTAssertEqual(e.distanceMeters, 0)
        XCTAssertNil(e.paceSecPerKm)
        XCTAssertEqual(e.lastUpdatedEpoch, 0)
    }

    // MARK: - App-Group bridge write/read

    func testBridgeWriteThenReadRoundTrips() {
        // Without the App Group entitlement (test host has none) the suite
        // UserDefaults can be nil; in that case write is a no-op and read
        // returns .empty. Tolerate both: assert the contract, not the
        // entitlement. When the suite IS available the round-trip holds.
        let snap = ActiveRunSnapshot(
            isActive: true,
            elapsedSeconds: 600,
            distanceMeters: 2000,
            paceSecPerKm: 300,
            lastUpdatedEpoch: 1_700_000_123.0
        )
        ActiveRunBridge.write(snap)
        let back = ActiveRunBridge.read()

        if UserDefaults(suiteName: ActiveRunBridge.appGroup) != nil {
            XCTAssertEqual(back.elapsedSeconds, 600)
            XCTAssertEqual(back.distanceMeters, 2000, accuracy: 0.0001)
            ActiveRunBridge.clear()
            XCTAssertFalse(ActiveRunBridge.read().isActive, "After clear, read must fall back to .empty")
        } else {
            XCTAssertFalse(back.isActive, "No App-Group suite: read must degrade to .empty")
        }
    }

    func testBridgeReadWithNoStoreReturnsEmpty() {
        ActiveRunBridge.clear()
        let back = ActiveRunBridge.read()
        XCTAssertFalse(back.isActive)
        XCTAssertEqual(back.elapsedSeconds, 0)
    }

    // MARK: - Staleness ceiling (mirrors ActiveRunProvider.snapshotEntry)

    /// The provider treats `isActive && lastUpdatedEpoch > 0 && age < 24h`
    /// as live. A snapshot left `isActive == true` by a crashed host app
    /// must read as inactive once it ages past the ceiling, or the watch
    /// face shows a phantom run forever. This re-derives that rule against
    /// the snapshot fields the provider consumes.
    private func isLive(_ snap: ActiveRunSnapshot, now: TimeInterval) -> Bool {
        let staleAfter: TimeInterval = 24 * 60 * 60
        let age = now - snap.lastUpdatedEpoch
        return snap.isActive && snap.lastUpdatedEpoch > 0 && age < staleAfter
    }

    func testFreshActiveSnapshotIsLive() {
        let now = 1_700_000_000.0
        let snap = ActiveRunSnapshot(isActive: true, elapsedSeconds: 60, distanceMeters: 200, paceSecPerKm: 300, lastUpdatedEpoch: now - 5)
        XCTAssertTrue(isLive(snap, now: now))
    }

    func testStaleActiveSnapshotReadsInactive() {
        let now = 1_700_000_000.0
        // 25 hours old, still flagged active — a phantom from a crash.
        let snap = ActiveRunSnapshot(isActive: true, elapsedSeconds: 60, distanceMeters: 200, paceSecPerKm: 300, lastUpdatedEpoch: now - 25 * 3600)
        XCTAssertFalse(isLive(snap, now: now))
    }

    func testZeroEpochNeverLive() {
        let now = 1_700_000_000.0
        let snap = ActiveRunSnapshot(isActive: true, elapsedSeconds: 0, distanceMeters: 0, paceSecPerKm: nil, lastUpdatedEpoch: 0)
        XCTAssertFalse(isLive(snap, now: now), "lastUpdatedEpoch==0 (never written) must not read live")
    }

    func testInactiveSnapshotNeverLive() {
        let now = 1_700_000_000.0
        let snap = ActiveRunSnapshot(isActive: false, elapsedSeconds: 0, distanceMeters: 0, paceSecPerKm: nil, lastUpdatedEpoch: now)
        XCTAssertFalse(isLive(snap, now: now))
    }

    func testJustUnderCeilingStillLive() {
        let now = 1_700_000_000.0
        // 23h59m old — a genuine (if implausible) long run, must stay live.
        let snap = ActiveRunSnapshot(isActive: true, elapsedSeconds: 86_300, distanceMeters: 200000, paceSecPerKm: 300, lastUpdatedEpoch: now - (24 * 3600 - 60))
        XCTAssertTrue(isLive(snap, now: now))
    }
}

import XCTest
@testable import WatchApp

/// An unsynced run's GPS trace used to live in `Caches`, which the system
/// reclaims under storage pressure — silently destroying the only copy of a
/// recorded run while the app went on offering to sync it. These pin the
/// three halves of the fix: the payload directory is durable, an upgrade
/// carries across whatever the old build left behind, and a run whose trace
/// really has gone is reported rather than shipped as an empty track.
final class RunPayloadStorageTests: XCTestCase {

    private var root: URL!
    private var legacy: URL!
    private var durable: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("payload-storage-\(UUID().uuidString)", isDirectory: true)
        legacy = root.appendingPathComponent("Caches/run_checkpoint", isDirectory: true)
        durable = root.appendingPathComponent("Application Support/run_checkpoint", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: durable, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ url: URL, _ body: String) {
        FileManager.default.createFile(atPath: url.path, contents: Data(body.utf8))
    }

    // MARK: - the payload is not in a purgeable directory

    func testPayloadDirectoryIsNotUnderCaches() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        XCTAssertFalse(
            RunPayloadStorage.directory.path.hasPrefix(caches.path),
            "an unsynced run's only copy must not sit where the system reclaims it"
        )
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        XCTAssertTrue(RunPayloadStorage.directory.path.hasPrefix(support.path))
    }

    func testCheckpointTrackFileResolvesIntoTheDurableDirectory() {
        let track = CheckpointStore.trackFile(runId: "abc")
        XCTAssertEqual(track.deletingLastPathComponent().path, RunPayloadStorage.directory.path)
        XCTAssertEqual(track.lastPathComponent, "abc.ndjson")
    }

    func testPreparedDirectoryIsExcludedFromBackup() throws {
        let dir = root.appendingPathComponent("prepared", isDirectory: true)
        RunPayloadStorage.createDirectory(at: dir)
        let excluded = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        XCTAssertEqual(excluded, true, "a GPS trace has no business in an iCloud device backup")
    }

    // MARK: - migration off an existing install

    func testMigrationMovesEveryCachedPayloadAcross() {
        write(legacy.appendingPathComponent("run-a.ndjson"), "{\"lat\":1}\n")
        write(legacy.appendingPathComponent("run-b.ndjson"), "{\"lat\":2}\n")

        let moved = RunPayloadStorage.migrateLegacyPayloads(from: legacy, to: durable)

        XCTAssertEqual(Set(moved), ["run-a.ndjson", "run-b.ndjson"])
        XCTAssertEqual(
            try? String(contentsOf: durable.appendingPathComponent("run-a.ndjson"), encoding: .utf8),
            "{\"lat\":1}\n"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: durable.appendingPathComponent("run-b.ndjson").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testAFailedMoveLeavesTheLegacyPayloadWhereItIs() {
        // `removeItem` on a populated directory would delete exactly the
        // payloads the move could not carry across.
        write(legacy.appendingPathComponent("run-a.ndjson"), "stale")
        write(durable.appendingPathComponent("run-a.ndjson"), "current")

        RunPayloadStorage.migrateLegacyPayloads(from: legacy, to: durable)

        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("run-a.ndjson").path))
    }

    func testMigrationRefusesToMigrateADirectoryOntoItself() {
        write(legacy.appendingPathComponent("run-a.ndjson"), "payload")
        XCTAssertEqual(RunPayloadStorage.migrateLegacyPayloads(from: legacy, to: legacy), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("run-a.ndjson").path))
    }

    func testMigrationNeverOverwritesADurablePayloadWithACachedOne() {
        write(legacy.appendingPathComponent("run-a.ndjson"), "stale")
        write(durable.appendingPathComponent("run-a.ndjson"), "current")

        let moved = RunPayloadStorage.migrateLegacyPayloads(from: legacy, to: durable)

        XCTAssertTrue(moved.isEmpty)
        XCTAssertEqual(
            try? String(contentsOf: durable.appendingPathComponent("run-a.ndjson"), encoding: .utf8),
            "current"
        )
    }

    func testMigrationIsIdempotentAndSurvivesAnAbsentLegacyDirectory() {
        write(legacy.appendingPathComponent("run-a.ndjson"), "x")
        XCTAssertEqual(RunPayloadStorage.migrateLegacyPayloads(from: legacy, to: durable), ["run-a.ndjson"])
        XCTAssertEqual(RunPayloadStorage.migrateLegacyPayloads(from: legacy, to: durable), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: durable.appendingPathComponent("run-a.ndjson").path))
    }

    func testPayloadsToMigrateSkipsOnlyTheNamesAlreadyPresent() {
        XCTAssertEqual(
            RunPayloadStorage.payloadsToMigrate(
                legacyNames: ["a.ndjson", "b.ndjson", "c.ndjson"],
                destinationNames: ["b.ndjson"]
            ),
            ["a.ndjson", "c.ndjson"]
        )
    }

    // MARK: - export lifetime

    func testAnExportStillQueuedForDeliveryIsNeverSwept() {
        let pending = durable.appendingPathComponent("pending.json")
        let candidates = [(url: pending, modified: Date(timeIntervalSince1970: 0))]
        XCTAssertEqual(
            RunPayloadStorage.exportsToSweep(candidates: candidates, pending: [pending], now: Date()),
            [],
            "WCSession reads the export off disk for the life of the transfer"
        )
    }

    func testAFreshExportIsNeverSwept() {
        let fresh = durable.appendingPathComponent("fresh.json")
        let candidates = [(url: fresh, modified: Date())]
        XCTAssertEqual(
            RunPayloadStorage.exportsToSweep(candidates: candidates, pending: [], now: Date()),
            []
        )
    }

    func testAnAgedUnreferencedExportIsSwept() {
        let stale = durable.appendingPathComponent("stale.json")
        write(stale, "[]")
        let old = Date().addingTimeInterval(-2 * RunPayloadStorage.staleExportMinAge)
        try? FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: stale.path)

        let swept = RunPayloadStorage.sweepStaleExports(in: durable, pending: [])

        XCTAssertEqual(swept.map(\.lastPathComponent), ["stale.json"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }

    func testTheSweepNeverTouchesAnNdjsonTrack() {
        let track = durable.appendingPathComponent("run-a.ndjson")
        write(track, "{\"lat\":1}\n")
        let old = Date().addingTimeInterval(-2 * RunPayloadStorage.staleExportMinAge)
        try? FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: track.path)

        XCTAssertEqual(RunPayloadStorage.sweepStaleExports(in: durable, pending: []), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: track.path))
    }

    // MARK: - honesty when the payload really is gone

    func testAMissingTraceForARunThatRecordedOneIsReported() {
        XCTAssertTrue(RunPayloadStorage.payloadIsMissing(recordedPointCount: 12_000, fileExists: false))
    }

    func testAnIndoorRunWithNoRecordedTraceIsNotReportedAsMissing() {
        XCTAssertFalse(RunPayloadStorage.payloadIsMissing(recordedPointCount: 0, fileExists: false))
    }

    func testAPresentTraceIsNotReportedAsMissing() {
        XCTAssertFalse(RunPayloadStorage.payloadIsMissing(recordedPointCount: 12_000, fileExists: true))
    }
}

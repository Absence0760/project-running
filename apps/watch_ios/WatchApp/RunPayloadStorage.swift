import Foundation

/// Where a recorded run's payload lives between the moment recording stops
/// and the moment the phone has it.
///
/// It used to be `Caches`. Until a run has been handed to the phone its
/// NDJSON track — and the JSON export built from it, which `WCSession` reads
/// straight off disk while the transfer is outstanding — are the only copies
/// of the trace in existence, and the system reclaims `Caches` under storage
/// pressure without asking and without telling the app. A not-yet-synced
/// payload is not a cache: it lives in Application Support, which only this
/// app deletes.
///
/// Excluded from backup for the same reason the Wear app sets
/// `android:allowBackup="false"` — a run's GPS trace is personal location
/// data and has no business in an iCloud device backup on its way to being
/// uploaded once.
enum RunPayloadStorage {
    /// Kept as the pre-migration name so an in-flight upgrade reads the same
    /// per-run file names on either side of the move.
    static let directoryName = "run_checkpoint"

    /// Exports stranded by a crash between "handed to WCSession" and the
    /// delivery callback are only swept once they are this old AND no longer
    /// among the session's outstanding transfers — WCSession will happily
    /// hold a queued transfer for days while the phone is off.
    static let staleExportMinAge: TimeInterval = 7 * 24 * 60 * 60

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static var legacyDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Create the durable directory, keep it out of backups, and carry across
    /// anything an older build left in `Caches`. Idempotent; call at launch
    /// before anything reads a payload.
    static func prepare() {
        createDirectory(at: directory)
        migrateLegacyPayloads()
    }

    static func createDirectory(at url: URL) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            var mutable = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try mutable.setResourceValues(values)
        } catch {
            #if DEBUG
            print("RunPayloadStorage: could not prepare \(url.path): \(error)")
            #endif
        }
    }

    /// Which of `legacyNames` a migration must move. A name already present
    /// at the destination is left where it is: the durable copy is the one a
    /// finished run is keyed to, and overwriting it with a stale cached file
    /// would trade a good payload for an older one.
    static func payloadsToMigrate(legacyNames: [String], destinationNames: Set<String>) -> [String] {
        legacyNames.filter { !destinationNames.contains($0) }
    }

    /// Move every payload an older build left in `Caches` into the durable
    /// directory. Returns the file names moved.
    @discardableResult
    static func migrateLegacyPayloads(
        from legacy: URL = legacyDirectory,
        to destination: URL = directory
    ) -> [String] {
        let fm = FileManager.default
        guard legacy != destination else { return [] }
        guard let legacyEntries = try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) else {
            return []
        }
        let existing = Set(
            (try? fm.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil))?
                .map(\.lastPathComponent) ?? []
        )
        let names = payloadsToMigrate(
            legacyNames: legacyEntries.map(\.lastPathComponent),
            destinationNames: existing
        )
        var moved: [String] = []
        for name in names {
            do {
                try fm.moveItem(
                    at: legacy.appendingPathComponent(name),
                    to: destination.appendingPathComponent(name)
                )
                moved.append(name)
            } catch {
                #if DEBUG
                print("RunPayloadStorage: could not migrate \(name): \(error)")
                #endif
            }
        }
        // Drop the legacy directory only once it is genuinely empty —
        // `removeItem` on a populated one would delete the very payloads a
        // failed move just left behind.
        if (try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil))?.isEmpty == true {
            try? fm.removeItem(at: legacy)
        }
        return moved
    }

    /// Which JSON exports may be deleted: not still queued for delivery, and
    /// old enough that no plausible in-flight transfer still needs them. An
    /// export is the file `WCSession` reads from during the transfer, so
    /// deleting one early aborts a sync that was about to succeed.
    static func exportsToSweep(
        candidates: [(url: URL, modified: Date)],
        pending: Set<URL>,
        now: Date,
        minAge: TimeInterval = staleExportMinAge
    ) -> [URL] {
        candidates
            .filter { !pending.contains($0.url) }
            .filter { now.timeIntervalSince($0.modified) >= minAge }
            .map(\.url)
    }

    @discardableResult
    static func sweepStaleExports(
        in directory: URL = directory,
        pending: Set<URL>,
        now: Date = Date()
    ) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }
        let candidates: [(url: URL, modified: Date)] = entries
            .filter { $0.pathExtension == "json" }
            .map { url in
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return (url, modified)
            }
        let doomed = exportsToSweep(candidates: candidates, pending: pending, now: now)
        for url in doomed { try? fm.removeItem(at: url) }
        return doomed
    }

    /// True when a finished run recorded a trace that is no longer on disk.
    ///
    /// The sync then still goes through — losing the run entirely would be
    /// worse than losing its map — but the runner is told, rather than being
    /// handed an empty track that reads exactly like an indoor recording.
    static func payloadIsMissing(recordedPointCount: Int, fileExists: Bool) -> Bool {
        recordedPointCount > 0 && !fileExists
    }
}

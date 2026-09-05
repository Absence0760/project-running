import XCTest

/// Guard-rail: every `runs.metadata` key referenced in the watchOS sources
/// must be registered in `docs/backend/metadata.md`.
///
/// `runs.metadata` is a jsonb bag with no type-level protection. Cross-client
/// drift (this watch writes `activity_type`, web reads `activityType`) is the
/// exact failure mode the registry was created to prevent. The Dart twin of
/// this guard is `apps/mobile_android/test/metadata_registry_test.dart`; the
/// TypeScript and Kotlin twins live under `apps/web/` and `apps/watch_wear/`.
/// Each scans its own platform's sources against the one shared registry.
final class MetadataRegistryTests: XCTestCase {

    /// Matches that are a real `metadata` identifier but not `runs.metadata`.
    ///
    /// `WCSession.transferFile(_:metadata:)` takes a transport envelope, not a
    /// jsonb bag: `ContentView.syncRun` packs the run's own COLUMNS into it
    /// (`id`, `started_at`, `duration_s`, `distance_m`, `source`) alongside the
    /// real metadata keys the phone lifts out of it — see the matching key
    /// list in `apps/mobile_ios/ios/Runner/WatchIngestBridge.swift`. Column
    /// names have no registry row by definition, so they are exempt; the
    /// metadata keys in that same dict stay guarded.
    private let exemptReferences: Set<String> = [
        "id", "started_at", "duration_s", "distance_m", "source",
    ]

    func testEveryRunsMetadataKeyInSwiftSourceIsRegistered() throws {
        let root = repoRoot()
        let docData = try Data(contentsOf: root.appendingPathComponent("docs/backend/metadata.md"))
        let registry = parseRegistry(String(decoding: docData, as: UTF8.self))
        XCTAssertFalse(registry.isEmpty, "parsed an empty registry — the markdown table shape changed")

        let sourceRoot = root.appendingPathComponent("apps/watch_ios/WatchApp")
        var referenced: [String: Set<String>] = [:]
        for file in swiftFiles(under: sourceRoot) {
            let raw = try Data(contentsOf: file)
            let source = stripComments(String(decoding: raw, as: UTF8.self))
            for key in extractMetadataKeys(source) {
                referenced[key, default: []].insert(file.lastPathComponent)
            }
        }

        // A scan that finds nothing is a broken scan, not a clean tree: the
        // watch's own run-metadata dict is always in range.
        XCTAssertFalse(
            referenced.isEmpty,
            "found no runs.metadata key references at all — the scan is not reaching the sources"
        )

        let unknown = referenced.keys
            .filter { !registry.contains($0) && !exemptReferences.contains($0) }
            .sorted()

        XCTAssertEqual(unknown, [], """
            Unregistered runs.metadata key(s) referenced in Swift source:
            \(unknown.map { "  \($0) at \(referenced[$0]!.sorted().joined(separator: ", "))" }.joined(separator: "\n"))

            Either:
              1) Register the key in docs/backend/metadata.md (preferred) — snake_case, shape, \
            writers, readers, public_runs safety.
              2) If the match is spurious (a `metadata` identifier that is not runs.metadata), \
            add the key to exemptReferences in this test with a reason.

            Drift in runs.metadata is invisible to the DB type system — this registry IS the \
            coordination point across web, mobile, watch_wear, and watch_ios.
            """)
    }

    /// `hr_coverage` is a MEASUREMENT, and this watch now makes one and sends it.
    ///
    /// Wear OS writes the key because Health Services' `MeasureClient` is
    /// foreground-only, so its `avg_bpm` can be a mean over a few minutes of a
    /// twelve-hour run (decisions § 1015 / § 1083). HealthKit's
    /// `HKLiveWorkoutBuilder` average is workout-scoped instead, so the claim
    /// here is genuinely better — but "better" is not a figure, and both watch
    /// clients write `source = 'watch'`, so until § 1207 the ABSENCE of the key
    /// was all a reader had. § 1156 built the measurement and spent it locally
    /// on the `avg_bpm` suppression; § 1207 sends it.
    ///
    /// What this guard holds, in the order the value travels. The figure must
    /// be MEASURED, not assumed — an assumed measurement is a fabricated one
    /// and worse than the absence it replaces — so the key may only be written
    /// from a non-nil claim, never unconditionally. It must be graded on the
    /// path a SAVED run takes, not merely available beside it: reading the
    /// ungraded `summaryAverageBPM` into a `FinishedRun` or a checkpoint is the
    /// defect the grade exists to prevent. And the statement that makes the
    /// remaining ambiguity readable has to stay where a maintainer will find
    /// it, or the next person adds an assumed `1.0`.
    /// Renamed from `testWatchOSWritesNoCoverageKeyAndGradesTheAverageItDoesWrite`
    /// when the key started being sent: a guard whose name asserts the opposite
    /// of what its code checks is a guard nobody can read.
    func testWatchOSSendsOnlyAMeasuredCoverageAndGradesTheAverageBesideIt() throws {
        let root = repoRoot()
        let contentView = root.appendingPathComponent("apps/watch_ios/WatchApp/ContentView.swift")
        let cvData = try Data(contentsOf: contentView)
        let cv = stripComments(String(decoding: cvData, as: UTF8.self))
        XCTAssertTrue(
            cv.contains("metadata[\"hr_coverage\"]"),
            """
            apps/watch_ios no longer sends `hr_coverage`. The figure is measured \
            (`HealthKitManager.advanceCoverage`) and both ends of the WCSession \
            envelope carry it; dropping the write silently returns every Apple-Watch \
            run to the three-way-ambiguous absence § 1207 removed it from.
            """
        )
        XCTAssertNotNil(
            firstMatch(
                #"if\s+let\s+(\w+)\s*=\s*run\.hrCoverage\s*\{\s*metadata\["hr_coverage"\]\s*=\s*\1\s*\}"#,
                in: cv
            ),
            """
            `hr_coverage` must be written only from a non-nil claim — the shape is \
            `if let <x> = run.hrCoverage { metadata["hr_coverage"] = <x> }`. An \
            unconditional write publishes 0.0 on every run whose HKWorkoutSession \
            never started, and a fabricated measurement is worse than a missing one \
            (decisions § 1207).
            """
        )
        XCTAssertFalse(
            cv.contains("hrCoverage ?? "),
            """
            A defaulted coverage is a fabricated measurement. Nil is UNMEASURED and \
            must omit the key, not resolve to a number.
            """
        )

        let hkURL = root.appendingPathComponent("apps/watch_ios/WatchApp/HealthKitManager.swift")
        let hkData = try Data(contentsOf: hkURL)
        let hk = String(decoding: hkData, as: UTF8.self)
        XCTAssertTrue(
            hk.contains("summaryAverageBPM"),
            "HealthKitManager no longer produces `summaryAverageBPM` — this guard is reading nothing"
        )
        for token in ["hr_coverage", "workout-scoped"] {
            XCTAssertTrue(
                hk.contains(token),
                """
                HealthKitManager.swift no longer states what `summaryAverageBPM` is scoped to \
                (missing "\(token)"). The value goes to the row as `avg_bpm`, and both watch \
                clients write `source = 'watch'` — so without this statement the absence of \
                `hr_coverage` is indistinguishable from a Wear run predating the key. Restore \
                it where the average is produced (decisions § 1106).
                """
            )
        }

        // The threshold itself. § 1106 recorded the unquantified gap — a live
        // session whose sensor goes quiet still averages what it got — and
        // § 1156 quantified it. The figure now travels to the row as well
        // (§ 1207), but the suppression is the half that CHANGES `avg_bpm`:
        // delete the threshold and a mean over three minutes of a twelve-hour
        // run is saved as that run's average, with the coverage sitting
        // truthfully beside it saying so and nothing acting on it.
        XCTAssertTrue(
            hk.contains("minAverageBPMCoverage"),
            """
            HealthKitManager.swift no longer suppresses `avg_bpm` below a coverage floor. \
            A mean taken over less of the run than not is not the run's average, and every \
            reader of `avg_bpm` treats it as though it were (decisions § 1083 / § 1156).
            """
        )

        // And the grading has to be on the path a SAVED run takes, not merely
        // available beside it. `summaryAverageBPM` is the ungraded mean; a
        // recorder reading it straight into a `FinishedRun` or a checkpoint
        // is the defect the grade exists to prevent.
        let wmURL = root.appendingPathComponent("apps/watch_ios/WatchApp/WorkoutManager.swift")
        let wmData = try Data(contentsOf: wmURL)
        let wm = stripComments(String(decoding: wmData, as: UTF8.self))
        XCTAssertTrue(
            wm.contains("heartRateClaim("),
            "WorkoutManager no longer grades the heart rate it saves (decisions § 1156)"
        )
        XCTAssertFalse(
            wm.contains("summaryAverageBPM"),
            """
            WorkoutManager reads the UNGRADED mean. Every average that reaches a row — the \
            finished run and the 15 s checkpoint a crash recovers from — must go through \
            `heartRateClaim(activeElapsedSeconds:)`, or a mean over three minutes of a \
            twelve-hour run is saved as that run's average heart rate (decisions § 1156).
            """
        )
    }

    /// Repo root resolved from THIS source file so the test doesn't depend on
    /// the runner's cwd — same trick as `WatchRunPayloadFixtureTests`.
    private func repoRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // WatchAppTests
            .deletingLastPathComponent() // watch_ios
            .deletingLastPathComponent() // apps
            .deletingLastPathComponent() // repo root
    }

    private func swiftFiles(under root: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.sorted {
            $0.path < $1.path
        }
    }

    /// Registered key names from the markdown registry: each table row opens
    /// `| \`key\` |`. Same parse as the Dart guard, so the two can't disagree
    /// about what "registered" means.
    private func parseRegistry(_ doc: String) -> Set<String> {
        var out: Set<String> = []
        for line in doc.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let m = firstMatch(#"^\|\s*`([a-z_][a-z0-9_]*)`\s*\|"#, in: String(line)) else {
                continue
            }
            out.insert(m)
        }
        return out
    }

    private func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text)
        else { return nil }
        return String(text[r])
    }

    /// Blank `//` and block comments, leaving offsets intact. String literals
    /// are walked over rather than blanked, so a `"//"` inside a string can't
    /// be mistaken for a comment and swallow the rest of the line.
    private func stripComments(_ source: String) -> String {
        var out = Array(source)
        var i = 0
        while i < out.count {
            if out[i] == "\"" {
                i += 1
                while i < out.count {
                    if out[i] == "\\" { i += 1 } else if out[i] == "\"" { break }
                    i += 1
                }
                i += 1
            } else if out[i] == "/", i + 1 < out.count, out[i + 1] == "/" {
                while i < out.count && out[i] != "\n" {
                    out[i] = " "
                    i += 1
                }
            } else if out[i] == "/", i + 1 < out.count, out[i + 1] == "*" {
                var depth = 1
                out[i] = " "
                out[i + 1] = " "
                i += 2
                while i < out.count && depth > 0 {
                    if out[i] == "/", i + 1 < out.count, out[i + 1] == "*" { depth += 1 }
                    if out[i] == "*", i + 1 < out.count, out[i + 1] == "/" { depth -= 1 }
                    if out[i] != "\n" { out[i] = " " }
                    i += 1
                }
                if i < out.count, out[i] == "/" {
                    out[i] = " "
                    i += 1
                }
            } else {
                i += 1
            }
        }
        return String(out)
    }

    /// Every `runs.metadata` key reference in one comment-stripped file:
    ///
    ///   * subscript reads/writes: `metadata["x"]`
    ///   * dictionary literals: `var metadata: [String: Any] = [ "x": … ]` and
    ///     the `metadata: [ "x": … ]` argument of a `RunPayload` init — DEPTH-1
    ///     string keys only, so a nested value dictionary can't contribute.
    private func extractMetadataKeys(_ source: String) -> Set<String> {
        var keys: Set<String> = []
        let chars = Array(source)

        for range in matchRanges(#"(?<![A-Za-z0-9_])[A-Za-z0-9_]*[Mm]etadata\s*\[\s*"([a-z_][a-z0-9_]*)"\s*\]"#, in: source, group: 1) {
            keys.insert(String(source[range]))
        }
        // `= [` (a var/let with an optional type annotation) and `: [` (a
        // labelled init argument). The second also matches a plain type
        // annotation like `let metadata: [String: String]`, which walks a
        // bracket pair holding no string keys and contributes nothing.
        for pattern in [
            #"(?<![A-Za-z0-9_])[A-Za-z0-9_]*[Mm]etadata\s*(?::[^=\n]*)?=\s*\["#,
            #"(?<![A-Za-z0-9_])[A-Za-z0-9_]*[Mm]etadata\s*:\s*\["#,
        ] {
            for range in matchRanges(pattern, in: source, group: 0) {
                let open = source.distance(from: source.startIndex, to: range.upperBound) - 1
                keys.formUnion(depthOneDictionaryKeys(chars, open: open))
            }
        }
        return keys
    }

    private func matchRanges(_ pattern: String, in text: String, group: Int) -> [Range<String.Index>] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range(at: group), in: text) }
    }

    /// String keys at depth 1 of the bracket pair opened at [open].
    private func depthOneDictionaryKeys(_ chars: [Character], open: Int) -> Set<String> {
        var keys: Set<String> = []
        var depth = 1
        var i = open + 1
        while i < chars.count && depth > 0 {
            switch chars[i] {
            case "[": depth += 1
            case "]": depth -= 1
            case "\"":
                let start = i + 1
                var j = start
                while j < chars.count {
                    if chars[j] == "\\" { j += 1 } else if chars[j] == "\"" { break }
                    j += 1
                }
                if depth == 1 && j < chars.count {
                    var k = j + 1
                    while k < chars.count && chars[k] == " " { k += 1 }
                    if k < chars.count && chars[k] == ":" {
                        let key = String(chars[start..<j])
                        if key.range(of: "^[a-z_][a-z0-9_]*$", options: .regularExpression) != nil {
                            keys.insert(key)
                        }
                    }
                }
                i = j
            default: break
            }
            i += 1
        }
        return keys
    }
}

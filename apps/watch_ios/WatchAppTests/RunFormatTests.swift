import XCTest
@testable import WatchApp

/// Pace / distance formatting is the watch's only user-facing number
/// surface during a run, and the same `RunFormat` strings are mirrored by
/// the complication (`ActiveRunComplication.swift`) and the Wear OS twin
/// (`UnitFormatTest.kt` / `ActiveRunTileFormattersTest.kt`). These pin the
/// km/mi conversion, the m:ss pace decomposition, and the placeholder.
///
/// `RunFormat` reads the km/mi choice from `UserDefaults preferred_unit`, so
/// each test sets (and restores) that key explicitly rather than depending on
/// the device default.
final class RunFormatTests: XCTestCase {
    private var savedUnit: String?

    override func setUp() {
        super.setUp()
        savedUnit = UserDefaults.standard.string(forKey: "preferred_unit")
    }

    override func tearDown() {
        if let savedUnit {
            UserDefaults.standard.set(savedUnit, forKey: "preferred_unit")
        } else {
            UserDefaults.standard.removeObject(forKey: "preferred_unit")
        }
        super.tearDown()
    }

    private func useKm() { UserDefaults.standard.set("km", forKey: "preferred_unit") }
    private func useMiles() { UserDefaults.standard.set("mi", forKey: "preferred_unit") }

    // MARK: - prefersMiles flag

    func testPrefersMilesReadsPreferredUnitKey() {
        useMiles()
        XCTAssertTrue(RunFormat.prefersMiles)
        useKm()
        XCTAssertFalse(RunFormat.prefersMiles)
        UserDefaults.standard.removeObject(forKey: "preferred_unit")
        XCTAssertFalse(RunFormat.prefersMiles, "Absent key must default to km, not miles")
    }

    func testMetresPerMileConstant() {
        XCTAssertEqual(RunFormat.metresPerMile, 1609.344, accuracy: 0.0001)
    }

    // MARK: - distance, km mode

    func testDistanceKmTwoDecimals() {
        useKm()
        let s = RunFormat.distance(metres: 5120, fractionDigits: 2)
        XCTAssertTrue(s.contains("5.12") || s.contains("5,12"), "Got: \(s)")
        XCTAssertTrue(s.lowercased().contains("km"), "Got: \(s)")
    }

    func testDistanceKmZeroIsValid() {
        useKm()
        let s = RunFormat.distance(metres: 0, fractionDigits: 2)
        XCTAssertTrue(s.hasPrefix("0"), "Got: \(s)")
        XCTAssertTrue(s.lowercased().contains("km"), "Got: \(s)")
    }

    func testDistanceKmRespectsFractionDigits() {
        useKm()
        let oneDigit = RunFormat.distance(metres: 5120, fractionDigits: 1)
        // 5.12 km truncates/rounds to one decimal: "5.1 km".
        XCTAssertTrue(oneDigit.contains("5.1") || oneDigit.contains("5,1"), "Got: \(oneDigit)")
        XCTAssertFalse(oneDigit.contains("5.12"), "One-digit format must not show two decimals: \(oneDigit)")
    }

    // MARK: - distance, miles mode

    func testDistanceMilesConvertsFromMetres() {
        useMiles()
        // 1609.344 m == exactly 1 mile.
        let s = RunFormat.distance(metres: 1609.344, fractionDigits: 2)
        XCTAssertTrue(s.contains("1.00") || s.contains("1,00"), "Got: \(s)")
        XCTAssertTrue(s.lowercased().contains("mi"), "Got: \(s)")
    }

    func testDistanceMilesHalfMile() {
        useMiles()
        let s = RunFormat.distance(metres: 804.672, fractionDigits: 2)
        XCTAssertTrue(s.contains("0.50") || s.contains("0,50"), "Got: \(s)")
    }

    // MARK: - pace

    func testPaceNilReturnsPlaceholder() {
        useKm()
        XCTAssertEqual(RunFormat.pace(secondsPerKm: nil), "--:--")
    }

    func testPaceZeroReturnsPlaceholder() {
        useKm()
        XCTAssertEqual(RunFormat.pace(secondsPerKm: 0), "--:--")
    }

    func testPaceNegativeReturnsPlaceholder() {
        useKm()
        XCTAssertEqual(RunFormat.pace(secondsPerKm: -30), "--:--")
    }

    func testPaceKmFormat() {
        useKm()
        XCTAssertEqual(RunFormat.pace(secondsPerKm: 330), "5:30 /km")
        XCTAssertEqual(RunFormat.pace(secondsPerKm: 300), "5:00 /km")
        XCTAssertEqual(RunFormat.pace(secondsPerKm: 754), "12:34 /km")
    }

    func testPaceKmRoundsToNearestSecond() {
        useKm()
        // 330.4 rounds down to 330 -> 5:30; 330.6 rounds up to 331 -> 5:31.
        XCTAssertEqual(RunFormat.pace(secondsPerKm: 330.4), "5:30 /km")
        XCTAssertEqual(RunFormat.pace(secondsPerKm: 330.6), "5:31 /km")
    }

    func testPaceKmZeroPadsSeconds() {
        useKm()
        // 305 s == 5:05, the seconds must be zero-padded.
        XCTAssertEqual(RunFormat.pace(secondsPerKm: 305), "5:05 /km")
    }

    func testPaceMilesConvertsAndSuffixes() {
        useMiles()
        // 300 s/km * (1609.344/1000) = 482.8 s/mi == 8:03 /mi (482.8 -> 483).
        XCTAssertEqual(RunFormat.pace(secondsPerKm: 300), "8:03 /mi")
    }

    func testPaceMilesSlowPace() {
        useMiles()
        // 360 s/km -> 579.36 s/mi -> 579 -> 9:39 /mi.
        XCTAssertEqual(RunFormat.pace(secondsPerKm: 360), "9:39 /mi")
    }
}

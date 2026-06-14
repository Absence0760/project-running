import XCTest
@testable import WatchApp

/// Pins the active-run complication's pure formatters
/// (`formatElapsed` / `formatDistanceKm` / `formatPaceSecPerKm` in
/// `Complications/ActiveRunComplication.swift`). They are a deliberate
/// second copy of the recording-screen formatting — the complication
/// builds in a separate Widget Extension target that can't link
/// `RunFormat.swift` — so they must be tested independently and kept in
/// lockstep with `RunFormatTests`. Mirrors the Wear OS twin's
/// `ActiveRunTileFormattersTest.kt`.
final class ComplicationFormatterTests: XCTestCase {
    private var savedUnit: String?

    override func setUp() {
        super.setUp()
        savedUnit = UserDefaults.standard.string(forKey: "preferred_unit")
        UserDefaults.standard.set("km", forKey: "preferred_unit")
    }

    override func tearDown() {
        if let savedUnit {
            UserDefaults.standard.set(savedUnit, forKey: "preferred_unit")
        } else {
            UserDefaults.standard.removeObject(forKey: "preferred_unit")
        }
        super.tearDown()
    }

    // MARK: - formatElapsed

    func testElapsedUnderOneHourIsMMSS() {
        XCTAssertEqual(formatElapsed(0), "00:00")
        XCTAssertEqual(formatElapsed(42), "00:42")
        XCTAssertEqual(formatElapsed(12 * 60 + 34), "12:34")
        XCTAssertEqual(formatElapsed(59 * 60 + 59), "59:59")
    }

    func testElapsedAtAndOverOneHourIsHMMSS() {
        XCTAssertEqual(formatElapsed(3600), "1:00:00")
        XCTAssertEqual(formatElapsed(1 * 3600 + 23 * 60 + 45), "1:23:45")
        XCTAssertEqual(formatElapsed(9 * 3600 + 59 * 60 + 59), "9:59:59")
    }

    func testElapsedUltraLength() {
        // 27h 03m 07s — well past any watch battery, but the formatter
        // must not overflow or wrap.
        XCTAssertEqual(formatElapsed(27 * 3600 + 3 * 60 + 7), "27:03:07")
    }

    func testElapsedClampsNegativeToZero() {
        XCTAssertEqual(formatElapsed(-5), "00:00")
    }

    // MARK: - formatPaceSecPerKm

    func testPaceKm() {
        XCTAssertEqual(formatPaceSecPerKm(330.0), "5:30/km")
        XCTAssertEqual(formatPaceSecPerKm(240.0), "4:00/km")
        XCTAssertEqual(formatPaceSecPerKm(754.0), "12:34/km")
    }

    func testPaceGuardsNilNonPositiveNonFinite() {
        XCTAssertEqual(formatPaceSecPerKm(nil), "—:—/km")
        XCTAssertEqual(formatPaceSecPerKm(0.0), "—:—/km")
        XCTAssertEqual(formatPaceSecPerKm(-30.0), "—:—/km")
        XCTAssertEqual(formatPaceSecPerKm(Double.nan), "—:—/km")
        XCTAssertEqual(formatPaceSecPerKm(Double.infinity), "—:—/km")
    }

    func testPaceMilesSuffixAndPlaceholder() {
        UserDefaults.standard.set("mi", forKey: "preferred_unit")
        // 300 s/km -> 8:03/mi.
        XCTAssertEqual(formatPaceSecPerKm(300.0), "8:03/mi")
        XCTAssertEqual(formatPaceSecPerKm(nil), "—:—/mi")
    }

    // MARK: - formatDistanceKm

    func testDistanceTwoDecimalsUnderTen() {
        let s = formatDistanceKm(5120)
        XCTAssertTrue(s.contains("5.12") || s.contains("5,12"), "Got: \(s)")
        XCTAssertTrue(s.lowercased().contains("km"), "Got: \(s)")
    }

    func testDistanceOneDecimalAtOrBeyondTen() {
        // The complication uses 2 decimals under 10 km, 1 at/over — the
        // second decimal is noise on a tiny face at marathon distances.
        let s = formatDistanceKm(21_100)
        XCTAssertTrue(s.contains("21.1") || s.contains("21,1"), "Got: \(s)")
        XCTAssertFalse(s.contains("21.10"), "At >=10 km must drop the second decimal: \(s)")
    }

    func testDistanceTenKmBoundaryUsesOneDecimal() {
        // Exactly 10.0 km is the cutoff — `value >= 10.0` selects 1 digit.
        let s = formatDistanceKm(10_000)
        XCTAssertTrue(s.contains("10.0") || s.contains("10,0"), "Got: \(s)")
        XCTAssertFalse(s.contains("10.00"), "Got: \(s)")
    }

    func testDistanceZero() {
        let s = formatDistanceKm(0)
        XCTAssertTrue(s.hasPrefix("0"), "Got: \(s)")
    }

    func testDistanceMilesConverts() {
        UserDefaults.standard.set("mi", forKey: "preferred_unit")
        let s = formatDistanceKm(1609.344)
        XCTAssertTrue(s.contains("1.00") || s.contains("1,00"), "Got: \(s)")
        XCTAssertTrue(s.lowercased().contains("mi"), "Got: \(s)")
    }
}

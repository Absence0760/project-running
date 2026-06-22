import Foundation

/// Locale-aware formatting for the on-watch run stats.
///
/// Two jobs the old `String(format:)` calls couldn't do:
///   1. The decimal separator follows `Locale.current` (a German watch
///      shows `5,12 km`, not `5.12 km`).
///   2. The distance unit word is localised by `MeasurementFormatter`,
///      and honours the user's km/mi preference — the same
///      `preferred_unit` UserDefaults key the pre-run pace presets read
///      (written by `WatchConnectivityManager` when the phone pushes a
///      unit change).
///
/// Pace is rendered as `m:ss` plus a `/km` or `/mi` suffix. The
/// minutes:seconds part is structural (a stopwatch reading, not a
/// decimal quantity) so it is not locale-separated; the reference
/// Wear OS / Flutter clients keep the `/km` suffix literal across all
/// six locales, so we match that.
enum RunFormat {
    static let metresPerMile = 1609.344

    static var prefersMiles: Bool {
        UserDefaults.standard.string(forKey: "preferred_unit") == "mi"
    }

    /// `5.12 km` / `5,12 km` / `3.18 mi`, decimal separator + unit word
    /// localised, value in the user's preferred unit.
    static func distance(metres: Double, fractionDigits: Int) -> String {
        let miles = prefersMiles
        let value = miles ? metres / metresPerMile : metres / 1000.0

        let number = NumberFormatter()
        number.locale = Locale.current
        number.numberStyle = .decimal
        number.minimumFractionDigits = fractionDigits
        number.maximumFractionDigits = fractionDigits
        number.usesGroupingSeparator = false
        let numberStr = number.string(from: NSNumber(value: value)) ?? "\(value)"

        let measurement = MeasurementFormatter()
        measurement.locale = Locale.current
        measurement.unitOptions = .providedUnit
        let unitStr = measurement.string(from: miles ? UnitLength.miles : UnitLength.kilometers)

        return "\(numberStr) \(unitStr)"
    }

    /// `5:30 /km` / `8:51 /mi`. Returns the em-dash placeholder when no
    /// pace is available yet. `secondsPerKm` is converted to the user's
    /// preferred unit before display.
    static func pace(secondsPerKm: Double?) -> String {
        guard let perKm = secondsPerKm, perKm > 0 else { return "--:--" }
        let miles = prefersMiles
        let perUnit = miles ? perKm * (metresPerMile / 1000.0) : perKm
        let total = Int(perUnit.rounded())
        let minutes = total / 60
        let seconds = total % 60
        let suffix = miles ? "/mi" : "/km"
        return String(format: "%d:%02d %@", minutes, seconds, suffix)
    }
}

// MARK: - Complication formatters
// The active-run complication (`Complications/ActiveRunComplication.swift`)
// carries a byte-identical copy of these three pure functions because it
// builds in a separate Widget Extension target that can't link this file.
// That copy is the source of truth for the widget; this copy lives in the
// WatchApp target so `ComplicationFormatterTests` can pin the contract
// without booting WidgetKit. Keep the two in lockstep.

func formatElapsed(_ seconds: Int) -> String {
    let s = max(seconds, 0)
    let h = s / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, sec)
    }
    return String(format: "%02d:%02d", m, sec)
}

func formatDistanceKm(_ meters: Double) -> String {
    let miles = UserDefaults.standard.string(forKey: "preferred_unit") == "mi"
    let metresPerMile = 1609.344
    let value = miles ? meters / metresPerMile : meters / 1000.0
    let digits = value >= 10.0 ? 1 : 2

    let number = NumberFormatter()
    number.locale = Locale.current
    number.numberStyle = .decimal
    number.minimumFractionDigits = digits
    number.maximumFractionDigits = digits
    number.usesGroupingSeparator = false
    let numberStr = number.string(from: NSNumber(value: value)) ?? "\(value)"

    let measurement = MeasurementFormatter()
    measurement.locale = Locale.current
    measurement.unitOptions = .providedUnit
    let unitStr = measurement.string(from: miles ? UnitLength.miles : UnitLength.kilometers)
    return "\(numberStr) \(unitStr)"
}

func formatPaceSecPerKm(_ secPerKm: Double?) -> String {
    let miles = UserDefaults.standard.string(forKey: "preferred_unit") == "mi"
    guard let p = secPerKm, p.isFinite, p > 0 else {
        return miles ? "—:—/mi" : "—:—/km"
    }
    let metresPerMile = 1609.344
    let perUnit = miles ? p * (metresPerMile / 1000.0) : p
    let total = Int(perUnit.rounded())
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d%@", m, s, miles ? "/mi" : "/km")
}

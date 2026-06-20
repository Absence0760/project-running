package com.runapp.watchwear.recording

import java.text.NumberFormat
import java.util.Locale

/// Locale- and unit-aware number formatting for the watch's distance /
/// pace readouts.
///
/// Two orthogonal concerns live here:
///
///  - **Decimal separator** — a runner whose watch is set to German sees
///    "5,12 km", a US runner sees "5.12 km". `String.format("%.2f", …)`
///    (no Locale) silently picks up the default locale's separator, so it
///    was already locale-sensitive but undeclared; these helpers make the
///    locale explicit and give one place to pin it.
///  - **Distance unit** — the `preferred_unit` pref (`km` | `mi`) chooses
///    whether distance is rendered in kilometres or miles and pace in
///    sec/km or sec/mi. The unit *word* ("km" / "mi") lives in
///    `strings.xml` and is applied by the caller via the unit-keyed string
///    resource; these helpers only produce the locale-formatted number and
///    do the km→mi arithmetic.

/// Metres in one international mile. The single conversion constant shared
/// by every km↔mi path on the watch.
const val METRES_PER_MILE: Double = 1609.344

/// The runner's distance-display preference. Mirrors the `preferred_unit`
/// universal setting (`'km' | 'mi'`) used across web + mobile.
enum class DistanceUnit {
    KM,
    MI;

    companion object {
        /// Resolve the pref string to a unit. Anything other than the exact
        /// `"mi"` token (null, `"km"`, a typo, a future value) falls back to
        /// kilometres — the app's default and the value the rest of the
        /// stack assumes when the pref is absent.
        fun fromPref(value: String?): DistanceUnit = if (value == "mi") MI else KM
    }
}

/// Format metres as a 2-decimal figure in the runner's [unit] and [locale]
/// — number only, no unit word. e.g. 5123.0 m → "5.12" km / "3.18" mi (en).
fun formatDistance(
    distanceM: Double,
    unit: DistanceUnit,
    locale: Locale = Locale.getDefault(),
): String = formatDistance(distanceM, unit, 2, locale)

/// Format metres in [unit] with [decimals] fraction digits in [locale].
/// Used by the tile, which drops to 1 decimal past the 10-unit mark.
fun formatDistance(
    distanceM: Double,
    unit: DistanceUnit,
    decimals: Int,
    locale: Locale = Locale.getDefault(),
): String {
    val value = when (unit) {
        DistanceUnit.KM -> distanceM / 1000.0
        DistanceUnit.MI -> distanceM / METRES_PER_MILE
    }
    val nf = NumberFormat.getNumberInstance(locale).apply {
        minimumFractionDigits = decimals
        maximumFractionDigits = decimals
        isGroupingUsed = false
    }
    return nf.format(value)
}

/// Convert a pace expressed in seconds-per-kilometre to seconds-per-[unit].
/// A km pace is already per-km; a mile pace is the same effort scaled to
/// the longer mile, so it's a larger number (a 5:00/km runner is ~8:03/mi).
fun paceSecPerUnit(secPerKm: Double, unit: DistanceUnit): Double = when (unit) {
    DistanceUnit.KM -> secPerKm
    DistanceUnit.MI -> secPerKm * (METRES_PER_MILE / 1000.0)
}

/// Format metres as a 2-decimal kilometre figure in [locale] — number
/// only, no unit word. Retained for the km-only call sites (notification,
/// recovery prompt) that don't take a unit. e.g. 5123.0 m → "5.12" (en).
fun formatKm(distanceM: Double, locale: Locale = Locale.getDefault()): String =
    formatDistance(distanceM, DistanceUnit.KM, 2, locale)

/// Format metres as a kilometre figure with [decimals] fraction digits in
/// [locale]. Retained for km-only call sites.
fun formatKm(distanceM: Double, decimals: Int, locale: Locale = Locale.getDefault()): String =
    formatDistance(distanceM, DistanceUnit.KM, decimals, locale)

package com.runapp.watchwear.recording

import java.text.NumberFormat
import java.util.Locale

/// Locale-aware number formatting for the watch's distance / pace readouts.
///
/// The point of these helpers is the *decimal separator*: a runner whose
/// watch is set to German sees "5,12 km", a US runner sees "5.12 km".
/// `String.format("%.2f", …)` (no Locale) silently picks up the default
/// locale's separator, so it was already locale-sensitive but undeclared;
/// these helpers make the locale explicit and give one place to pin the
/// behaviour. The translated unit word ("km") lives in `strings.xml` and is
/// applied by the caller via `getString(R.string.distance_km, …)`.

/// Format metres as a 2-decimal kilometre figure in [locale] — number only,
/// no unit word. e.g. 5123.0 m → "5.12" (en) / "5,12" (de).
fun formatKm(distanceM: Double, locale: Locale = Locale.getDefault()): String {
    val nf = NumberFormat.getNumberInstance(locale).apply {
        minimumFractionDigits = 2
        maximumFractionDigits = 2
        isGroupingUsed = false
    }
    return nf.format(distanceM / 1000.0)
}

/// Format metres as a kilometre figure with [decimals] fraction digits in
/// [locale]. Used by the tile, which drops to 1 decimal past 10 km.
fun formatKm(distanceM: Double, decimals: Int, locale: Locale = Locale.getDefault()): String {
    val nf = NumberFormat.getNumberInstance(locale).apply {
        minimumFractionDigits = decimals
        maximumFractionDigits = decimals
        isGroupingUsed = false
    }
    return nf.format(distanceM / 1000.0)
}

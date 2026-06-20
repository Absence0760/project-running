package com.runapp.watchwear.recording

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Locale

/// The watch follows the device locale for its distance read-outs and the
/// runner's `preferred_unit` for the km-vs-mi choice. Two load-bearing
/// behaviours are pinned here: the decimal separator (a German-locale
/// watch shows "5,12", a US one "5.12") and the km→mi conversion (distance
/// and pace). `UnitFormat.kt` is the single place both decisions are made.
class UnitFormatTest {

    @Test
    fun `formatKm uses a period in en-US`() {
        assertEquals("5.12", formatKm(5_123.0, Locale.US))
        assertEquals("0.00", formatKm(0.0, Locale.US))
        assertEquals("10.50", formatKm(10_500.0, Locale.US))
    }

    @Test
    fun `formatKm uses a comma in de-DE`() {
        assertEquals("5,12", formatKm(5_123.0, Locale.GERMANY))
        assertEquals("0,00", formatKm(0.0, Locale.GERMANY))
    }

    @Test
    fun `formatKm always emits exactly two fraction digits`() {
        // 5000 m → "5.00", not "5". The two-decimal read keeps the metric
        // line a stable width on the watch face.
        assertEquals("5.00", formatKm(5_000.0, Locale.US))
        assertEquals("5,00", formatKm(5_000.0, Locale.GERMANY))
    }

    @Test
    fun `formatKm never groups thousands`() {
        // 12 345 m = 12.35 km — no grouping separator ("12.35", not the
        // German "12,35" with a thousands dot, which would garble on the
        // tiny screen). Grouping is irrelevant under ~1000 km but pinning
        // it guards against a locale whose default turns it on.
        assertEquals("12.35", formatKm(12_345.0, Locale.US))
    }

    @Test
    fun `formatKm honours an explicit decimal count`() {
        // The tile drops to one decimal past 10 km.
        assertEquals("21.1", formatKm(21_100.0, 1, Locale.US))
        assertEquals("21,1", formatKm(21_100.0, 1, Locale.GERMANY))
        assertEquals("5.123", formatKm(5_123.0, 3, Locale.US))
    }

    @Test
    fun `default locale path does not crash and round-trips a known value`() {
        // Exercises the Locale.getDefault() overload (the production call
        // site) without asserting a separator we don't control in CI.
        val def = Locale.getDefault()
        try {
            Locale.setDefault(Locale.US)
            assertEquals("5.12", formatKm(5_123.0))
            assertEquals("21.1", formatKm(21_100.0, 1))
        } finally {
            Locale.setDefault(def)
        }
    }

    // ───────────── Mile paths ─────────────

    @Test
    fun `DistanceUnit fromPref maps only the exact mi token to miles`() {
        assertEquals(DistanceUnit.MI, DistanceUnit.fromPref("mi"))
        assertEquals(DistanceUnit.KM, DistanceUnit.fromPref("km"))
        assertEquals(DistanceUnit.KM, DistanceUnit.fromPref(null))
        // A rogue / future / typo value falls back to kilometres, the
        // app default — never throws.
        assertEquals(DistanceUnit.KM, DistanceUnit.fromPref("miles"))
        assertEquals(DistanceUnit.KM, DistanceUnit.fromPref("MI"))
        assertEquals(DistanceUnit.KM, DistanceUnit.fromPref(""))
    }

    @Test
    fun `formatDistance in km matches formatKm`() {
        assertEquals("5.12", formatDistance(5_123.0, DistanceUnit.KM, Locale.US))
        assertEquals("5,12", formatDistance(5_123.0, DistanceUnit.KM, Locale.GERMANY))
        assertEquals("21.1", formatDistance(21_100.0, DistanceUnit.KM, 1, Locale.US))
    }

    @Test
    fun `formatDistance in mi converts metres to miles`() {
        // 5123 m = 3.1833 mi → "3.18" at two decimals.
        assertEquals("3.18", formatDistance(5_123.0, DistanceUnit.MI, Locale.US))
        // Exactly one mile, two miles.
        assertEquals("1.00", formatDistance(1_609.344, DistanceUnit.MI, Locale.US))
        assertEquals("0.00", formatDistance(0.0, DistanceUnit.MI, Locale.US))
        // 10 mi at one decimal (the tile's past-10 cutoff).
        assertEquals("10.0", formatDistance(16_093.44, DistanceUnit.MI, 1, Locale.US))
    }

    @Test
    fun `formatDistance in mi follows the locale decimal separator`() {
        // German comma separator applies to miles just as it does km.
        assertEquals("3,18", formatDistance(5_123.0, DistanceUnit.MI, Locale.GERMANY))
    }

    @Test
    fun `paceSecPerUnit leaves km pace untouched`() {
        assertEquals(300.0, paceSecPerUnit(300.0, DistanceUnit.KM), 1e-9)
    }

    @Test
    fun `paceSecPerUnit scales a km pace up to the longer mile`() {
        // A 5:00/km runner covers a mile (1.609344 km) in 482.80 s.
        assertEquals(482.8032, paceSecPerUnit(300.0, DistanceUnit.MI), 1e-4)
        // 6:00/km → 579.36 s/mi.
        assertEquals(579.36384, paceSecPerUnit(360.0, DistanceUnit.MI), 1e-4)
    }
}

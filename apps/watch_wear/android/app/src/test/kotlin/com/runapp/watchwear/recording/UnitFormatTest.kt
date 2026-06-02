package com.runapp.watchwear.recording

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Locale

/// The watch follows the device locale for its distance read-outs. The
/// load-bearing behaviour is the decimal separator: a German-locale watch
/// must show "5,12 km", a US one "5.12 km". `formatKm` is the single place
/// that decision is made, so it's pinned here against a couple of locales
/// with different separators.
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
}

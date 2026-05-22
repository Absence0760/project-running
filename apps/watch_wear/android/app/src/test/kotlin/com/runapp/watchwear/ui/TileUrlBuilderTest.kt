package com.runapp.watchwear.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// Unit tests for [buildTileUrl] — the pure raster-tile URL builder
/// used by the on-watch mini-map's tile fetcher. Pins:
///
///   * Production MapTiler path (when `PUBLIC_MAPTILER_KEY` is the
///     only env source).
///   * Local Protomaps tileserver-gl dev path (when
///     `PUBLIC_TILE_URL_TEMPLATE` is set).
///   * Placeholder substitution for the dev template.
///
/// See `docs/protomaps_local_setup.md` + `decisions.md § 68`.
class TileUrlBuilderTest {

    @Test
    fun `empty template falls back to MapTiler URL with key`() {
        val url = buildTileUrl(
            z = 14, x = 8192, y = 5430,
            template = "",
            maptilerKey = "abc123",
            styleSlug = "streets-v2-dark",
        )
        assertEquals(
            "https://api.maptiler.com/maps/streets-v2-dark/14/8192/5430.png?key=abc123",
            url,
        )
    }

    @Test
    fun `blank template (whitespace) falls back to MapTiler too`() {
        // `isNotBlank` (not `isNotEmpty`) is the right gate — a
        // value like " " from a misconfigured .env.local shouldn't
        // bypass the MapTiler fallback.
        val url = buildTileUrl(
            z = 0, x = 0, y = 0,
            template = "   ",
            maptilerKey = "K",
        )
        assertTrue(
            "blank template must fall through to MapTiler",
            url.contains("api.maptiler.com"),
        )
    }

    @Test
    fun `non-blank template wins outright — local dev path`() {
        val url = buildTileUrl(
            z = 14, x = 8192, y = 5430,
            template = "http://localhost:8080/styles/basic/{z}/{x}/{y}.png",
            maptilerKey = "production-key",
        )
        assertEquals(
            "http://localhost:8080/styles/basic/14/8192/5430.png",
            url,
        )
        assertFalse(
            "override must not include the MapTiler URL",
            url.contains("maptiler.com"),
        )
        assertFalse(
            "override must not leak the MapTiler key",
            url.contains("production-key"),
        )
    }

    @Test
    fun `template placeholders substitute z + x + y literally`() {
        val url = buildTileUrl(
            z = 7,
            x = 42,
            y = 99,
            template = "http://h/p/{z}/{x}/{y}.png",
            maptilerKey = "",
        )
        assertEquals("http://h/p/7/42/99.png", url)
    }

    @Test
    fun `repeated placeholders in the template are all substituted`() {
        // Defensive: replace() is global by default. Confirm a
        // template that uses the same placeholder twice doesn't
        // leave the second one dangling.
        val url = buildTileUrl(
            z = 5, x = 1, y = 2,
            template = "http://h/{z}/{z}/{x}.png",
            maptilerKey = "",
        )
        assertEquals("http://h/5/5/1.png", url)
    }

    @Test
    fun `template without placeholders returns as-is (operator responsibility)`() {
        // tileserver-gl with a malformed template would silently
        // produce identical tiles for every grid cell — that's the
        // operator's problem to debug. The builder doesn't second-
        // guess.
        val url = buildTileUrl(
            z = 14, x = 8192, y = 5430,
            template = "http://h/fixed.png",
            maptilerKey = "",
        )
        assertEquals("http://h/fixed.png", url)
    }

    @Test
    fun `Android emulator alias 10_0_2_2 round-trips intact`() {
        // The emulator's host alias — what bin/protomaps-dev.sh tells
        // the user to use when targeting a Wear OS emulator.
        val url = buildTileUrl(
            z = 14, x = 8192, y = 5430,
            template = "http://10.0.2.2:8080/styles/basic/{z}/{x}/{y}.png",
            maptilerKey = "",
        )
        assertEquals(
            "http://10.0.2.2:8080/styles/basic/14/8192/5430.png",
            url,
        )
    }

    @Test
    fun `MapTiler styleSlug default is streets-v2-dark`() {
        val url = buildTileUrl(
            z = 0, x = 0, y = 0,
            template = "",
            maptilerKey = "K",
            // styleSlug omitted → uses default
        )
        assertTrue(url.contains("/streets-v2-dark/"))
    }

    @Test
    fun `MapTiler styleSlug override threads through`() {
        val url = buildTileUrl(
            z = 0, x = 0, y = 0,
            template = "",
            maptilerKey = "K",
            styleSlug = "outdoor-v2",
        )
        assertTrue(url.contains("/outdoor-v2/"))
    }

    @Test
    fun `MapTiler URL always uses single-resolution png (not @2x)`() {
        // The watch is a 1x display surface — high-DPI tiles would
        // burn 4x the cellular bandwidth for no visible improvement
        // on a 360×360 screen. Pin that the fallback URL does NOT
        // include the @2x suffix.
        val url = buildTileUrl(
            z = 14, x = 0, y = 0,
            template = "",
            maptilerKey = "K",
        )
        assertFalse(
            "watch tiles must NOT be @2x",
            url.contains("@2x"),
        )
        assertTrue(url.endsWith(".png?key=K"))
    }

    @Test
    fun `zoom 0 produces well-formed URL (no negative-zoom escape)`() {
        val url = buildTileUrl(
            z = 0, x = 0, y = 0,
            template = "http://h/{z}/{x}/{y}.png",
            maptilerKey = "",
        )
        assertEquals("http://h/0/0/0.png", url)
    }

    @Test
    fun `high zoom + huge x_y don't overflow the string formatting`() {
        // Smoke: x and y at zoom 20 can reach ~1 million. Make sure
        // Int.toString() handles it without exponent notation.
        val url = buildTileUrl(
            z = 20, x = 1_048_575, y = 1_048_575,
            template = "http://h/{z}/{x}/{y}.png",
            maptilerKey = "",
        )
        assertEquals("http://h/20/1048575/1048575.png", url)
    }

    // ---- URL edge cases -------------------------------------------------

    @Test
    fun `template with query params round-trips intact`() {
        // A custom local server might require an auth-token query
        // param. buildTileUrl doesn't strip, encode, or otherwise
        // mangle the URL beyond substituting placeholders.
        val url = buildTileUrl(
            z = 5, x = 1, y = 2,
            template = "http://h/t/{z}/{x}/{y}.png?token=abc&debug=1",
            maptilerKey = "",
        )
        assertEquals(
            "http://h/t/5/1/2.png?token=abc&debug=1",
            url,
        )
    }

    @Test
    fun `IPv6 bracketed-host template round-trips intact`() {
        val url = buildTileUrl(
            z = 5, x = 1, y = 2,
            template = "http://[::1]:8080/t/{z}/{x}/{y}.png",
            maptilerKey = "",
        )
        assertEquals("http://[::1]:8080/t/5/1/2.png", url)
    }

    @Test
    fun `https template round-trips intact (production-shape override)`() {
        val url = buildTileUrl(
            z = 5, x = 1, y = 2,
            template = "https://tiles.example.com/styles/basic/{z}/{x}/{y}.png",
            maptilerKey = "",
        )
        assertEquals(
            "https://tiles.example.com/styles/basic/5/1/2.png",
            url,
        )
    }
}

/// Tests for the file-level [tileSourceEnabled] helper — the
/// load-bearing OR-of-blank-checks that controls whether the
/// mini-map even attempts to render tiles.
class TileSourceEnabledTest {

    @Test
    fun `both empty → disabled (no key, no override)`() {
        assertFalse(tileSourceEnabled(template = "", maptilerKey = ""))
    }

    @Test
    fun `both blank (whitespace) → disabled (stray env-file spaces)`() {
        assertFalse(tileSourceEnabled(template = " ", maptilerKey = "\t\n"))
    }

    @Test
    fun `key-only → enabled (production path)`() {
        assertTrue(tileSourceEnabled(template = "", maptilerKey = "abc"))
    }

    @Test
    fun `template-only → enabled (local Protomaps dev path)`() {
        assertTrue(tileSourceEnabled(
            template = "http://localhost:8080/{z}/{x}/{y}.png",
            maptilerKey = "",
        ))
    }

    @Test
    fun `both set → enabled (override wins inside buildTileUrl)`() {
        // Belt-and-braces: the dev path keeps the production key in
        // .env.local so a single rebuild can flip back. Pin that
        // having both is a valid configuration.
        assertTrue(tileSourceEnabled(
            template = "http://localhost:8080/{z}/{x}/{y}.png",
            maptilerKey = "abc",
        ))
    }

    @Test
    fun `key with stray trailing newline → enabled (isNotBlank trims)`() {
        // Operator pastes a key with a trailing newline from a
        // password manager. Kotlin's `isNotBlank` treats that
        // as non-blank (newlines are whitespace, but the content
        // before the newline is real). Pin the behavior.
        assertTrue(tileSourceEnabled(
            template = "",
            maptilerKey = "abc\n",
        ))
    }
}

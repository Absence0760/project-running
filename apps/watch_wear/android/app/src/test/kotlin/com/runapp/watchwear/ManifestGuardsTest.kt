package com.runapp.watchwear

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level guards for the Wear OS AndroidManifest. The audit pass
/// flagged two manifest issues Play reviewers regress on: a redundant
/// application-level cleartext-traffic flag, and missing background
/// HR access on Wear OS 3.5+ (API 34+). These tests pin both in place.
///
/// Pure-JVM JUnit, no Robolectric — matches the rest of the test
/// module's "read the source, assert a pattern" pattern (see
/// `RoutesBridgeWiringTest`, `ScreenWiringTest`).
class ManifestGuardsTest {

    private val manifest: String by lazy {
        File("src/main/AndroidManifest.xml").readText()
    }

    @Test
    fun `BODY_SENSORS_BACKGROUND is declared`() {
        // Why: BODY_SENSORS alone covers foreground HR access only.
        // On Wear OS 3.5+ (API 34+) the platform stops delivering
        // Health Services samples once the display goes ambient.
        // Long runs silently drop avg_bpm without this permission.
        // Play Data Safety must list the same set the binary actually
        // requests; mismatches trigger reviewer flags.
        assertTrue(
            "AndroidManifest.xml must declare BODY_SENSORS_BACKGROUND " +
                "so HR keeps streaming when the watch dims.",
            manifest.contains(
                "android.permission.BODY_SENSORS_BACKGROUND"
            ),
        )
    }

    @Test
    fun `application does not set usesCleartextTraffic=true`() {
        // Why: the network security config (res/xml/network_security_config.xml)
        // is the canonical mechanism — it whitelists 10.0.2.2 (the
        // emulator host) and nothing else. The application-level
        // attribute is redundant for actual behaviour, but Play
        // reviewers read it without cross-checking the NSC and flag
        // it as a security gap on the manifest scan.
        val applicationOpenTag = Regex(
            """<application\b[^>]*>""",
            RegexOption.DOT_MATCHES_ALL,
        ).find(manifest)?.value
            ?: error("Could not find <application> element in manifest")
        assertFalse(
            "<application> must not set android:usesCleartextTraffic=\"true\". " +
                "The networkSecurityConfig attribute carries the same intent " +
                "with a tighter scope; Play reviewers flag the redundant attribute.",
            applicationOpenTag.contains("usesCleartextTraffic=\"true\""),
        )
    }

    @Test
    fun `networkSecurityConfig is still wired`() {
        // Why: the previous test removes the broad cleartext-traffic
        // toggle, but the dev-loopback NSC must stay attached
        // otherwise local Supabase (http://10.0.2.2:54321) becomes
        // unreachable in debug builds.
        val applicationOpenTag = Regex(
            """<application\b[^>]*>""",
            RegexOption.DOT_MATCHES_ALL,
        ).find(manifest)?.value
            ?: error("Could not find <application> element in manifest")
        assertTrue(
            "<application> must still declare " +
                "android:networkSecurityConfig=\"@xml/network_security_config\"",
            applicationOpenTag.contains(
                "networkSecurityConfig=\"@xml/network_security_config\""
            ),
        )
        assertTrue(
            "res/xml/network_security_config.xml must exist",
            File("src/main/res/xml/network_security_config.xml").exists(),
        )
    }
}

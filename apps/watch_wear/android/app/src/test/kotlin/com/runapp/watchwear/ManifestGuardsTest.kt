package com.runapp.watchwear

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level guards for the Wear OS AndroidManifest. The audit pass
/// flagged two manifest issues Play reviewers regress on: a redundant
/// application-level cleartext-traffic flag, and a body-sensor
/// permission the app can neither obtain nor use. These tests pin both.
///
/// Pure-JVM JUnit, no Robolectric — matches the rest of the test
/// module's "read the source, assert a pattern" pattern (see
/// `RoutesBridgeWiringTest`, `ScreenWiringTest`).
class ManifestGuardsTest {

    private val manifest: String by lazy {
        File("src/main/AndroidManifest.xml").readText()
    }

    @Test
    fun `BODY_SENSORS_BACKGROUND is not declared`() {
        // Why, and this reverses what this guard used to assert: the
        // permission was declared for two years on the claim that HR
        // "stops streaming once the display goes ambient" without it.
        // Two facts kill that claim. It was never passed to
        // `permissionLauncher.launch`, so no watch has ever granted it
        // — a declared-and-unrequested runtime permission is inert.
        // And it is not the permission this app's heart rate depends
        // on: Health Services documents BODY_SENSORS_BACKGROUND against
        // PassiveMonitoringClient, while `HeartRateMonitor` uses
        // MeasureClient, whose background access is documented as "no"
        // and is not something a permission grant changes. What DOES
        // govern sensor access from the recording service is the
        // foreground-service type it starts with, guarded separately in
        // `ManifestPermissionCoverageTest`.
        //
        // So the declaration bought no capability and cost a sensor
        // permission on the install prompt and the Play Data Safety
        // form. Re-adding it needs a MeasureClient -> ExerciseClient
        // migration to be worth anything, and that is a code change
        // this guard should see first.
        assertFalse(
            "AndroidManifest.xml must not declare BODY_SENSORS_BACKGROUND — " +
                "it gates PassiveMonitoringClient, and this app reads heart " +
                "rate through MeasureClient.",
            manifest.contains(
                "android.permission.BODY_SENSORS_BACKGROUND"
            ),
        )
        assertTrue(
            "BODY_SENSORS itself must stay declared — MeasureClient needs it",
            Regex("""<uses-permission\s+android:name="android\.permission\.BODY_SENSORS"\s*/>""")
                .containsMatchIn(manifest),
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

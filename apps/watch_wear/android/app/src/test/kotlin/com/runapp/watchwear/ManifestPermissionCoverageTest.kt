package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// A declared permission and a requested permission are two different
/// facts, and nothing in this module connected them.
///
/// `AndroidManifest.xml` declares what the app MAY hold;
/// `RunWatchApp.kt`'s `permissionLauncher.launch(...)` is the only place the
/// app ever ASKS for one. A runtime permission that appears in the first list
/// and not the second is never granted on any watch — and the failure is
/// invisible from inside the app, because the code that depends on it goes on
/// calling the API and the platform simply withholds the effect. That is how
/// `POST_NOTIFICATIONS` sat declared-but-unrequested: the recording service
/// posts its `OngoingActivity` notification on every tick, `startForeground`
/// succeeds, and on API 33+ the notification is kept out of the shade — so
/// the runner loses the ongoing-activity chip that is their way back into a
/// live run from the watch face, with nothing anywhere reporting an error.
///
/// The requirement is DERIVED from the manifest rather than listed here: a
/// hand-written list would cover the permissions someone remembered on the
/// day, and a permission added to the manifest tomorrow would be covered by
/// nothing. Everything the manifest declares is therefore held to one of
/// three answers — requested at runtime, install-time (so there is nothing to
/// request), or a registered exemption carrying its reason. An exemption
/// naming a permission the manifest no longer declares fails too, so the
/// register cannot go stale in the quiet direction.
class ManifestPermissionCoverageTest {

    private val manifest: String by lazy {
        File("src/main/AndroidManifest.xml").readText()
    }

    private val requestSite: String by lazy {
        File("src/main/kotlin/com/runapp/watchwear/ui/RunWatchApp.kt").readText()
    }

    /// Granted at install with no dialog, so "did we request it" is not a
    /// question that can be asked of them.
    private val installTime = setOf(
        "INTERNET",
        "ACCESS_NETWORK_STATE",
        "WAKE_LOCK",
        "FOREGROUND_SERVICE",
        "FOREGROUND_SERVICE_LOCATION",
        "FOREGROUND_SERVICE_HEALTH",
        // Not a dialog either: it only permits LAUNCHING the system
        // whitelist prompt, which `system/BatteryOptimization.kt` does.
        "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
    )

    /// Runtime permissions the app deliberately does not ask for, each with
    /// the reason. Anything not here and not install-time must be in the
    /// launch array.
    private val exempt = mapOf(
        "ACCESS_COARSE_LOCATION" to
            "the platform grants it alongside ACCESS_FINE_LOCATION, which IS " +
                "requested; asking for both separately offers the runner an " +
                "approximate-location choice that would silently degrade the " +
                "GPS trace",
    )

    private fun declaredPermissions(): Set<String> =
        Regex("""<uses-permission\s+android:name="android\.permission\.([A-Z_0-9]+)"""")
            .findAll(manifest)
            .map { it.groupValues[1] }
            .toSet()

    private fun requestedPermissions(): Set<String> =
        Regex("""Manifest\.permission\.([A-Z_0-9]+)""")
            .findAll(requestSite)
            .map { it.groupValues[1] }
            .toSet()

    @Test
    fun `the manifest declares a permission set this guard can read`() {
        // A regex that silently stops matching would make every assertion
        // below pass vacuously.
        val declared = declaredPermissions()
        assertTrue(
            "no <uses-permission> parsed out of the manifest — the guard is " +
                "reading nothing and would pass on anything",
            declared.size >= 8,
        )
        assertTrue(
            "ACCESS_FINE_LOCATION must parse out — it is the one permission " +
                "without which the app has no product",
            "ACCESS_FINE_LOCATION" in declared,
        )
    }

    @Test
    fun `every runtime permission the manifest declares is requested or exempted`() {
        val unaccounted = (declaredPermissions() - installTime - exempt.keys - requestedPermissions())
            .sorted()
        assertEquals(
            "declared in AndroidManifest.xml but never requested at runtime, " +
                "so it can never be granted: $unaccounted. Add it to the " +
                "permissionLauncher.launch array in RunWatchApp.kt, or register " +
                "it in this test's `exempt` map with the reason.",
            emptyList<String>(),
            unaccounted,
        )
    }

    @Test
    fun `the notification permission is requested, and behind the API gate`() {
        // The regression this guard was written for. POST_NOTIFICATIONS did
        // not exist before API 33 and minSdk here is 30, so it is requested
        // conditionally — but the condition must not be what removes it.
        assertTrue(
            "POST_NOTIFICATIONS must be requested — the ongoing-activity " +
                "notification is the runner's route back into a live run",
            "POST_NOTIFICATIONS" in requestedPermissions(),
        )
        assertTrue(
            "the POST_NOTIFICATIONS request must sit behind a TIRAMISU " +
                "version gate (minSdk is 30 and the permission is API 33+)",
            requestSite.contains("Build.VERSION_CODES.TIRAMISU"),
        )
    }

    @Test
    fun `no exemption outlives the permission it excuses`() {
        val declared = declaredPermissions()
        val stale = exempt.keys.filter { it !in declared }.sorted()
        assertEquals(
            "exempted from the runtime request but no longer declared in the " +
                "manifest: $stale. Drop the entry — an exemption for a " +
                "permission that does not exist reads as coverage and is none.",
            emptyList<String>(),
            stale,
        )
        val pointless = exempt.keys.filter { it in requestedPermissions() }.sorted()
        assertEquals(
            "exempted from the runtime request AND requested anyway: " +
                "$pointless. One of the two is wrong.",
            emptyList<String>(),
            pointless,
        )
    }

    @Test
    fun `the foreground service enumerates every type its permissions claim`() {
        // FOREGROUND_SERVICE_HEALTH without "health" in foregroundServiceType
        // is a SecurityException the moment the service starts on API 34+,
        // and the service reads heart rate on every run. The two halves live
        // in different elements of the same file and neither implies the
        // other.
        val serviceTag = Regex(
            """<service\b[^>]*RunRecordingService[^>]*/>""",
            RegexOption.DOT_MATCHES_ALL,
        ).find(manifest)?.value
            ?: error("Could not find the RunRecordingService <service> element")
        val types = Regex("""foregroundServiceType="([^"]+)"""")
            .find(serviceTag)?.groupValues?.get(1)
            ?.split('|')?.map { it.trim() }?.toSet()
            ?: error("RunRecordingService declares no foregroundServiceType")
        val declared = declaredPermissions()
        val expected = buildSet {
            if ("FOREGROUND_SERVICE_LOCATION" in declared) add("location")
            if ("FOREGROUND_SERVICE_HEALTH" in declared) add("health")
        }
        assertEquals(
            "every FOREGROUND_SERVICE_<TYPE> permission the manifest declares " +
                "must appear in the service's foregroundServiceType, and " +
                "vice versa",
            expected,
            types,
        )
    }
}

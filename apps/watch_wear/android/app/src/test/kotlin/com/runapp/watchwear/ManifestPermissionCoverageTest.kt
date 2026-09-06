package com.runapp.watchwear

import android.content.pm.ServiceInfo
import android.os.Build
import com.runapp.watchwear.recording.RunRecordingService
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

    private val serviceSource: String by lazy {
        File(
            "src/main/kotlin/com/runapp/watchwear/recording/RunRecordingService.kt",
        ).readText()
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
        // Normal permission. `Vibrator.vibrate` is still refused without the
        // DECLARATION, which is the other direction this class now checks.
        "VIBRATE",
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

    /// Platform APIs this module calls that the system refuses without a
    /// manifest declaration, and the permission each one needs.
    ///
    /// The OTHER direction from every test above, and the one nothing checked:
    /// those hold the manifest to the request site, so a permission declared
    /// and never asked for is caught, while a permission CALLED FOR and never
    /// declared is not — and that failure is quieter still. `Vibrator.vibrate`
    /// throws `SecurityException` across the binder with no declaration, the
    /// call site catches `Throwable` because a watch may genuinely have no
    /// vibrator, and the two are indistinguishable from inside the app: the
    /// pace alert's haptic had therefore never fired on any watch, on any
    /// build, and read as hardware (decisions § 1302).
    ///
    /// Keyed on the API rather than on a receiver name, because the
    /// requirement belongs to the call and not to whatever a local happens to
    /// be called this month.
    private val permissionGatedApis = mapOf(
        Regex("""\.vibrate\(""") to "VIBRATE",
    )

    private fun mainSources(): List<File> =
        File("src/main/kotlin").walkTopDown().filter { it.extension == "kt" }.toList()

    @Test
    fun `every permission-gated API this module calls is declared`() {
        val sources = mainSources().map { it.readText() }
        assertTrue("no Kotlin sources found — the scan is reading nothing", sources.size >= 10)
        val declared = declaredPermissions()
        val called = permissionGatedApis.filterKeys { re -> sources.any { re.containsMatchIn(it) } }
        // A table whose every entry has stopped matching is a guard asleep,
        // not a clean tree: the calls it names are all still made.
        assertEquals(
            "no permission-gated API matched anywhere under src/main — either " +
                "every call was removed (drop the table entries) or the patterns " +
                "have gone stale",
            permissionGatedApis.size,
            called.size,
        )
        val undeclared = called.values.filterNot { it in declared }.sorted()
        assertEquals(
            "called from src/main but never declared in AndroidManifest.xml, so " +
                "the platform refuses it on every device: $undeclared. The call " +
                "site's catch cannot tell you — it looks like absent hardware.",
            emptyList<String>(),
            undeclared,
        )
    }

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

    private fun declaredServiceTypes(): Set<String> {
        val serviceTag = Regex(
            """<service\b[^>]*RunRecordingService[^>]*/>""",
            RegexOption.DOT_MATCHES_ALL,
        ).find(manifest)?.value
            ?: error("Could not find the RunRecordingService <service> element")
        return Regex("""foregroundServiceType="([^"]+)"""")
            .find(serviceTag)?.groupValues?.get(1)
            ?.split('|')?.map { it.trim() }?.toSet()
            ?: error("RunRecordingService declares no foregroundServiceType")
    }

    @Test
    fun `the foreground service enumerates every type its permissions claim`() {
        // FOREGROUND_SERVICE_HEALTH without "health" in foregroundServiceType
        // is a SecurityException the moment the service starts on API 34+,
        // and the service reads heart rate on every run. The two halves live
        // in different elements of the same file and neither implies the
        // other.
        val types = declaredServiceTypes()
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

    @Test
    fun `the service starts with every foreground-service type the manifest declares`() {
        // The manifest and `startForeground` are two separate declarations
        // of the same fact and neither implies the other. From API 34 it is
        // the RUNTIME mask that decides whether a service may keep using a
        // while-in-use permission while the app is not visible — so a
        // manifest that says `location|health` while the code passes
        // LOCATION alone buys the app a sensor permission, a
        // FOREGROUND_SERVICE_HEALTH declaration and a Play Data Safety line
        // for a service type it never actually starts as. That was the
        // state here: the manifest half of the 2026-05-30 store-privacy
        // audit landed and the code half did not.
        //
        // Derived from the manifest, not listed: adding a third type
        // tomorrow is covered by this without anyone remembering to.
        val missing = declaredServiceTypes()
            .map { "FOREGROUND_SERVICE_TYPE_" + it.uppercase() }
            .filterNot { serviceSource.contains(it) }
            .sorted()
        assertEquals(
            "declared in the manifest's foregroundServiceType but never " +
                "passed to startForeground in RunRecordingService.kt: " +
                "$missing. Either pass the type or stop declaring it.",
            emptyList<String>(),
            missing,
        )
    }

    @Test
    fun `the health service type is withheld until its prerequisite is granted`() {
        // Passing FOREGROUND_SERVICE_TYPE_HEALTH before BODY_SENSORS or
        // ACTIVITY_RECOGNITION has been granted is refused by the platform,
        // not ignored — and a runner is entitled to decline both and still
        // record a GPS run. So the mask is computed, and the health bit is
        // the conditional half.
        val location = ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
        val health = ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
        val api34 = Build.VERSION_CODES.UPSIDE_DOWN_CAKE
        // Two distinct non-zero bits, or every equality below holds for
        // any mask at all and the test asserts nothing.
        assertTrue(
            "the platform type constants must be distinct non-zero bits, " +
                "got location=$location health=$health",
            location != 0 && health != 0 && (location and health) == 0,
        )

        assertEquals(
            "both granted-prerequisite and API 34+ must yield location|health",
            location or health,
            RunRecordingService.foregroundServiceTypeMask(api34, true),
        )
        assertEquals(
            "no body-sensor or activity permission means location alone",
            location,
            RunRecordingService.foregroundServiceTypeMask(api34, false),
        )
        assertEquals(
            "the health type does not exist before API 34",
            location,
            RunRecordingService.foregroundServiceTypeMask(api34 - 1, true),
        )
        assertTrue(
            "location is unconditional — it is what the run itself needs",
            (0..2).all { i ->
                val m = RunRecordingService.foregroundServiceTypeMask(
                    api34 - 1 + i,
                    i % 2 == 0,
                )
                m and location == location
            },
        )
    }
}

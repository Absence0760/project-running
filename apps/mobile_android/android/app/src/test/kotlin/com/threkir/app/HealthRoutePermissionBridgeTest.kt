package com.threkir.app

import org.junit.Assert.assertEquals
import org.junit.Test

/// Pins the two cross-language wire-format constants
/// [HealthRoutePermissionBridge] depends on. Neither is checked by a
/// compiler: [HealthRoutePermissionBridge.PERMISSION] is inlined from the
/// androidx constant, so a library rename would silently change what the app
/// asks Health Connect for while `AndroidManifest.xml` and
/// `res/xml/health_permissions.xml` kept declaring the old string — and a
/// permission that isn't declared is refused with no dialog. [CHANNEL] is
/// matched only by an identical string literal in
/// `lib/health_connect_importer.dart`; drift means the Dart call falls into
/// its catch and every runner sees a silent refusal.
///
/// The launcher + method-channel surfaces can't run on a host JVM, so these
/// constants are the testable seam — same convention as
/// [WearRoutesBridgeArgsTest].
class HealthRoutePermissionBridgeTest {

    @Test
    fun `PERMISSION is the string declared in the manifest and permissions xml`() {
        assertEquals(
            "android.permission.health.READ_EXERCISE_ROUTES",
            HealthRoutePermissionBridge.PERMISSION,
        )
    }

    @Test
    fun `PERMISSION is the plural read form, not the singular write one`() {
        // WRITE_EXERCISE_ROUTE is singular and is a different grant entirely;
        // asking for it here would request write access to the runner's
        // location history while buying no read access at all.
        assertEquals(true, HealthRoutePermissionBridge.PERMISSION.endsWith("ROUTES"))
        assertEquals(
            false,
            HealthRoutePermissionBridge.PERMISSION.contains("WRITE"),
        )
    }

    @Test
    fun `CHANNEL matches the Dart healthRoutePermissionChannel name`() {
        assertEquals(
            "run_app/health_route_permission",
            HealthRoutePermissionBridge.CHANNEL,
        )
    }
}

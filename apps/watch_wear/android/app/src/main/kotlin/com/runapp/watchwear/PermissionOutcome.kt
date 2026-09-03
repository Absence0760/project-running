package com.runapp.watchwear

import android.Manifest

/// What declining one of the pre-run permissions actually costs the
/// runner. The order of the entries is the order the notice renders in,
/// so the same denial set always reads the same way.
enum class PermissionCost {
    /// Blocking. Without it there is no route, no distance and no pace —
    /// only the clock — so the run does not start.
    Location,
    HeartRate,
    Steps,
    OngoingNotification,
}

/// The pre-run permission dialog's result, graded.
///
/// `RunWatchApp`'s callback used to be `if (granted[FINE_LOCATION] == true)
/// { showCountdown = true }` with no else: a runner who declined got no
/// countdown, no message and no state change, which on a screen with no
/// keyboard reads as a broken GO button. The gate itself was right and
/// stays — what was missing is the report.
data class PermissionOutcome(
    val canStart: Boolean,
    val costs: List<PermissionCost>,
)

/// Grade the `RequestMultiplePermissions` result map.
///
/// An ABSENT key is not a denial: `POST_NOTIFICATIONS` is only requested
/// from API 33, so on a Wear OS 3 watch it never appears in the map and
/// must not be reported as something the runner turned off. Only an
/// explicit `false` costs anything.
fun permissionOutcome(granted: Map<String, Boolean>): PermissionOutcome {
    fun denied(permission: String): Boolean = granted[permission] == false

    val costs = buildList {
        if (denied(Manifest.permission.ACCESS_FINE_LOCATION)) add(PermissionCost.Location)
        if (denied(Manifest.permission.BODY_SENSORS)) add(PermissionCost.HeartRate)
        if (denied(Manifest.permission.ACTIVITY_RECOGNITION)) add(PermissionCost.Steps)
        if (denied(Manifest.permission.POST_NOTIFICATIONS)) {
            add(PermissionCost.OngoingNotification)
        }
    }
    return PermissionOutcome(
        canStart = granted[Manifest.permission.ACCESS_FINE_LOCATION] == true,
        costs = costs,
    )
}

/// Whether this GO tap should stop at the notice instead of counting down.
///
/// A run that cannot start ALWAYS stops here — including the degenerate
/// case where the result map named nothing at all, because a GO tap that
/// changes nothing on screen is precisely the defect this exists to close.
/// A runnable-but-degraded set stops once: a runner who has permanently
/// declined step counting should not re-read that card before every run.
fun shouldInterruptForCosts(outcome: PermissionOutcome, alreadyShown: Boolean): Boolean =
    !outcome.canStart || (outcome.costs.isNotEmpty() && !alreadyShown)

package com.threkir.app

import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Asks Health Connect for READ_EXERCISE_ROUTES, the separate grant that
/// releases a workout's GPS route alongside its summary.
///
/// Nothing else in the app can ask for it: the `health` plugin maps
/// WORKOUT_ROUTE *read* access onto the exercise-session read permission
/// alone (`HealthDataOperations.preparePermissionsListInternal`), so without
/// this bridge the grant is only reachable from inside the Health Connect
/// app. Dart side is `lib/health_connect_importer.dart`.
///
/// Construction and channel attachment are separate because they have to
/// happen at different times: `registerForActivityResult` must run before the
/// activity is CREATED, while the messenger only exists once the Flutter
/// engine is configured — which under `FlutterFragmentActivity` can be as
/// late as `onStart`, since the FlutterFragment is added with `commit()`.
class HealthRoutePermissionBridge(private val activity: ComponentActivity) :
    MethodChannel.MethodCallHandler {

    private var pending: MethodChannel.Result? = null

    private val launcher: ActivityResultLauncher<Set<String>> =
        activity.registerForActivityResult(
            PermissionController.createRequestPermissionResultContract(),
        ) { granted -> settle(granted.contains(PERMISSION)) }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestRoutePermission" -> requestRoutePermission(result)
            else -> result.notImplemented()
        }
    }

    private fun requestRoutePermission(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("in_flight", "A route-permission request is already open", null)
            return
        }
        if (HealthConnectClient.getSdkStatus(activity) !=
            HealthConnectClient.SDK_AVAILABLE
        ) {
            result.success(false)
            return
        }
        pending = result
        try {
            launcher.launch(setOf(PERMISSION))
        } catch (e: Exception) {
            settle(false)
        }
    }

    private fun settle(granted: Boolean) {
        val result = pending ?: return
        pending = null
        result.success(granted)
    }

    companion object {
        const val CHANNEL = "run_app/health_route_permission"

        /// Routes and nothing else. The exercise-session read is already held
        /// by the time this is reachable, and every permission added here is
        /// one the Play Data Safety declaration has to carry.
        const val PERMISSION = HealthPermission.PERMISSION_READ_EXERCISE_ROUTES
    }
}

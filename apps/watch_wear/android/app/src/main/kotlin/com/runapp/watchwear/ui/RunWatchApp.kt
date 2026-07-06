package com.runapp.watchwear.ui

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExitToApp
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.foundation.lazy.AutoCenteringParams
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.foundation.rotary.RotaryScrollableDefaults
import androidx.wear.compose.foundation.rotary.rotaryScrollable
import androidx.wear.compose.foundation.lazy.ScalingLazyListState
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.CompactButton
import androidx.wear.compose.material.CompactChip
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.Vignette
import androidx.wear.compose.material.VignettePosition
import com.runapp.watchwear.R
import com.runapp.watchwear.RunViewModel
import com.runapp.watchwear.Stage
import com.runapp.watchwear.hrZoneOf
import com.runapp.watchwear.recording.formatKm
import com.runapp.watchwear.system.BatteryOptimization
import android.app.Activity
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Shadow

@Composable
fun RunWatchApp(vm: RunViewModel, activity: Activity, isAmbient: Boolean = false) {
    val state by vm.state.collectAsStateWithLifecycle()
    // Brief 3-2-1 overlay between permission grant and the ViewModel's
    // `start()` call. UI-only — the recording service isn't live during
    // the countdown. Mirrors the user-visible behaviour on Android.
    var showCountdown by remember { mutableStateOf(false) }
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions(),
    ) { granted ->
        if (granted[Manifest.permission.ACCESS_FINE_LOCATION] == true) {
            showCountdown = true
        }
    }
    // Warm-fetch tiles around the runner's last-known location while
    // the 3-second countdown plays. Riding the countdown means the
    // running screen's first frame already has tiles in cache —
    // otherwise it would draw the polyline + position dot on the
    // midnight background until the first HTTP fetch lands.
    LaunchedEffect(showCountdown) {
        if (showCountdown) vm.prefetchTilesForRunStart()
    }

    DuskTheme {
        Scaffold(
            timeText = { TimeText() },
            vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        ) {
            when (state.stage) {
                Stage.PreRun -> {
                    var batteryHelp by remember { mutableStateOf(false) }
                    // Auto-dismiss the instruction card when the user has
                    // actually granted the exemption — VM state flips from
                    // `batteryOptimised = true` → `false`.
                    LaunchedEffect(state.batteryOptimised) {
                        if (!state.batteryOptimised) batteryHelp = false
                    }
                    if (batteryHelp) {
                        BatteryInstructions(
                            // Samsung One UI Watch: the auto-open intent is a
                            // no-op, so lead with the Galaxy Wearable manual
                            // path and hide the dead button (persona #35).
                            samsung = BatteryOptimization.recommendsManualGuidance(),
                            onTryAutoOpen = {
                                BatteryOptimization.requestExemption(activity)
                            },
                            onClose = { batteryHelp = false },
                        )
                    } else {
                        PreRunScreen(
                            queuedCount = state.queuedCount,
                            syncing = state.syncing,
                            authed = state.authed,
                            authError = state.authError,
                            online = state.online,
                            batteryOptimised = state.batteryOptimised,
                            batteryPercent = state.batteryPercent,
                            pendingRecoveryDistance = state.pendingRecovery?.distanceM,
                            activityType = state.activityType,
                            activeRace = state.activeRace,
                            selectedRouteName = state.selectedRoute?.name,
                            selectedRouteWaypoints = state.selectedRoute?.toLatLngs() ?: emptyList(),
                            targetPaceSecPerKm = state.targetPaceSecPerKm,
                            onCycleActivity = {
                                val order = listOf("run", "walk", "hike", "cycle")
                                val next = order[(order.indexOf(state.activityType) + 1) % order.size]
                                vm.setActivityType(next)
                            },
                            onCyclePace = vm::cycleTargetPace,
                            onOpenRoutePicker = vm::openRoutePicker,
                            onStart = {
                                permissionLauncher.launch(
                                    arrayOf(
                                        Manifest.permission.ACCESS_FINE_LOCATION,
                                        Manifest.permission.BODY_SENSORS,
                                        // Needed for `TYPE_STEP_COUNTER` on
                                        // API 29+. Granting is not blocking
                                        // — the step flow is silent if the
                                        // user denies.
                                        Manifest.permission.ACTIVITY_RECOGNITION,
                                    )
                                )
                            },
                            onSignIn = vm::openSignIn,
                            onSignOut = vm::signOut,
                            onFixBattery = { batteryHelp = true },
                            onRecover = vm::recoverCheckpoint,
                            onDiscardRecovery = vm::discardCheckpoint,
                            onSync = vm::sync,
                        )
                    }
                }
                Stage.SignIn -> SignInScreen(
                    authError = state.authError,
                    loading = state.signInLoading,
                    onSubmit = vm::signInWithEmail,
                    onCancel = vm::cancelSignIn,
                )
                Stage.Running, Stage.Paused -> RunningScreen(
                    elapsedMs = state.elapsedMs,
                    distanceM = state.distanceM,
                    paceSecPerKm = state.paceSecPerKm,
                    preferredUnit = state.preferredUnit,
                    bpm = state.bpm,
                    hrZoneCutoffs = state.hrZoneCutoffs,
                    steps = state.steps,
                    lapCount = state.lapCount,
                    paused = state.stage == Stage.Paused,
                    locationAvailable = state.locationAvailable,
                    // `distanceM == 0.0` is the poor man's "no point yet"
                    // check — the recorder only moves the counter when
                    // GPS has delivered its first usable fix. Combined
                    // with `locationAvailable=false` it tells us the run
                    // is indoor / no-GPS rather than mid-run signal loss.
                    noGpsYet = state.distanceM == 0.0,
                    offRouteDistanceM = state.offRouteDistanceM,
                    routeRemainingM = state.routeRemainingM,
                    routeWaypoints = state.routeWaypoints,
                    latestPoint = state.latestPoint,
                    fallbackLatLng = state.lastKnownLatLng,
                    trackOverlayPoints = state.trackOverlayPoints,
                    ambient = isAmbient,
                    onPause = vm::pause,
                    onResume = vm::resume,
                    onLap = vm::markLap,
                    onStop = vm::stop,
                )
                Stage.PostRun -> PostRunScreen(
                    summary = state.lastRunSummary,
                    bodyWeightKg = state.bodyWeightKg,
                    preferredUnit = state.preferredUnit,
                    synced = state.thisRunSynced,
                    syncing = state.syncing,
                    syncError = state.syncError,
                    onSync = vm::sync,
                    onStartNext = vm::startNextRun,
                    onDiscard = vm::discard,
                )
                Stage.RoutePicker -> RoutePickerScreen(
                    routes = state.routes,
                    selectedId = state.selectedRoute?.id,
                    loading = state.routesLoading,
                    preferredUnit = state.preferredUnit,
                    onPick = vm::selectRoute,
                    onClear = vm::clearSelectedRoute,
                    onCancel = vm::closeRoutePicker,
                )
            }

            if (showCountdown) {
                CountdownOverlay(
                    routeWaypoints = state.selectedRoute?.toLatLngs() ?: emptyList(),
                    previewLatLng = state.lastKnownLatLng,
                    onComplete = {
                        showCountdown = false
                        vm.start()
                    },
                    onCancel = { showCountdown = false },
                )
            }
        }
    }
}

/// Full-screen 3-2-1 countdown shown between permission grant and the
/// ViewModel's `start()`. A tap anywhere cancels and returns to PreRun.
///
/// Doubles as a pre-warm window for the running screen: the map
/// renders full-screen *behind* the digit, populated from
/// `lastKnownLatLng` (kicked off by `prefetchTilesForRunStart`). By
/// the time the count hits 1 and `start()` flips the stage, tiles
/// are decoded and on-screen — no flash-to-midnight transition.
@Composable
private fun CountdownOverlay(
    routeWaypoints: List<com.runapp.watchwear.recording.RouteMath.LatLng>,
    previewLatLng: com.runapp.watchwear.recording.RouteMath.LatLng?,
    onComplete: () -> Unit,
    onCancel: () -> Unit,
) {
    var count by remember { mutableIntStateOf(3) }
    LaunchedEffect(Unit) {
        // 3 → 2 → 1, one second each, then fire `onComplete`.
        for (n in 3 downTo 1) {
            count = n
            delay(1000L)
        }
        onComplete()
    }
    val cancelCountdownCd = stringResource(R.string.cd_cancel_countdown)
    Box(
        modifier = Modifier
            .fillMaxSize()
            .clickable(onClick = onCancel)
            .semantics {
                contentDescription = cancelCountdownCd
                role = Role.Button
            },
        contentAlignment = Alignment.Center,
    ) {
        // Map underlay: route polyline + tiles centred on the
        // last-known fix so the runner sees the streets they're
        // about to run while the digit plays. When neither a route
        // nor a fix exists yet (cold launch indoor / no GPS), the
        // mini-map's own midnight background takes over — same as
        // the in-run no-fix branch.
        if (routeWaypoints.isNotEmpty() || previewLatLng != null) {
            RouteMiniMap(
                route = routeWaypoints,
                current = previewLatLng,
                modifier = Modifier.fillMaxSize(),
                clipShape = androidx.compose.ui.graphics.RectangleShape,
            )
        } else {
            // Fall back to the old solid-black backdrop so the digit
            // pops on watches with no last-known location yet.
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.92f)),
            )
        }
        // Soft scrim only behind the digit so the map stays visible
        // around the edges. 0.45 alpha is enough that the digit's
        // strokes don't have to fight tile contrast, much less than
        // the old 0.92 that hid the map entirely.
        if (routeWaypoints.isNotEmpty() || previewLatLng != null) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.45f)),
            )
        }
        Text(
            count.toString(),
            style = MaterialTheme.typography.display1.copy(
                shadow = Shadow(Color.Black.copy(alpha = 0.8f), Offset(0f, 2f), 8f),
            ),
            color = DuskPalette.parchment,
            fontSize = 84.sp,
        )
    }
}

/// Full-screen instruction card explaining how to grant battery-opt
/// exemption. Replaces a silent `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
/// intent launch — on many Wear OS builds that intent resolves but the
/// actual Activity is a no-op stub. The card gives the user a reliable
/// manual path plus a "Try auto-open" button for watches where the
/// intent does work.
@Composable
private fun BatteryInstructions(
    samsung: Boolean,
    onTryAutoOpen: () -> Unit,
    onClose: () -> Unit,
) {
    val listState = rememberScalingLazyListState()
    // Rotary bezel / crown drives the scroll (Galaxy Watch physical
    // bezel, Pixel Watch crown). Without this the only way down a list
    // longer than the screen is a touch drag. Persona samsung #32.
    val rotaryFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) { rotaryFocus.requestFocus() }
    ScalingLazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .rotaryScrollable(
                RotaryScrollableDefaults.behavior(scrollableState = listState),
                focusRequester = rotaryFocus,
            ),
        state = listState,
        horizontalAlignment = Alignment.CenterHorizontally,
        autoCentering = AutoCenteringParams(itemIndex = 0),
        contentPadding = PaddingValues(horizontal = 14.dp),
    ) {
        item {
            Text(
                stringResource(R.string.battery_allow_background),
                style = MaterialTheme.typography.title3,
                textAlign = TextAlign.Center,
            )
        }
        item {
            Text(
                if (samsung) {
                    stringResource(R.string.battery_samsung_summary)
                } else {
                    stringResource(R.string.battery_stock_summary)
                },
                style = MaterialTheme.typography.caption2,
                color = DuskPalette.haze,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(vertical = 6.dp),
            )
        }
        // The Galaxy Wearable manual step is the primary (and on Samsung,
        // the only working) path — show it prominently first.
        item {
            Text(
                if (samsung) {
                    stringResource(R.string.battery_samsung_steps)
                } else {
                    stringResource(R.string.battery_stock_steps)
                },
                style = MaterialTheme.typography.caption2,
                color = DuskPalette.parchment,
                textAlign = TextAlign.Start,
                modifier = Modifier.padding(horizontal = 4.dp, vertical = 4.dp),
            )
        }
        // Stock Wear OS exposes an on-watch settings path + a working
        // auto-open shortcut. On Samsung both are no-ops, so we suppress
        // them rather than offer a button that silently does nothing.
        if (!samsung) {
            item {
                Text(
                    stringResource(R.string.battery_on_watch_steps),
                    style = MaterialTheme.typography.caption3,
                    color = DuskPalette.haze,
                    textAlign = TextAlign.Start,
                    modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
                )
            }
            item {
                Chip(
                    onClick = onTryAutoOpen,
                    label = {
                        Text(
                            stringResource(R.string.battery_try_auto_open),
                            style = MaterialTheme.typography.caption2,
                        )
                    },
                    colors = ChipDefaults.secondaryChipColors(),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
        item {
            Chip(
                onClick = onClose,
                label = { Text(stringResource(R.string.done)) },
                colors = ChipDefaults.primaryChipColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun PreRunScreen(
    queuedCount: Int,
    syncing: Boolean,
    authed: Boolean,
    authError: String?,
    online: Boolean,
    batteryOptimised: Boolean,
    batteryPercent: Int?,
    activeRace: com.runapp.watchwear.ActiveRaceState?,
    pendingRecoveryDistance: Double?,
    activityType: String,
    selectedRouteName: String?,
    selectedRouteWaypoints: List<com.runapp.watchwear.recording.RouteMath.LatLng>,
    targetPaceSecPerKm: Int?,
    onCycleActivity: () -> Unit,
    onCyclePace: () -> Unit,
    onOpenRoutePicker: () -> Unit,
    onStart: () -> Unit,
    onSignIn: () -> Unit,
    onSignOut: () -> Unit,
    onFixBattery: () -> Unit,
    onRecover: () -> Unit,
    onDiscardRecovery: () -> Unit,
    onSync: () -> Unit,
) {
    // Recovery prompt takes precedence — user has unsaved-run state from
    // a previous app kill. Show that exclusively until they decide.
    if (pendingRecoveryDistance != null) {
        Box(modifier = Modifier.fillMaxSize().padding(20.dp), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(stringResource(R.string.recover_unsaved_run), style = MaterialTheme.typography.title3, textAlign = TextAlign.Center)
                Spacer(Modifier.height(4.dp))
                Text(
                    stringResource(R.string.distance_km_recorded, formatKm(pendingRecoveryDistance)),
                    style = MaterialTheme.typography.caption2,
                    color = DuskPalette.haze,
                )
                Spacer(Modifier.height(8.dp))
                Chip(
                    onClick = onRecover,
                    label = { Text(stringResource(R.string.save_it)) },
                    colors = ChipDefaults.primaryChipColors(),
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(4.dp))
                Chip(
                    onClick = onDiscardRecovery,
                    label = { Text(stringResource(R.string.discard)) },
                    colors = ChipDefaults.secondaryChipColors(),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
        return
    }

    // Pre-run layout matches the running screen's edge-anchored
    // pattern: route preview fills the watch face as a background,
    // status banners hug the top arc, Start lives at dead centre,
    // and the settings chip rail + auxiliary chips cluster at the
    // bottom edge. Aligned via Box.align() so each region is
    // independently positioned — content overflow in one region
    // can't push another out of frame, which was the bug that
    // shoved Start into the system TimeText when a route was
    // selected.
    val captionShadow = Shadow(Color.Black.copy(alpha = 0.6f), Offset(0f, 0.5f), 3f)
    Box(modifier = Modifier.fillMaxSize()) {
        // Background: full-screen route preview when one's picked
        // (same canvas as the in-run map, with `current = null` so
        // it fits-bounds and frames the whole polyline). Without a
        // route, the watch background shows through unchanged.
        if (authed && selectedRouteWaypoints.isNotEmpty()) {
            val routePreviewCd = stringResource(R.string.cd_route_preview_change)
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clickable(onClick = onOpenRoutePicker)
                    .semantics {
                        contentDescription = routePreviewCd
                        role = Role.Button
                    }
            ) {
                RouteMiniMap(
                    route = selectedRouteWaypoints,
                    current = null,
                    modifier = Modifier.fillMaxSize(),
                    clipShape = androidx.compose.ui.graphics.RectangleShape,
                )
            }
        }

        // Top arc: thin status captions. Padding clears the system
        // `TimeText` (rendered by the parent Scaffold) — without
        // this padding the queued-count line lands in the same
        // pixels as the clock and goes unreadable. The battery `!`
        // and sign-out icon buttons live further down on the chord
        // curve (top=50.dp), so the centred pills here don't have
        // to dodge them at the narrow upper chord.
        Column(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 30.dp, start = 16.dp, end = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (queuedCount > 0) {
                // Tappable so the runner can force a retry — the queue
                // also drains automatically on every connectivity edge
                // and on app cold-start, but if the user just got home
                // and wants their run synced *now* (e.g., to check it
                // on the phone), waiting for a network event is the
                // wrong feel. While the drain is in flight we replace
                // the label with a small spinner; offline / unauthed
                // keep the chip disabled because retrying is guaranteed
                // to fail until the network or session comes back —
                // CompactChip dims it visually so the user can tell.
                //
                // Visual styling matches the Activity / Route / Pace
                // chips at the bottom arc: same `translucentChip`
                // colours (white-alpha-0.15 + parchment) and `caption3`
                // typography so the four chips read as one family.
                CompactChip(
                    onClick = onSync,
                    enabled = online && authed && !syncing,
                    label = {
                        if (syncing) {
                            CircularProgressIndicator(
                                strokeWidth = 1.5.dp,
                                modifier = Modifier.size(12.dp),
                                indicatorColor = DuskPalette.parchment,
                            )
                        } else {
                            Text(
                                stringResource(R.string.sync_count, queuedCount),
                                style = MaterialTheme.typography.caption3,
                                maxLines = 1,
                                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                            )
                        }
                    },
                    colors = ChipDefaults.secondaryChipColors(
                        backgroundColor = Color.White.copy(alpha = 0.15f),
                        contentColor = DuskPalette.parchment,
                    ),
                    modifier = Modifier.widthIn(max = 100.dp),
                )
            } else if (!online && authed) {
                Text(
                    stringResource(R.string.offline),
                    style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                    color = DuskPalette.warning,
                )
            }
            if (!authed) {
                Text(
                    stringResource(R.string.offline),
                    style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                    color = DuskPalette.warning,
                )
                if (authError != null) {
                    Text(
                        authError,
                        style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                        color = DuskPalette.error,
                        textAlign = TextAlign.Center,
                    )
                }
            }
            if (batteryPercent != null &&
                batteryPercent < com.runapp.watchwear.system.BatteryStatus.LOW_THRESHOLD_PERCENT) {
                Text(
                    stringResource(R.string.battery_consider_charging, batteryPercent),
                    style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                    color = DuskPalette.warning,
                    textAlign = TextAlign.Center,
                )
            }
            if (activeRace != null) {
                Text(
                    if (activeRace.isArmed) stringResource(R.string.race_armed) else stringResource(R.string.race_live),
                    style = MaterialTheme.typography.caption2.copy(shadow = captionShadow),
                    color = MaterialTheme.colors.primary,
                )
                val title = activeRace.eventTitle ?: stringResource(R.string.event)
                Text(
                    if (activeRace.isArmed) stringResource(R.string.race_wait_for_go, title)
                    else stringResource(R.string.race_tap_start, title),
                    style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                    color = DuskPalette.parchment,
                    textAlign = TextAlign.Center,
                )
            }
            // Route name pill at the top arc — only when a route is
            // picked. Replaces the centre Route chip in the bottom
            // cluster so Start can take the centre-bottom slot. Tap
            // re-opens the picker, same as the bottom chip would.
            if (authed && selectedRouteWaypoints.isNotEmpty() && selectedRouteName != null) {
                Spacer(Modifier.height(2.dp))
                val routeSelectedCd = stringResource(R.string.cd_route_selected, selectedRouteName)
                CompactChip(
                    onClick = onOpenRoutePicker,
                    label = {
                        Text(
                            selectedRouteName,
                            style = MaterialTheme.typography.caption3,
                            maxLines = 1,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                        )
                    },
                    colors = ChipDefaults.secondaryChipColors(
                        backgroundColor = Color.White.copy(alpha = 0.15f),
                        contentColor = DuskPalette.parchment,
                    ),
                    // 90 dp leaves clear horizontal space on each
                    // side for the TopStart/TopEnd corner icons that
                    // share this vertical band — wider pills (e.g.
                    // 130 dp) bump into the sign-out icon on names
                    // like "Battersea Park Out & Back".
                    modifier = Modifier
                        .widthIn(max = 90.dp)
                        .semantics {
                            contentDescription = routeSelectedCd
                        },
                )
            }
        }

        // Primary action. Two distinct shapes depending on context:
        //   * No route ⇒ BIG circular Button dead centre, anchoring
        //     the otherwise-empty midnight screen.
        //   * Route picked ⇒ small CompactChip at the bottom-centre
        //     of the curved cluster, alongside Activity / Pace.
        //     Same chip size as its neighbours so the four-button
        //     arc reads as a uniform row, and the route preview
        //     above the cluster stays unobstructed. Route name is
        //     surfaced as a tappable pill in the top status area.
        val routeSelected = authed && selectedRouteWaypoints.isNotEmpty()
        if (!routeSelected) {
            Button(
                onClick = onStart,
                modifier = Modifier
                    .align(Alignment.Center)
                    .size(ButtonDefaults.LargeButtonSize),
            ) {
                Text(
                    stringResource(R.string.start),
                    style = MaterialTheme.typography.title3,
                )
            }
        } else {
            CompactChip(
                onClick = onStart,
                label = {
                    Text(
                        stringResource(R.string.start),
                        style = MaterialTheme.typography.caption2,
                    )
                },
                colors = ChipDefaults.primaryChipColors(),
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 14.dp)
                    .widthIn(max = 100.dp),
            )
        }

        // Bottom arc: three settings chips positioned independently
        // so they hug the inscribed circle's curve, matching the
        // running screen's Pause / Lap / Stop pattern. Centre chip
        // (Route, or Sign-in when unauthed) sits at the lowest
        // point; Activity and Pace sit on the sides higher up
        // (~36 dp from the bottom edge) where the chord is wide
        // enough that their rounded corners aren't clipped by the
        // bezel — at the very bottom, the chord narrows to ~140 dp
        // and a 60-dp chip with 8 dp side padding falls outside it.
        // Backdrop is white-alpha-0.15 instead of black-alpha-0.55
        // so the chips remain visible against the midnight
        // background (no-route case) AND against street tiles
        // (route-selected case) — frosted-glass on either.
        val translucentChip = ChipDefaults.secondaryChipColors(
            backgroundColor = Color.White.copy(alpha = 0.15f),
            contentColor = DuskPalette.parchment,
        )
        val activityLabel = activityLabel(activityType)
        val activityCd = stringResource(R.string.cd_activity_type, activityLabel)
        CompactChip(
            onClick = onCycleActivity,
            label = {
                Text(
                    activityLabel,
                    style = MaterialTheme.typography.caption3,
                    maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                )
            },
            colors = translucentChip,
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(start = 22.dp, bottom = 36.dp)
                .widthIn(max = 56.dp)
                // The label is a single abbreviated word ("Run"); without
                // this a TalkBack user can't tell it's a cycle control or
                // what it does. Spell out the action + current value.
                .semantics {
                    contentDescription = activityCd
                },
        )
        if (authed && !routeSelected) {
            // Bottom-centre Route picker chip — only when no route
            // is picked yet. When a route IS picked, Start takes
            // this slot in the curve and the route name pill
            // appears at the top arc.
            val chooseRouteCd = stringResource(R.string.cd_choose_route)
            CompactChip(
                onClick = onOpenRoutePicker,
                label = {
                    Text(
                        stringResource(R.string.route),
                        style = MaterialTheme.typography.caption3,
                        maxLines = 1,
                        overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                    )
                },
                colors = translucentChip,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 14.dp)
                    .widthIn(max = 100.dp)
                    .semantics {
                        contentDescription = chooseRouteCd
                    },
            )
        } else if (!authed) {
            // Replaces the Route chip with Sign-in when unauthed.
            // Same position so the curve looks identical regardless
            // of auth state.
            val signInCd = stringResource(R.string.cd_sign_in)
            CompactChip(
                onClick = onSignIn,
                label = {
                    Text(
                        stringResource(R.string.sign_in),
                        style = MaterialTheme.typography.caption3,
                        maxLines = 1,
                    )
                },
                colors = translucentChip,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 14.dp)
                    .semantics {
                        contentDescription = signInCd
                    },
            )
        }
        val paceCd = if (targetPaceSecPerKm == null) {
            stringResource(R.string.cd_target_pace_off)
        } else {
            stringResource(R.string.cd_target_pace, formatPace(targetPaceSecPerKm.toDouble()))
        }
        val paceOffLabel = stringResource(R.string.pace)
        CompactChip(
            onClick = onCyclePace,
            label = {
                Text(
                    if (targetPaceSecPerKm == null) paceOffLabel
                    else formatPace(targetPaceSecPerKm.toDouble()),
                    style = MaterialTheme.typography.caption3,
                    maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                )
            },
            colors = translucentChip,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 22.dp, bottom = 36.dp)
                .widthIn(max = 56.dp)
                .semantics {
                    contentDescription = paceCd
                },
        )

        // Top side icon buttons, mirroring the bottom Activity / Pace
        // chip arrangement: sign-out on the right, "fix battery
        // optimisation" warning on the left. Padding (top=36.dp,
        // start/end=22.dp) matches the bottom row's 36 dp distance
        // from the bezel — the previous 50.dp left a visible gap
        // above the icons that the bottom row didn't have, so the
        // face read as bottom-heavy. The centred route-name pill is
        // capped at 90 dp width so it never collides horizontally
        // with the corner icons even though they share a vertical
        // band. Translucent backgrounds so the icons don't blot
        // out the route map underneath.
        val cornerIconColors = ButtonDefaults.secondaryButtonColors(
            backgroundColor = Color.Black.copy(alpha = 0.55f),
            contentColor = DuskPalette.parchment,
        )
        if (batteryOptimised) {
            CompactButton(
                onClick = onFixBattery,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(top = 36.dp, start = 22.dp),
                colors = ButtonDefaults.secondaryButtonColors(
                    backgroundColor = Color.Black.copy(alpha = 0.55f),
                    contentColor = DuskPalette.warning,
                ),
            ) {
                Text(
                    "!",
                    style = MaterialTheme.typography.caption1,
                    color = DuskPalette.warning,
                )
            }
        }
        if (authed) {
            CompactButton(
                onClick = onSignOut,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 36.dp, end = 22.dp),
                colors = cornerIconColors,
            ) {
                Icon(
                    imageVector = Icons.Filled.ExitToApp,
                    contentDescription = stringResource(R.string.sign_out),
                    modifier = Modifier.size(14.dp),
                )
            }
        }
    }
}

/// Direct email/password sign-in for users without a paired Android phone.
///
/// Uses `BasicTextField` with explicit focus + `SoftwareKeyboardController`
/// so tapping a field raises the system keyboard in one tap (instead of
/// the three-choice picker the `RemoteInput` path forces). Requires a
/// keyboard IME installed on the watch; all Wear OS 3+ emulators and
/// retail watches have one.
@Composable
private fun SignInScreen(
    authError: String?,
    loading: Boolean,
    onSubmit: (email: String, password: String) -> Unit,
    onCancel: () -> Unit,
) {
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }

    val listState = rememberScalingLazyListState()
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        state = listState,
        horizontalAlignment = Alignment.CenterHorizontally,
        contentPadding = PaddingValues(
            top = 32.dp,
            bottom = 32.dp,
            start = 12.dp,
            end = 12.dp,
        ),
    ) {
        item {
            Text(
                stringResource(R.string.sign_in),
                style = MaterialTheme.typography.title3,
            )
        }
        item {
            InlineTextField(
                value = email,
                // Lowercase on input + explicit `KeyboardCapitalization.None`
                // on the IME options: some Wear keyboards auto-shift after
                // `@` ("new word" heuristic), which turns `test.com` into
                // `TEST>COM` (shift-`.` = `>`). Belt-and-suspenders so the
                // stored email is canonicalised regardless.
                onValueChange = { email = it.trim().lowercase() },
                label = stringResource(R.string.email),
                keyboardType = KeyboardType.Email,
                // Done (not Next): Wear GBoard's right-arrow "Next" doesn't
                // reliably commit the composing text before moving focus,
                // which blanks the email on transition. Done (checkmark)
                // always commits. User taps Password field manually after.
                imeAction = ImeAction.Done,
                capitalization = KeyboardCapitalization.None,
            )
        }
        item {
            InlineTextField(
                value = password,
                onValueChange = { password = it },
                label = stringResource(R.string.password),
                keyboardType = KeyboardType.Password,
                imeAction = ImeAction.Done,
                isPassword = true,
                onImeDone = {
                    // Gate the keyboard's Done action the same way the
                    // Submit chip is gated. Otherwise Enter with an empty
                    // email fires the request anyway and Supabase returns
                    // `validation_failed: missing email or phone`.
                    if (email.isNotEmpty() && password.isNotEmpty()) {
                        onSubmit(email, password)
                    }
                },
            )
        }

        if (authError != null) {
            item {
                Text(
                    authError,
                    style = MaterialTheme.typography.caption3,
                    color = DuskPalette.error,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 8.dp),
                )
            }
        }

        item {
            Chip(
                onClick = { onSubmit(email, password) },
                enabled = !loading && email.isNotEmpty() && password.isNotEmpty(),
                label = {
                    if (loading) {
                        CircularProgressIndicator(
                            strokeWidth = 2.dp,
                            modifier = Modifier.height(16.dp),
                        )
                    } else {
                        Text(stringResource(R.string.submit))
                    }
                },
                colors = ChipDefaults.primaryChipColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            Chip(
                onClick = onCancel,
                enabled = !loading,
                label = { Text(stringResource(R.string.cancel)) },
                colors = ChipDefaults.secondaryChipColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun InlineTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    keyboardType: KeyboardType,
    imeAction: ImeAction,
    isPassword: Boolean = false,
    capitalization: KeyboardCapitalization = KeyboardCapitalization.Sentences,
    onImeDone: (() -> Unit)? = null,
) {
    val focusRequester = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current

    // Internal TextFieldValue so we control the cursor position. After the
    // user commits (Done), we reset selection to position 0 — otherwise the
    // cursor stays at the end of a long string and `BasicTextField`
    // scrolls the viewport to the cursor, hiding the leading characters
    // (the bug where "runner@test.com" visually rendered as "test.com").
    var fieldState by remember(value.length == 0) {
        mutableStateOf(TextFieldValue(value, TextRange(value.length)))
    }
    // Keep internal state in sync when the parent rewrites the string
    // (e.g. the `.trim().lowercase()` transform on email).
    LaunchedEffect(value) {
        if (fieldState.text != value) {
            fieldState = fieldState.copy(text = value)
        }
    }

    val handleAction: () -> Unit = {
        fieldState = fieldState.copy(selection = TextRange.Zero)
        keyboard?.hide()
        focusManager.clearFocus()
        onImeDone?.invoke()
    }
    val handleValueChange: (TextFieldValue) -> Unit = { new ->
        val text = new.text
        if (text.any { it == '\n' || it == '\r' }) {
            val stripped = text.replace("\n", "").replace("\r", "")
            fieldState = new.copy(text = stripped)
            onValueChange(stripped)
            handleAction()
        } else {
            fieldState = new
            onValueChange(text)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(DuskPalette.dusk)
            .clickable {
                focusRequester.requestFocus()
                keyboard?.show()
            }
            .padding(horizontal = 10.dp, vertical = 6.dp),
    ) {
        Column {
            Text(
                label,
                style = MaterialTheme.typography.caption3,
                color = DuskPalette.haze,
            )
            Box {
                if (value.isEmpty()) {
                    Text(
                        stringResource(R.string.tap_here),
                        style = MaterialTheme.typography.body2,
                        color = DuskPalette.haze,
                    )
                }
                BasicTextField(
                    value = fieldState,
                    onValueChange = handleValueChange,
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(
                        keyboardType = keyboardType,
                        imeAction = imeAction,
                        capitalization = capitalization,
                        autoCorrectEnabled = false,
                    ),
                    keyboardActions = KeyboardActions(
                        onDone = { handleAction() },
                        onGo = { handleAction() },
                        onSend = { handleAction() },
                        onSearch = { handleAction() },
                        onNext = {
                            // Email → Password focus jump. Password
                            // won't have a "Next" handler because its
                            // imeAction is Done, but wire for safety.
                            if (onImeDone == null) {
                                focusManager.moveFocus(FocusDirection.Next)
                            } else {
                                handleAction()
                            }
                        },
                    ),
                    visualTransformation = if (isPassword) {
                        PasswordVisualTransformation()
                    } else {
                        VisualTransformation.None
                    },
                    textStyle = TextStyle(
                        color = DuskPalette.parchment,
                        fontSize = MaterialTheme.typography.body2.fontSize,
                    ),
                    cursorBrush = SolidColor(DuskPalette.parchment),
                    modifier = Modifier
                        .fillMaxWidth()
                        .focusRequester(focusRequester),
                )
            }
        }
    }
}


@Composable
private fun RunningScreen(
    elapsedMs: Long,
    distanceM: Double,
    paceSecPerKm: Double?,
    preferredUnit: com.runapp.watchwear.recording.DistanceUnit,
    bpm: Int?,
    hrZoneCutoffs: List<Int>?,
    steps: Int?,
    lapCount: Int,
    paused: Boolean,
    locationAvailable: Boolean,
    noGpsYet: Boolean,
    offRouteDistanceM: Double?,
    routeRemainingM: Double?,
    routeWaypoints: List<com.runapp.watchwear.recording.RouteMath.LatLng>,
    latestPoint: com.runapp.watchwear.GpsPoint?,
    /// Last-known location captured during the start countdown.
    /// Used as a fallback when `latestPoint` is null — the live
    /// GPS stream takes 0.5–2 s to produce its first fix after the
    /// service starts, and without this fallback the screen would
    /// blank out the map between countdown end and first stream
    /// fix. Once `latestPoint` lands the real value takes over.
    fallbackLatLng: com.runapp.watchwear.recording.RouteMath.LatLng?,
    trackOverlayPoints: List<com.runapp.watchwear.recording.RouteMath.LatLng>,
    ambient: Boolean,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onLap: () -> Unit,
    onStop: () -> Unit,
) {
    val haptics = androidx.compose.ui.platform.LocalHapticFeedback.current

    // Off-route hysteresis: alert above 40 m, clear below 20 m. Single
    // haptic pulse when the state flips to "off" — drivers an alert
    // without the pulsing-every-tick spam a flat threshold would cause
    // at the boundary.
    var wasOffRoute by remember { mutableStateOf(false) }
    val currentlyOffRoute = offRouteDistanceM != null && offRouteDistanceM > 40
    val backOnRoute = offRouteDistanceM != null && offRouteDistanceM < 20
    LaunchedEffect(currentlyOffRoute, backOnRoute) {
        if (currentlyOffRoute && !wasOffRoute) {
            wasOffRoute = true
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            delay(180)
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        } else if (backOnRoute && wasOffRoute) {
            wasOffRoute = false
        }
    }
    // Ambient mode: OEM burn-in protection rules apply — pure-black
    // background, thin outlined text, no solid fills, and the content
    // shifts a few dp each minute (handled by the system if we use the
    // `TimeText` primitive). The recording continues in the service;
    // this branch is purely lower-power rendering.
    if (ambient) {
        Scaffold(timeText = { TimeText() }) {
            Column(
                modifier = Modifier.fillMaxSize().padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    formatElapsed(elapsedMs),
                    style = MaterialTheme.typography.display1.copy(
                        fontWeight = androidx.compose.ui.text.font.FontWeight.Light,
                    ),
                    color = Color.White,
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    distanceLabel(distanceM, preferredUnit),
                    style = MaterialTheme.typography.body1,
                    color = Color.White.copy(alpha = 0.72f),
                )
                if (paused) {
                    Spacer(Modifier.height(2.dp))
                    Text(
                        stringResource(R.string.paused_lower),
                        style = MaterialTheme.typography.caption2,
                        color = Color.White.copy(alpha = 0.4f),
                    )
                }
            }
        }
        return
    }

    // Map fills the whole watch face as a background. Metrics overlay
    // in the centre; pause / lap / stop buttons cluster against the
    // bottom edge of the round face. The button cluster auto-hides
    // 5 s after the last interaction so the runner gets an
    // unobstructed view of the route. Tap anywhere on the map to
    // bring the buttons back. While paused, controls stay visible
    // so the runner can resume without a hidden tap.
    // Effective position: prefer the live stream once it's flowing,
    // fall back to the countdown's last-known fix while the recorder
    // is still warming up. Bridges the 0.5–2 s gap where `latestPoint`
    // is null but we already know roughly where the runner is.
    val effectiveCurrent: com.runapp.watchwear.recording.RouteMath.LatLng? = latestPoint?.let {
        com.runapp.watchwear.recording.RouteMath.LatLng(it.lat, it.lng)
    } ?: fallbackLatLng
    val showMiniMap = routeWaypoints.isNotEmpty() ||
        trackOverlayPoints.size >= 2 ||
        effectiveCurrent != null

    var controlsVisible by remember { mutableStateOf(true) }
    // Bumped on every interaction (tap or button press) to restart the
    // auto-hide delay. Each new value re-keys the LaunchedEffect, which
    // cancels the old delay coroutine and starts a fresh 5 s countdown.
    var revealTick by remember { mutableIntStateOf(0) }
    LaunchedEffect(revealTick, paused) {
        if (paused) return@LaunchedEffect
        delay(5_000)
        controlsVisible = false
    }
    val reveal: () -> Unit = {
        controlsVisible = true
        revealTick++
    }

    // Glanceable text styles bake a subtle shadow into the time +
    // distance so they pop against street tiles. Without it, white
    // parchment on a busy `streets-v2-dark` tile (say, over a road
    // label) loses contrast at running pace.
    val timeStyle = MaterialTheme.typography.display2.copy(
        shadow = Shadow(Color.Black.copy(alpha = 0.7f), Offset(0f, 1f), 6f),
    )
    val captionShadow = Shadow(Color.Black.copy(alpha = 0.6f), Offset(0f, 0.5f), 3f)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                // Detect taps on the map background. Any composable
                // above (like the buttons in the AnimatedVisibility
                // block) consumes its own clicks before this fires.
                detectTapGestures { reveal() }
            },
    ) {
        if (showMiniMap) {
            RouteMiniMap(
                route = routeWaypoints,
                current = effectiveCurrent,
                track = trackOverlayPoints,
                modifier = Modifier.fillMaxSize(),
                clipShape = androidx.compose.ui.graphics.RectangleShape,
            )
        }

        // Top metrics: time + distance + (status banners). Anchored
        // to the top of the round face so the centre band stays
        // clear for the runner's position dot — runners need to see
        // *where they are* on the map without text overlapping the
        // dot. Status banners (GPS lost, off-route) sit above the
        // time so they never compete with primary metrics.
        Column(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 24.dp, start = 16.dp, end = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (!locationAvailable) {
                Text(
                    if (noGpsYet) stringResource(R.string.no_gps_time_only) else stringResource(R.string.gps_lost),
                    style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                    color = DuskPalette.warning,
                )
            }
            if (wasOffRoute && offRouteDistanceM != null) {
                Text(
                    stringResource(R.string.off_route_distance, offRouteDistanceM.toInt()),
                    style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                    color = DuskPalette.warning,
                )
            }
            Text(
                formatElapsed(elapsedMs),
                style = timeStyle,
                color = if (paused) DuskPalette.haze else DuskPalette.parchment,
            )
            Text(
                distanceLabel(distanceM, preferredUnit),
                style = MaterialTheme.typography.body2.copy(shadow = captionShadow),
            )
        }

        // Bottom secondary metrics. Anchored above where the curved
        // button cluster will sit so the two regions don't crowd
        // each other. Bottom padding ~62dp clears the
        // ~28dp-from-bottom outer buttons + spacing.
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 62.dp, start = 16.dp, end = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (paceSecPerKm != null && paceSecPerKm > 0 && !paused) {
                Text(
                    paceLabel(paceSecPerKm, preferredUnit),
                    style = MaterialTheme.typography.caption2.copy(shadow = captionShadow),
                    color = DuskPalette.parchment,
                )
            }
            if (routeRemainingM != null && routeRemainingM > 1.0) {
                Text(
                    distanceToGoLabel(routeRemainingM, preferredUnit),
                    style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                    color = DuskPalette.lilac,
                )
            }
            val secondary = listOfNotNull(
                // Zone badge sits adjacent to the BPM reading so the
                // runner can read both in a single glance. Falls back
                // to bare "146 bpm" when the cutoffs haven't been
                // resolved (no hr_zones / max_hr_bpm / DOB set, or the
                // session-restore prefs fetch hasn't returned yet).
                bpm?.let { b ->
                    val z = hrZoneOf(b, hrZoneCutoffs)
                    if (z != null) stringResource(R.string.bpm_zone, b, z) else stringResource(R.string.bpm, b)
                },
                steps?.takeIf { it > 0 }?.let { pluralStringResource(R.plurals.steps, it, it) },
                lapCount.takeIf { it > 0 }?.let { stringResource(R.string.lap_number, it) },
            )
            if (secondary.isNotEmpty()) {
                Text(
                    secondary.joinToString(" · "),
                    style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                    color = DuskPalette.haze,
                )
            }
        }

        // Curved button cluster around the bottom arc. Three buttons
        // positioned independently so they can hug the bezel — a
        // single horizontal Row at the very bottom edge gets clipped
        // at the corners on a round face. Lap sits at the lowest
        // point (BottomCenter, 12 dp inset); Pause and Stop sit on
        // the sides slightly higher (28 dp inset) so they follow
        // the inscribed circle inward.
        AnimatedVisibility(
            visible = controlsVisible,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.fillMaxSize(),
        ) {
            val translucent = ButtonDefaults.secondaryButtonColors(
                backgroundColor = Color.Black.copy(alpha = 0.55f),
                contentColor = DuskPalette.parchment,
            )
            // audit/accessibility (May 2026) High — every running-screen
            // Button below now declares a Modifier.semantics {
            // contentDescription = ... ; role = Role.Button } so TalkBack
            // announces a useful label instead of the visual content
            // ("||", "Go", "Lap"). Mirrors the recording-screen Semantics
            // fix on the mobile twin (commit 6b2ef21).
            val resumeCd = stringResource(R.string.cd_resume_run)
            val pauseCd = stringResource(R.string.cd_pause_run)
            val lapCd = stringResource(R.string.cd_mark_lap)
            val resumeLabel = stringResource(R.string.resume_short)
            val lapLabel = stringResource(R.string.lap)
            Box(modifier = Modifier.fillMaxSize()) {
                if (paused) {
                    Button(
                        onClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            reveal()
                            onResume()
                        },
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .padding(start = 28.dp, bottom = 32.dp)
                            .size(ButtonDefaults.SmallButtonSize)
                            .semantics {
                                contentDescription = resumeCd
                                role = Role.Button
                            },
                    ) {
                        Text(resumeLabel, style = MaterialTheme.typography.caption3)
                    }
                } else {
                    Button(
                        onClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            reveal()
                            onPause()
                        },
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .padding(start = 28.dp, bottom = 32.dp)
                            .size(ButtonDefaults.SmallButtonSize)
                            .semantics {
                                contentDescription = pauseCd
                                role = Role.Button
                            },
                        colors = translucent,
                    ) {
                        Text("||")
                    }
                }
                Button(
                    onClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        reveal()
                        onLap()
                    },
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(bottom = 12.dp)
                        .size(ButtonDefaults.SmallButtonSize)
                        .semantics {
                            contentDescription = lapCd
                            role = Role.Button
                        },
                    colors = translucent,
                ) {
                    Text(lapLabel, style = MaterialTheme.typography.caption3)
                }
                HoldToStopButton(
                    onStop = onStop,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(end = 28.dp, bottom = 32.dp),
                )
            }
        }
    }
}

/// Pre-run route picker. Compact list of the user's saved routes; tap
/// to select, "None" to clear the current selection, "Cancel" to back
/// out without changing it. Refreshing the list happens in the
/// ViewModel (`refreshRoutes`) when the stage flips to RoutePicker —
/// the UI here only renders what's in `state.routes`.
@Composable
private fun RoutePickerScreen(
    routes: List<com.runapp.watchwear.SavedRoute>,
    selectedId: String?,
    loading: Boolean,
    preferredUnit: com.runapp.watchwear.recording.DistanceUnit,
    onPick: (com.runapp.watchwear.SavedRoute) -> Unit,
    onClear: () -> Unit,
    onCancel: () -> Unit,
) {
    val listState = rememberScalingLazyListState()
    // Rotary bezel / crown scroll for the route list. Persona samsung #32.
    val rotaryFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) { rotaryFocus.requestFocus() }
    ScalingLazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .rotaryScrollable(
                RotaryScrollableDefaults.behavior(scrollableState = listState),
                focusRequester = rotaryFocus,
            ),
        state = listState,
        horizontalAlignment = Alignment.CenterHorizontally,
        autoCentering = AutoCenteringParams(itemIndex = 0),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 24.dp),
    ) {
        item {
            Text(
                stringResource(R.string.route),
                style = MaterialTheme.typography.title3,
            )
        }
        if (loading && routes.isEmpty()) {
            item {
                CircularProgressIndicator(
                    strokeWidth = 2.dp,
                    modifier = Modifier.height(16.dp),
                )
            }
        }
        item {
            Chip(
                onClick = onClear,
                label = {
                    Text(
                        stringResource(R.string.route_none),
                        style = MaterialTheme.typography.caption2,
                    )
                },
                colors = if (selectedId == null)
                    ChipDefaults.primaryChipColors()
                else ChipDefaults.secondaryChipColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        items(routes.size) { i ->
            val r = routes[i]
            val isSelected = r.id == selectedId
            Chip(
                onClick = { onPick(r) },
                label = {
                    Column {
                        Text(
                            r.name,
                            style = MaterialTheme.typography.caption2,
                            maxLines = 1,
                        )
                        Text(
                            distanceLabel(r.distanceM, preferredUnit),
                            style = MaterialTheme.typography.caption3,
                            color = DuskPalette.haze,
                        )
                    }
                },
                colors = if (isSelected)
                    ChipDefaults.primaryChipColors()
                else ChipDefaults.secondaryChipColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (routes.isEmpty() && !loading) {
            item {
                Text(
                    stringResource(R.string.route_picker_empty),
                    style = MaterialTheme.typography.caption3,
                    color = DuskPalette.haze,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 8.dp),
                )
            }
        }
        item {
            Chip(
                onClick = onCancel,
                label = { Text(stringResource(R.string.cancel)) },
                colors = ChipDefaults.secondaryChipColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

/// Stop button that requires an ~800 ms press before firing `onStop`.
/// A circular progress ring fills around the button during the hold;
/// releasing early cancels. Prevents a single accidental tap from ending
/// a long run — the single most damaging mis-tap a runner can make.
@Composable
private fun HoldToStopButton(
    onStop: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    var progress by remember { mutableFloatStateOf(0f) }
    var holdJob by remember { mutableStateOf<Job?>(null) }
    val holdDurationMs = 800L

    Box(
        modifier = modifier
            .size(ButtonDefaults.SmallButtonSize)
            .pointerInput(Unit) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    holdJob?.cancel()
                    holdJob = scope.launch {
                        val startMs = System.currentTimeMillis()
                        while (isActive) {
                            val elapsed = System.currentTimeMillis() - startMs
                            progress = (elapsed.toFloat() / holdDurationMs)
                                .coerceAtMost(1f)
                            if (elapsed >= holdDurationMs) {
                                onStop()
                                progress = 0f
                                break
                            }
                            delay(16)
                        }
                    }
                    waitForUpOrCancellation()
                    holdJob?.cancel()
                    holdJob = null
                    progress = 0f
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        // Ring fills from 0 → 1 during the hold. Only drawn while held so
        // it doesn't compete visually with the Pause / Lap buttons when
        // the runner is just looking at their stats.
        if (progress > 0f) {
            CircularProgressIndicator(
                progress = progress,
                modifier = Modifier.size(ButtonDefaults.SmallButtonSize),
                strokeWidth = 3.dp,
                indicatorColor = MaterialTheme.colors.onPrimary,
                trackColor = Color.Transparent,
            )
        }
        Box(
            modifier = Modifier
                .size(ButtonDefaults.SmallButtonSize - 6.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colors.primary),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                stringResource(R.string.stop),
                style = MaterialTheme.typography.caption2,
                color = MaterialTheme.colors.onPrimary,
            )
        }
    }
}

@Composable
private fun PostRunScreen(
    summary: com.runapp.watchwear.FinishedSummary?,
    bodyWeightKg: Double?,
    preferredUnit: com.runapp.watchwear.recording.DistanceUnit,
    synced: Boolean,
    syncing: Boolean,
    syncError: String?,
    onSync: () -> Unit,
    onStartNext: () -> Unit,
    onDiscard: () -> Unit,
) {
    // Same edge-anchored Box pattern as PreRun + Running. The recorded
    // track fills the watch face as a background; headline stats hug
    // the top arc; small curved buttons live at the bottom arc; the
    // destructive Discard sits in the top-end corner. Splits aren't
    // rendered on-watch — the phone / web run-detail view shows them
    // in a much more readable layout, and dropping them here keeps
    // the route preview unobstructed (which the runner just asked
    // for). One run-only summary plus the route shape.
    val captionShadow = Shadow(Color.Black.copy(alpha = 0.6f), Offset(0f, 0.5f), 3f)
    val titleShadow = Shadow(Color.Black.copy(alpha = 0.7f), Offset(0f, 1f), 6f)

    Box(modifier = Modifier.fillMaxSize()) {
        // Background: the actual recorded track. Hidden for indoor
        // runs (no GPS fixes) — the screen falls back to the midnight
        // background, which still reads cleanly with stats on top.
        if (summary != null && summary.trackLatLngs.size >= 2) {
            RouteMiniMap(
                route = emptyList(),
                current = null,
                track = summary.trackLatLngs,
                modifier = Modifier.fillMaxSize(),
                clipShape = androidx.compose.ui.graphics.RectangleShape,
            )
        }

        // Top stats: distance + duration + (avg bpm). Same vertical
        // anchor as the running screen's time + distance so the
        // pre→run→post visual rhythm is consistent.
        if (summary != null) {
            Column(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 28.dp, start = 16.dp, end = 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    distanceLabel(summary.distanceM, preferredUnit),
                    style = MaterialTheme.typography.title2.copy(shadow = titleShadow),
                    color = DuskPalette.parchment,
                )
                Text(
                    formatDuration(summary.durationS),
                    style = MaterialTheme.typography.caption2.copy(shadow = captionShadow),
                    color = DuskPalette.haze,
                )
                if (summary.avgBpm != null) {
                    Text(
                        stringResource(R.string.bpm_avg, summary.avgBpm.toInt()),
                        style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                        color = DuskPalette.coral,
                    )
                }
                // Calorie estimate (persona samsung #34). Same 1 kcal/kg/km
                // ladder the phone/web run-detail uses, so the figure here
                // matches what the synced run shows there (modulo the
                // gender calibration the watch can't read — see RunCalories).
                run {
                    val kcal = com.runapp.watchwear.recording.RunCalories.estimate(
                        summary.distanceM, bodyWeightKg, summary.activityType,
                    )
                    if (kcal > 0) {
                        Text(
                            stringResource(R.string.kcal, kcal),
                            style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                            color = DuskPalette.haze,
                        )
                    }
                }
                if (synced) {
                    Text(
                        stringResource(R.string.synced),
                        style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                        color = DuskPalette.success,
                    )
                }
                if (syncError != null) {
                    Text(
                        syncError,
                        style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                        color = DuskPalette.error,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }

        // Frosted-glass button colour — matches PreRun chips and
        // running-screen Pause/Lap buttons so the pre→run→post
        // surface vocabulary is consistent.
        val translucent = ButtonDefaults.secondaryButtonColors(
            backgroundColor = Color.White.copy(alpha = 0.15f),
            contentColor = DuskPalette.parchment,
        )

        // Bottom-centre: primary action. Sync until the run lands;
        // Done after. Sized to SmallButtonSize like the running
        // screen's Lap / Stop buttons — the previous full-width chip
        // dwarfed the route preview.
        // audit/accessibility (May 2026) High — same Modifier.semantics
        // pattern as the running-screen buttons above. "Sync" / "Done"
        // / "Next" / "×" announce as their visual content otherwise;
        // the contentDescription names each action explicitly.
        val primaryCd = when {
            syncing -> stringResource(R.string.cd_syncing_run)
            synced -> stringResource(R.string.cd_start_next_run)
            else -> stringResource(R.string.cd_sync_run)
        }
        Button(
            onClick = if (synced) onStartNext else onSync,
            enabled = !syncing,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 14.dp)
                .size(ButtonDefaults.SmallButtonSize)
                .semantics {
                    contentDescription = primaryCd
                    role = Role.Button
                },
        ) {
            when {
                syncing -> CircularProgressIndicator(
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(16.dp),
                )
                synced -> Text(
                    stringResource(R.string.done),
                    style = MaterialTheme.typography.caption3,
                )
                else -> Text(
                    stringResource(R.string.sync),
                    style = MaterialTheme.typography.caption3,
                )
            }
        }

        // Bottom-start: "Start next run" — only meaningful while the
        // current run is not yet synced (post-sync the centre button
        // already routes to Next). Sits at the curve like Pause on
        // the running screen.
        if (!synced && summary != null) {
            val nextCd = stringResource(R.string.cd_start_next_run)
            Button(
                onClick = onStartNext,
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(start = 22.dp, bottom = 36.dp)
                    .size(ButtonDefaults.SmallButtonSize)
                    .semantics {
                        contentDescription = nextCd
                        role = Role.Button
                    },
                colors = translucent,
            ) {
                Text(stringResource(R.string.next), style = MaterialTheme.typography.caption3)
            }
        }

        // Bottom-end: discard. Mirror of Stop on the running screen
        // — destructive action positioned where the runner's hand
        // already expects it. Single tap (no hold) is fine here:
        // the run isn't running, just unsaved, and a Discard tap
        // can be re-triggered if dismissed by mistake.
        if (!synced && summary != null) {
            val discardCd = stringResource(R.string.cd_discard_unsaved_run)
            Button(
                onClick = onDiscard,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(end = 22.dp, bottom = 36.dp)
                    .size(ButtonDefaults.SmallButtonSize)
                    .semantics {
                        contentDescription = discardCd
                        role = Role.Button
                    },
                colors = translucent,
            ) {
                Text(
                    stringResource(R.string.discard_short),
                    style = MaterialTheme.typography.body2,
                )
            }
        }
    }
}

private fun formatDuration(totalS: Int): String {
    val h = totalS / 3600
    val m = (totalS % 3600) / 60
    val s = totalS % 60
    return if (h > 0) String.format(java.util.Locale.ROOT, "%d:%02d:%02d", h, m, s)
    else String.format(java.util.Locale.ROOT, "%d:%02d", m, s)
}

private fun formatElapsed(ms: Long): String {
    val total = ms / 1000
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) String.format(java.util.Locale.ROOT, "%d:%02d:%02d", h, m, s)
    else String.format(java.util.Locale.ROOT, "%02d:%02d", m, s)
}

private fun formatPace(secPerKm: Double): String {
    val m = (secPerKm / 60).toInt()
    val s = (secPerKm % 60).toInt()
    return String.format(java.util.Locale.ROOT, "%d:%02d", m, s)
}

/// Localized distance readout in the runner's [unit] (e.g. "5.12 km" /
/// "3.18 mi"). The number is formatted locale-aware; the unit word comes
/// from the unit-keyed string resource.
@Composable
private fun distanceLabel(
    distanceM: Double,
    unit: com.runapp.watchwear.recording.DistanceUnit,
): String {
    val num = com.runapp.watchwear.recording.formatDistance(distanceM, unit)
    val res = when (unit) {
        com.runapp.watchwear.recording.DistanceUnit.KM -> R.string.distance_km
        com.runapp.watchwear.recording.DistanceUnit.MI -> R.string.distance_mi
    }
    return stringResource(res, num)
}

/// Localized "X.XX km/mi to go" route-remaining badge in the runner's [unit].
@Composable
private fun distanceToGoLabel(
    distanceM: Double,
    unit: com.runapp.watchwear.recording.DistanceUnit,
): String {
    val num = com.runapp.watchwear.recording.formatDistance(distanceM, unit)
    val res = when (unit) {
        com.runapp.watchwear.recording.DistanceUnit.KM -> R.string.distance_km_to_go
        com.runapp.watchwear.recording.DistanceUnit.MI -> R.string.distance_mi_to_go
    }
    return stringResource(res, num)
}

/// Localized pace readout in the runner's [unit] ("5:30 /km" / "8:51 /mi").
/// [paceSecPerKm] is converted to seconds-per-mile when the unit is miles.
@Composable
private fun paceLabel(
    paceSecPerKm: Double,
    unit: com.runapp.watchwear.recording.DistanceUnit,
): String {
    val perUnit = com.runapp.watchwear.recording.paceSecPerUnit(paceSecPerKm, unit)
    val res = when (unit) {
        com.runapp.watchwear.recording.DistanceUnit.KM -> R.string.pace_per_km
        com.runapp.watchwear.recording.DistanceUnit.MI -> R.string.pace_per_mi
    }
    return stringResource(res, formatPace(perUnit))
}

/// Resolve a localized label for a cycled activity type. Unknown values
/// fall back to a capitalized form of the raw key so a future activity
/// added to the cycle list still renders something readable before its
/// string lands.
@Composable
private fun activityLabel(activityType: String): String = when (activityType) {
    "run" -> stringResource(R.string.activity_run)
    "walk" -> stringResource(R.string.activity_walk)
    "hike" -> stringResource(R.string.activity_hike)
    "cycle" -> stringResource(R.string.activity_cycle)
    else -> activityType.replaceFirstChar { it.uppercase() }
}

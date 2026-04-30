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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.foundation.lazy.AutoCenteringParams
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
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
import com.runapp.watchwear.RunViewModel
import com.runapp.watchwear.Stage
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
                            onTryAutoOpen = {
                                BatteryOptimization.requestExemption(activity)
                            },
                            onClose = { batteryHelp = false },
                        )
                    } else {
                        PreRunScreen(
                            queuedCount = state.queuedCount,
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
                    bpm = state.bpm,
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
                    trackOverlayPoints = state.trackOverlayPoints,
                    ambient = isAmbient,
                    onPause = vm::pause,
                    onResume = vm::resume,
                    onLap = vm::markLap,
                    onStop = vm::stop,
                )
                Stage.PostRun -> PostRunScreen(
                    summary = state.lastRunSummary,
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
                    onPick = vm::selectRoute,
                    onClear = vm::clearSelectedRoute,
                    onCancel = vm::closeRoutePicker,
                )
            }

            if (showCountdown) {
                CountdownOverlay(
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
/// ViewModel's `start()`. A tap anywhere cancels and returns to PreRun,
/// matching the Android pattern.
@Composable
private fun CountdownOverlay(
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
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.92f))
            .clickable(onClick = onCancel),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            count.toString(),
            style = MaterialTheme.typography.display1,
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
    onTryAutoOpen: () -> Unit,
    onClose: () -> Unit,
) {
    val listState = rememberScalingLazyListState()
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        state = listState,
        horizontalAlignment = Alignment.CenterHorizontally,
        autoCentering = AutoCenteringParams(itemIndex = 0),
        contentPadding = PaddingValues(horizontal = 14.dp),
    ) {
        item {
            Text(
                "Allow background activity",
                style = MaterialTheme.typography.title3,
                textAlign = TextAlign.Center,
            )
        }
        item {
            Text(
                "Needed so GPS keeps recording on long runs.",
                style = MaterialTheme.typography.caption2,
                color = DuskPalette.haze,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(vertical = 6.dp),
            )
        }
        item {
            Text(
                "On phone: open Wear OS / Galaxy Wearable → Run Onward → Battery → Unrestricted.",
                style = MaterialTheme.typography.caption2,
                color = DuskPalette.parchment,
                textAlign = TextAlign.Start,
                modifier = Modifier.padding(horizontal = 4.dp, vertical = 4.dp),
            )
        }
        item {
            Text(
                "Or on watch: Settings → Apps → Run Onward → Battery → Unrestricted (if shown).",
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
                        "Try auto-open",
                        style = MaterialTheme.typography.caption2,
                    )
                },
                colors = ChipDefaults.secondaryChipColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            Chip(
                onClick = onClose,
                label = { Text("Done") },
                colors = ChipDefaults.primaryChipColors(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun PreRunScreen(
    queuedCount: Int,
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
) {
    // Recovery prompt takes precedence — user has unsaved-run state from
    // a previous app kill. Show that exclusively until they decide.
    if (pendingRecoveryDistance != null) {
        Box(modifier = Modifier.fillMaxSize().padding(20.dp), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Recover unsaved run?", style = MaterialTheme.typography.title3, textAlign = TextAlign.Center)
                Spacer(Modifier.height(4.dp))
                Text(
                    "%.2f km recorded".format(pendingRecoveryDistance / 1000.0),
                    style = MaterialTheme.typography.caption2,
                    color = DuskPalette.haze,
                )
                Spacer(Modifier.height(8.dp))
                Chip(
                    onClick = onRecover,
                    label = { Text("Save it") },
                    colors = ChipDefaults.primaryChipColors(),
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(4.dp))
                Chip(
                    onClick = onDiscardRecovery,
                    label = { Text("Discard") },
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
            Box(modifier = Modifier.fillMaxSize().clickable(onClick = onOpenRoutePicker)) {
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
        // pixels as the clock and goes unreadable.
        Column(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 30.dp, start = 16.dp, end = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (queuedCount > 0) {
                val suffix = if (online) "" else " · offline"
                Text(
                    "$queuedCount run${if (queuedCount == 1) "" else "s"} to sync$suffix",
                    style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                    color = if (online) DuskPalette.haze else DuskPalette.warning,
                )
            } else if (!online && authed) {
                Text(
                    "Offline",
                    style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                    color = DuskPalette.warning,
                )
            }
            if (!authed) {
                Text(
                    "Offline",
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
                    "Battery $batteryPercent% · consider charging",
                    style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                    color = DuskPalette.warning,
                    textAlign = TextAlign.Center,
                )
            }
            if (activeRace != null) {
                Text(
                    if (activeRace.isArmed) "RACE ARMED" else "RACE LIVE",
                    style = MaterialTheme.typography.caption2.copy(shadow = captionShadow),
                    color = MaterialTheme.colors.primary,
                )
                val title = activeRace.eventTitle ?: "Event"
                Text(
                    if (activeRace.isArmed) "$title · wait for GO" else "$title · tap Start",
                    style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                    color = DuskPalette.parchment,
                    textAlign = TextAlign.Center,
                )
            }
        }

        // Centre: BIG primary action, dead centre. The bottom chips
        // are positioned independently along the inscribed curve
        // so there's no chip rail row competing for centre-band
        // pixels — Start can anchor the screen geometrically.
        Button(
            onClick = onStart,
            modifier = Modifier
                .align(Alignment.Center)
                .size(ButtonDefaults.LargeButtonSize),
        ) {
            Text(
                "Start",
                style = MaterialTheme.typography.title3,
            )
        }

        // Bottom arc: three settings chips positioned independently
        // so they hug the inscribed circle's curve, matching the
        // running screen's Pause / Lap / Stop pattern. Centre chip
        // (Route, or Sign-in when unauthed) sits at the lowest
        // point; Activity and Pace sit on the sides slightly higher
        // so their corners don't get clipped by the bezel. widthIn
        // caps each chip — long route names ellipsis-truncate but
        // can't push into the side chips.
        val translucentChip = ChipDefaults.secondaryChipColors(
            backgroundColor = Color.Black.copy(alpha = 0.55f),
            contentColor = DuskPalette.parchment,
        )
        CompactChip(
            onClick = onCycleActivity,
            label = {
                Text(
                    activityType.replaceFirstChar { it.uppercase() },
                    style = MaterialTheme.typography.caption3,
                    maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                )
            },
            colors = translucentChip,
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(start = 8.dp, bottom = 30.dp)
                .widthIn(max = 60.dp),
        )
        if (authed) {
            CompactChip(
                onClick = onOpenRoutePicker,
                label = {
                    Text(
                        selectedRouteName ?: "Route",
                        style = MaterialTheme.typography.caption3,
                        maxLines = 1,
                        overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                    )
                },
                colors = translucentChip,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 12.dp)
                    .widthIn(max = 100.dp),
            )
        } else {
            // Replaces the Route chip with Sign-in when unauthed.
            // Same position so the curve looks identical regardless
            // of auth state.
            CompactChip(
                onClick = onSignIn,
                label = {
                    Text(
                        "Sign in",
                        style = MaterialTheme.typography.caption3,
                        maxLines = 1,
                    )
                },
                colors = translucentChip,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 12.dp),
            )
        }
        CompactChip(
            onClick = onCyclePace,
            label = {
                Text(
                    if (targetPaceSecPerKm == null) "Pace"
                    else formatPace(targetPaceSecPerKm.toDouble()),
                    style = MaterialTheme.typography.caption3,
                    maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                )
            },
            colors = translucentChip,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 8.dp, bottom = 30.dp)
                .widthIn(max = 60.dp),
        )

        // Top-corner icon buttons. Sign-out at TopEnd, "fix battery
        // optimisation" warning at TopStart — both get the same
        // translucent treatment so they don't blot out the route
        // map underneath. The battery warning used to be a wide
        // chip stuffed into the bottom rail, where it pushed the
        // chip rail up into the Start button. As an icon it stays
        // visible without crowding the primary action.
        val cornerIconColors = ButtonDefaults.secondaryButtonColors(
            backgroundColor = Color.Black.copy(alpha = 0.55f),
            contentColor = DuskPalette.parchment,
        )
        if (batteryOptimised) {
            CompactButton(
                onClick = onFixBattery,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(top = 26.dp, start = 26.dp),
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
                    .padding(top = 26.dp, end = 26.dp),
                colors = cornerIconColors,
            ) {
                Icon(
                    imageVector = Icons.Filled.ExitToApp,
                    contentDescription = "Sign out",
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
                "Sign in",
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
                label = "Email",
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
                label = "Password",
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
                        Text("Submit")
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
                label = { Text("Cancel") },
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
                        "Tap here",
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
    bpm: Int?,
    steps: Int?,
    lapCount: Int,
    paused: Boolean,
    locationAvailable: Boolean,
    noGpsYet: Boolean,
    offRouteDistanceM: Double?,
    routeRemainingM: Double?,
    routeWaypoints: List<com.runapp.watchwear.recording.RouteMath.LatLng>,
    latestPoint: com.runapp.watchwear.GpsPoint?,
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
                    "%.2f km".format(distanceM / 1000.0),
                    style = MaterialTheme.typography.body1,
                    color = Color.White.copy(alpha = 0.72f),
                )
                if (paused) {
                    Spacer(Modifier.height(2.dp))
                    Text(
                        "paused",
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
    val showMiniMap = routeWaypoints.isNotEmpty() ||
        trackOverlayPoints.size >= 2 ||
        latestPoint != null

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
                current = latestPoint?.let {
                    com.runapp.watchwear.recording.RouteMath.LatLng(it.lat, it.lng)
                },
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
                    if (noGpsYet) "No GPS — time only" else "GPS lost",
                    style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                    color = DuskPalette.warning,
                )
            }
            if (wasOffRoute && offRouteDistanceM != null) {
                Text(
                    "Off route · ${offRouteDistanceM.toInt()} m",
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
                "%.2f km".format(distanceM / 1000.0),
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
                    "${formatPace(paceSecPerKm)} /km",
                    style = MaterialTheme.typography.caption2.copy(shadow = captionShadow),
                    color = DuskPalette.parchment,
                )
            }
            if (routeRemainingM != null && routeRemainingM > 1.0) {
                Text(
                    "%.2f km to go".format(routeRemainingM / 1000.0),
                    style = MaterialTheme.typography.caption3.copy(shadow = captionShadow),
                    color = DuskPalette.lilac,
                )
            }
            val secondary = listOfNotNull(
                bpm?.let { "$it bpm" },
                steps?.takeIf { it > 0 }?.let { "$it steps" },
                lapCount.takeIf { it > 0 }?.let { "Lap $it" },
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
                            .size(ButtonDefaults.SmallButtonSize),
                    ) {
                        Text("Go", style = MaterialTheme.typography.caption3)
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
                            .size(ButtonDefaults.SmallButtonSize),
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
                        .size(ButtonDefaults.SmallButtonSize),
                    colors = translucent,
                ) {
                    Text("Lap", style = MaterialTheme.typography.caption3)
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
    onPick: (com.runapp.watchwear.SavedRoute) -> Unit,
    onClear: () -> Unit,
    onCancel: () -> Unit,
) {
    val listState = rememberScalingLazyListState()
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        state = listState,
        horizontalAlignment = Alignment.CenterHorizontally,
        autoCentering = AutoCenteringParams(itemIndex = 0),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 24.dp),
    ) {
        item {
            Text(
                "Route",
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
                        "None",
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
                            "%.2f km".format(r.distanceM / 1000.0),
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
                    "No saved routes. Build a route on the phone or web first.",
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
                label = { Text("Cancel") },
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
                "Stop",
                style = MaterialTheme.typography.caption2,
                color = MaterialTheme.colors.onPrimary,
            )
        }
    }
}

@Composable
private fun PostRunScreen(
    summary: com.runapp.watchwear.FinishedSummary?,
    synced: Boolean,
    syncing: Boolean,
    syncError: String?,
    onSync: () -> Unit,
    onStartNext: () -> Unit,
    onDiscard: () -> Unit,
) {
    val listState = rememberScalingLazyListState()
    Box(modifier = Modifier.fillMaxSize()) {
        ScalingLazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            horizontalAlignment = Alignment.CenterHorizontally,
            // Auto-center the first item so the distance stat lands in the
            // middle of the round face instead of colliding with TimeText.
            autoCentering = AutoCenteringParams(itemIndex = 0),
            contentPadding = PaddingValues(horizontal = 12.dp),
        ) {
            if (summary != null) {
                // Route preview thumbnail at the top of the column —
                // the actual shape the runner just ran. Renders
                // tiles + the recorded track polyline; no `current`
                // because the run is over. Hidden for indoor runs
                // where the track has fewer than 2 points.
                if (summary.trackLatLngs.size >= 2) {
                    item {
                        RouteMiniMap(
                            route = emptyList(),
                            current = null,
                            track = summary.trackLatLngs,
                            modifier = Modifier.size(96.dp),
                        )
                    }
                }
                item {
                    Text(
                        "%.2f km".format(summary.distanceM / 1000.0),
                        style = MaterialTheme.typography.title2,
                    )
                }
                item {
                    Text(
                        formatDuration(summary.durationS),
                        style = MaterialTheme.typography.caption2,
                        color = DuskPalette.haze,
                    )
                }
                if (summary.avgBpm != null) {
                    item {
                        Text(
                            "${summary.avgBpm.toInt()} bpm avg",
                            style = MaterialTheme.typography.caption3,
                            color = DuskPalette.error,
                        )
                    }
                }
            }
            if (syncError != null) {
                item {
                    Text(
                        syncError,
                        style = MaterialTheme.typography.caption3,
                        color = DuskPalette.error,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    )
                }
            }

            // Splits table — one row per lap. Rendered compactly with
            // the lap number, pace for that split, and cumulative
            // distance. Hides entirely when the user didn't tap Lap.
            if (summary != null && summary.laps.isNotEmpty()) {
                item {
                    Text(
                        "Splits",
                        style = MaterialTheme.typography.caption2,
                        color = DuskPalette.lilac,
                        modifier = Modifier.padding(top = 6.dp),
                    )
                }
                items(summary.laps.size) { i ->
                    val lap = summary.laps[i]
                    androidx.compose.foundation.layout.Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 10.dp, vertical = 3.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            "Lap ${lap.number}",
                            style = MaterialTheme.typography.caption3,
                            color = DuskPalette.haze,
                        )
                        Text(
                            formatLapSplit(lap),
                            style = MaterialTheme.typography.caption3,
                            color = DuskPalette.parchment,
                        )
                    }
                }
            }
            if (synced) {
                item {
                    Text(
                        "Synced",
                        style = MaterialTheme.typography.caption2,
                        color = DuskPalette.success,
                        modifier = Modifier.padding(vertical = 4.dp),
                    )
                }
                item {
                    Chip(
                        onClick = onStartNext,
                        label = { Text("Done") },
                        colors = ChipDefaults.primaryChipColors(),
                        // 0.78f instead of fillMaxWidth(): the chip
                        // sits in the bottom arc of the round face
                        // where the bezel curves inward, so a full-
                        // width chip gets its end caps clipped. 78 %
                        // matches the chord width about 28 dp from
                        // the bottom edge.
                        modifier = Modifier.fillMaxWidth(0.78f),
                    )
                }
            } else {
                item {
                    Chip(
                        onClick = onSync,
                        enabled = !syncing,
                        label = {
                            if (syncing) {
                                CircularProgressIndicator(
                                    strokeWidth = 2.dp,
                                    modifier = Modifier.height(16.dp),
                                )
                            } else {
                                Text("Sync")
                            }
                        },
                        colors = ChipDefaults.primaryChipColors(),
                        // 0.78f instead of fillMaxWidth(): the chip
                        // sits in the bottom arc of the round face
                        // where the bezel curves inward, so a full-
                        // width chip gets its end caps clipped. 78 %
                        // matches the chord width about 28 dp from
                        // the bottom edge.
                        modifier = Modifier.fillMaxWidth(0.78f),
                    )
                }
                item {
                    Chip(
                        onClick = onStartNext,
                        label = { Text("Start next run") },
                        colors = ChipDefaults.secondaryChipColors(),
                        modifier = Modifier.fillMaxWidth(0.78f),
                    )
                }
            }
        }

        // Small destructive action at ~2 o'clock — same offset as the
        // PreRun sign-out icon so it lands inside the round-bezel inscribed
        // rectangle. Only shows before the run is synced.
        if (!synced && summary != null) {
            CompactButton(
                onClick = onDiscard,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 24.dp, end = 24.dp),
                colors = ButtonDefaults.secondaryButtonColors(),
            ) {
                Text(
                    "×",
                    style = MaterialTheme.typography.body1,
                )
            }
        }
    }
}

private fun formatLapSplit(lap: com.runapp.watchwear.FinishedLap): String {
    val m = lap.splitSeconds / 60
    val s = lap.splitSeconds % 60
    val km = lap.splitDistanceM / 1000.0
    return "%d:%02d · %.2f km".format(m, s, km)
}

private fun formatDuration(totalS: Int): String {
    val h = totalS / 3600
    val m = (totalS % 3600) / 60
    val s = totalS % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}

private fun formatElapsed(ms: Long): String {
    val total = ms / 1000
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
}

private fun formatPace(secPerKm: Double): String {
    val m = (secPerKm / 60).toInt()
    val s = (secPerKm % 60).toInt()
    return "%d:%02d".format(m, s)
}

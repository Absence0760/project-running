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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExitToApp
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.graphics.SolidColor
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

@Composable
fun RunWatchApp(vm: RunViewModel, activity: Activity) {
    val state by vm.state.collectAsStateWithLifecycle()
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions(),
    ) { granted ->
        if (granted[Manifest.permission.ACCESS_FINE_LOCATION] == true) {
            vm.start()
        }
    }

    DuskTheme {
        Scaffold(
            timeText = { TimeText() },
            vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        ) {
            when (state.stage) {
                Stage.PreRun -> PreRunScreen(
                    queuedCount = state.queuedCount,
                    authed = state.authed,
                    authError = state.authError,
                    batteryOptimised = state.batteryOptimised,
                    pendingRecoveryDistance = state.pendingRecovery?.distanceM,
                    onStart = {
                        permissionLauncher.launch(
                            arrayOf(
                                Manifest.permission.ACCESS_FINE_LOCATION,
                                Manifest.permission.BODY_SENSORS,
                            )
                        )
                    },
                    onSignIn = vm::openSignIn,
                    onSignOut = vm::signOut,
                    onFixBattery = { BatteryOptimization.requestExemption(activity) },
                    onRecover = vm::recoverCheckpoint,
                    onDiscardRecovery = vm::discardCheckpoint,
                )
                Stage.SignIn -> SignInScreen(
                    authError = state.authError,
                    loading = state.signInLoading,
                    onSubmit = vm::signInWithEmail,
                    onCancel = vm::cancelSignIn,
                )
                Stage.Running -> RunningScreen(
                    elapsedMs = state.elapsedMs,
                    distanceM = state.distanceM,
                    paceSecPerKm = state.paceSecPerKm,
                    bpm = state.bpm,
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
            }
        }
    }
}

@Composable
private fun PreRunScreen(
    queuedCount: Int,
    authed: Boolean,
    authError: String?,
    batteryOptimised: Boolean,
    pendingRecoveryDistance: Double?,
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

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            // Status caption above the Start button. Order: queued count
            // first (most relevant), then any auth-error detail. The
            // "Ready to Run" heading was dropped — the big Start button
            // is self-explanatory and removing the heading frees the
            // top-right area for the sign-out icon to live alone.
            if (queuedCount > 0) {
                Text(
                    "$queuedCount run${if (queuedCount == 1) "" else "s"} to sync",
                    style = MaterialTheme.typography.caption3,
                    color = DuskPalette.haze,
                )
                Spacer(Modifier.height(4.dp))
            }
            if (!authed) {
                Text(
                    "Offline",
                    style = MaterialTheme.typography.caption3,
                    color = DuskPalette.warning,
                )
                if (authError != null) {
                    Text(
                        authError,
                        style = MaterialTheme.typography.caption3,
                        color = DuskPalette.error,
                        textAlign = TextAlign.Center,
                    )
                }
                Spacer(Modifier.height(4.dp))
            }
            Button(
                onClick = onStart,
                modifier = Modifier.size(ButtonDefaults.LargeButtonSize + 20.dp),
            ) {
                Text(
                    "Start",
                    style = MaterialTheme.typography.title3,
                )
            }
            if (!authed) {
                Spacer(Modifier.height(4.dp))
                CompactChip(
                    onClick = onSignIn,
                    label = { Text("Sign in", style = MaterialTheme.typography.caption2) },
                    colors = ChipDefaults.secondaryChipColors(),
                )
            }
            if (batteryOptimised) {
                Spacer(Modifier.height(4.dp))
                CompactChip(
                    onClick = onFixBattery,
                    label = {
                        Text(
                            "Fix battery saver",
                            style = MaterialTheme.typography.caption3,
                        )
                    },
                    colors = ChipDefaults.secondaryChipColors(),
                )
            }
        }

        // Small exit-icon button at ~2 o'clock. The round bezel cuts off
        // the bounding-box corner — TopEnd with 8dp padding ends up outside
        // the visible circle. ~24dp pulls it well inside the inscribed
        // rectangle on a typical round face.
        if (authed) {
            CompactButton(
                onClick = onSignOut,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 24.dp, end = 24.dp),
                colors = ButtonDefaults.secondaryButtonColors(),
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
    onStop: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            formatElapsed(elapsedMs),
            style = MaterialTheme.typography.display2,
        )
        Spacer(Modifier.height(2.dp))
        Text(
            "%.2f km".format(distanceM / 1000.0),
            style = MaterialTheme.typography.body2,
        )
        // Hide the pace row until the recorder has enough distance to
        // compute one — a "--:-- /km" placeholder looked enough like an
        // HR placeholder to be confusing.
        if (paceSecPerKm != null && paceSecPerKm > 0) {
            Text(
                "${formatPace(paceSecPerKm)} /km",
                style = MaterialTheme.typography.caption3,
                color = DuskPalette.haze,
            )
        }
        // Only render the HR row when we actually got a sample. With
        // ENABLE_HR off (the default), the ViewModel never starts the
        // sensor and `bpm` stays null — so the row vanishes entirely
        // rather than teaching the user to trust a "— bpm" placeholder.
        if (bpm != null) {
            Text(
                "$bpm bpm",
                style = MaterialTheme.typography.caption3,
                color = DuskPalette.error,
            )
        }
        Spacer(Modifier.height(8.dp))
        Button(onClick = onStop) {
            Text("Stop")
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
                        modifier = Modifier.fillMaxWidth(),
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
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                item {
                    Chip(
                        onClick = onStartNext,
                        label = { Text("Start next run") },
                        colors = ChipDefaults.secondaryChipColors(),
                        modifier = Modifier.fillMaxWidth(),
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

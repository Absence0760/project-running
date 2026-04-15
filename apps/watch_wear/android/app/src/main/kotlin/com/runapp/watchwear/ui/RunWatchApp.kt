package com.runapp.watchwear.ui

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.Vignette
import androidx.wear.compose.material.VignettePosition
import com.runapp.watchwear.RunViewModel
import com.runapp.watchwear.Stage

@Composable
fun RunWatchApp(vm: RunViewModel) {
    val state by vm.state.collectAsStateWithLifecycle()
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions(),
    ) { granted ->
        if (granted.values.all { it }) vm.start()
    }

    MaterialTheme {
        Scaffold(
            timeText = { TimeText() },
            vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        ) {
            when (state.stage) {
                Stage.PreRun -> PreRunScreen(
                    queuedCount = state.queuedCount,
                    authed = state.authed,
                    authError = state.authError,
                    onStart = {
                        permissionLauncher.launch(
                            arrayOf(
                                Manifest.permission.ACCESS_FINE_LOCATION,
                                Manifest.permission.BODY_SENSORS,
                            )
                        )
                    },
                    onSignIn = vm::openSignIn,
                )
                Stage.SignIn -> SignInScreen(
                    authError = state.authError,
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
    onStart: () -> Unit,
    onSignIn: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("Ready to Run", style = MaterialTheme.typography.title3)
        Spacer(Modifier.height(4.dp))
        if (queuedCount > 0) {
            Text(
                "$queuedCount run${if (queuedCount == 1) "" else "s"} to sync",
                style = MaterialTheme.typography.caption3,
                color = Color.LightGray,
            )
        }
        if (!authed) {
            Text("Offline", style = MaterialTheme.typography.caption3, color = Color(0xFFFFA726))
            if (authError != null) {
                Text(
                    authError,
                    style = MaterialTheme.typography.caption3,
                    color = Color(0xFFEF5350),
                    textAlign = TextAlign.Center,
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Button(onClick = onStart) {
            Text("Start")
        }
        if (!authed) {
            Spacer(Modifier.height(4.dp))
            Button(onClick = onSignIn, colors = ButtonDefaults.secondaryButtonColors()) {
                Text("Sign in", style = MaterialTheme.typography.caption2)
            }
        }
    }
}

/// Direct email/password sign-in for users without a paired Android phone.
/// The UX is rough on a 46mm screen — voice input is usually less painful
/// than the on-screen keyboard for the email. Typing credentials on a
/// watch is not the recommended path; if a paired Android phone is
/// available, sign in there and the Wearable Data Layer bridge takes over.
@Composable
private fun SignInScreen(
    authError: String?,
    onSubmit: (email: String, password: String) -> Unit,
    onCancel: () -> Unit,
) {
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }

    val scroll = rememberScrollState()
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(scroll)
            .padding(horizontal = 12.dp, vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("Sign in", style = MaterialTheme.typography.title3)
        Spacer(Modifier.height(6.dp))
        Text(
            "Email",
            style = MaterialTheme.typography.caption3,
            color = Color.LightGray,
        )
        BasicTextField(
            value = email,
            onValueChange = { email = it.trim() },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Email,
            ),
            textStyle = MaterialTheme.typography.body2.copy(color = Color.White),
            decorationBox = { inner ->
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFF222222))
                        .padding(6.dp),
                ) { inner() }
            },
            modifier = Modifier.padding(vertical = 2.dp),
        )
        Spacer(Modifier.height(6.dp))
        Text(
            "Password",
            style = MaterialTheme.typography.caption3,
            color = Color.LightGray,
        )
        BasicTextField(
            value = password,
            onValueChange = { password = it },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Password,
            ),
            visualTransformation = PasswordVisualTransformation(),
            textStyle = MaterialTheme.typography.body2.copy(color = Color.White),
            decorationBox = { inner ->
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFF222222))
                        .padding(6.dp),
                ) { inner() }
            },
            modifier = Modifier.padding(vertical = 2.dp),
        )
        if (authError != null) {
            Spacer(Modifier.height(4.dp))
            Text(
                authError,
                style = MaterialTheme.typography.caption3,
                color = Color(0xFFEF5350),
                textAlign = TextAlign.Center,
            )
        }
        Spacer(Modifier.height(8.dp))
        Button(
            onClick = { onSubmit(email, password) },
            enabled = email.isNotEmpty() && password.isNotEmpty(),
        ) {
            Text("Submit")
        }
        Spacer(Modifier.height(4.dp))
        Button(
            onClick = onCancel,
            colors = ButtonDefaults.secondaryButtonColors(),
        ) {
            Text("Cancel", style = MaterialTheme.typography.caption2)
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
        Text(
            paceSecPerKm?.let { "${formatPace(it)} /km" } ?: "--:-- /km",
            style = MaterialTheme.typography.caption3,
            color = Color.LightGray,
        )
        Text(
            bpm?.let { "$it bpm" } ?: "— bpm",
            style = MaterialTheme.typography.caption3,
            color = Color(0xFFEF5350),
        )
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
    Scaffold(
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        ScalingLazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            item { Text("Run Complete", style = MaterialTheme.typography.title3) }
            if (summary != null) {
                item {
                    Text(
                        "%.2f km".format(summary.distanceM / 1000.0),
                        style = MaterialTheme.typography.body1,
                    )
                }
                item {
                    Text(
                        "${summary.durationS / 60}m ${summary.durationS % 60}s",
                        style = MaterialTheme.typography.caption3,
                        color = Color.LightGray,
                    )
                }
                if (summary.avgBpm != null) {
                    item {
                        Text(
                            "${summary.avgBpm.toInt()} bpm avg",
                            style = MaterialTheme.typography.caption3,
                            color = Color(0xFFEF5350),
                        )
                    }
                }
            }
            if (syncError != null) {
                item {
                    Text(
                        syncError,
                        style = MaterialTheme.typography.caption3,
                        color = Color(0xFFEF5350),
                        textAlign = TextAlign.Center,
                    )
                }
            }
            if (synced) {
                item { Text("Synced", style = MaterialTheme.typography.caption2) }
                item { Button(onClick = onStartNext) { Text("Done") } }
            } else {
                item {
                    Button(onClick = onSync, enabled = !syncing) {
                        if (syncing) CircularProgressIndicator(strokeWidth = 2.dp)
                        else Text("Sync")
                    }
                }
                item { Button(onClick = onStartNext, colors = ButtonDefaults.secondaryButtonColors()) { Text("Start next run") } }
                item { Button(onClick = onDiscard, colors = ButtonDefaults.secondaryButtonColors()) { Text("Discard") } }
            }
        }
    }
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

package com.runapp.watchwear.ui

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
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
                    onStart = {
                        permissionLauncher.launch(
                            arrayOf(
                                Manifest.permission.ACCESS_FINE_LOCATION,
                                Manifest.permission.BODY_SENSORS,
                            )
                        )
                    },
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
    onStart: () -> Unit,
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
        }
        Spacer(Modifier.height(8.dp))
        Button(onClick = onStart) {
            Text("Start")
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

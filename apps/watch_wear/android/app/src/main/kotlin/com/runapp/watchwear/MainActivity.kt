package com.runapp.watchwear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.lifecycle.ViewModelProvider
import androidx.wear.ambient.AmbientLifecycleObserver
import com.runapp.watchwear.ui.RunWatchApp
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

class MainActivity : ComponentActivity() {

    private val vm: RunViewModel by lazy {
        ViewModelProvider(this, RunViewModel.Factory(application))[RunViewModel::class.java]
    }

    private val _ambient = MutableStateFlow(false)
    val ambient = _ambient.asStateFlow()

    private val ambientCallback = object : AmbientLifecycleObserver.AmbientLifecycleCallback {
        override fun onEnterAmbient(ambientDetails: AmbientLifecycleObserver.AmbientDetails) {
            _ambient.value = true
        }

        override fun onExitAmbient() {
            _ambient.value = false
        }

        override fun onUpdateAmbient() {
            // Called ~once a minute. The foreground service keeps
            // writing to RecordingRepository so our ambient view just
            // re-renders on state change — no extra work needed here.
        }
    }

    private fun hasWearableLibrary(): Boolean {
        return try {
            Class.forName("com.google.android.wearable.compat.WearableActivityController")
            true
        } catch (_: ClassNotFoundException) {
            false
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (hasWearableLibrary()) {
            lifecycle.addObserver(AmbientLifecycleObserver(this, ambientCallback))
        }
        setContent {
            val isAmbient by ambient.collectAsState()
            RunWatchApp(vm = vm, activity = this, isAmbient = isAmbient)
        }
    }

    override fun onResume() {
        super.onResume()
        vm.refreshBatteryOptimisation()
    }
}

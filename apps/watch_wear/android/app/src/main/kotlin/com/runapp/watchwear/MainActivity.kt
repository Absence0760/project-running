package com.runapp.watchwear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.ViewModelProvider
import com.runapp.watchwear.ui.RunWatchApp

class MainActivity : ComponentActivity() {

    private val vm: RunViewModel by lazy {
        ViewModelProvider(this, RunViewModel.Factory(application))[RunViewModel::class.java]
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            RunWatchApp(vm = vm, activity = this)
        }
    }

    override fun onResume() {
        super.onResume()
        // Returning from the battery-optimisation system prompt — re-check
        // status so the warning banner disappears once granted.
        vm.refreshBatteryOptimisation()
    }
}

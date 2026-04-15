package com.runapp.watchwear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runapp.watchwear.ui.RunWatchApp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val vm: RunViewModel = viewModel(factory = RunViewModel.Factory(application))
            RunWatchApp(vm)
        }
    }
}

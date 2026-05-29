package com.threkir.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        WearAuthBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        WearRoutesBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        RunNotificationBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        // #14: the activity may have just been (re)launched by tapping a
        // Pause/Resume/Stop button on the run notification — forward that
        // action to Dart now that the engine + bridge exist.
        handleRunActionIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleRunActionIntent(intent)
    }

    private fun handleRunActionIntent(intent: Intent?) {
        val action = intent?.getStringExtra(RunNotificationBridge.EXTRA_RUN_ACTION) ?: return
        RunNotificationBridge.instance?.dispatchAction(action)
    }
}

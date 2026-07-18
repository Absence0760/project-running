package com.threkir.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/// Receives the lock-screen Pause/Resume/Stop notification-action broadcasts
/// posted by `RunNotificationBridge.actionIntent` and forwards the action to
/// Dart. A broadcast (not an activity launch) is what lets the button fire on
/// a locked phone without the keyguard unlock prompt (issue #270). The
/// recording foreground service keeps the process alive, so the bridge
/// singleton is live when this fires; if it somehow isn't, `dispatchAction`'s
/// null-instance path drops the action rather than crashing.
class RunActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.getStringExtra(RunNotificationBridge.EXTRA_RUN_ACTION) ?: return
        RunNotificationBridge.instance?.dispatchAction(action)
    }
}

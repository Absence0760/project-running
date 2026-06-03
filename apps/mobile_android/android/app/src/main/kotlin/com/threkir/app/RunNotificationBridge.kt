package com.threkir.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Replaces the foreground-service notification that `geolocator_android`
/// posts while a run is recording, so the lock screen + notification shade
/// show live time / distance / pace instead of a static "Run in progress".
///
/// This works by reposting a notification with the same channel id and
/// notification id that `GeolocatorLocationService` uses to call
/// `startForeground`. Android treats identical `(channel, id)` as an update
/// rather than a new notification, so our content overwrites the visible
/// row without detaching the foreground service — geolocator keeps feeding
/// us fixes and Android keeps honouring `FOREGROUND_SERVICE_LOCATION`.
///
/// Constants mirror `com.baseflow.geolocator.GeolocatorLocationService`:
///   CHANNEL_ID = "geolocator_channel_01"
///   ONGOING_NOTIFICATION_ID = 75415
/// If a future geolocator release changes either value this bridge stops
/// overriding silently (our notification becomes a second row) — fix by
/// updating the constants below.
class RunNotificationBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, CHANNEL)

    // #14: set true once the Dart side announces its method-call handler is
    // live (`ready`). A notification action that arrives before then (cold
    // start — the process was relaunched by tapping a button) is stashed
    // and flushed on `ready` so it isn't dropped.
    private var dartReady = false
    private var pendingAction: String? = null

    init {
        instance = this
        methodChannel.setMethodCallHandler(this)
        // Pre-create the notification channel with VISIBILITY_PUBLIC before
        // geolocator does. lockscreenVisibility is immutable after channel
        // creation, so winning the race is the only way to make live stats
        // visible on the lock screen — the channel that exists at
        // startForeground() time dictates what the system renders.
        ensureChannelHasLockScreenVisibility()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "update" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?>
                if (args == null) {
                    result.error("bad_args", "update needs a Map", null)
                    return
                }
                if (!hasPostNotificationsPermission()) {
                    // NotificationManager.notify silently no-ops on
                    // Android 13+ when POST_NOTIFICATIONS is not granted.
                    // Report that up so Dart knows the lock screen is stale
                    // rather than pretending we posted.
                    result.error(
                        "no_permission",
                        "POST_NOTIFICATIONS not granted",
                        null,
                    )
                    return
                }
                val title = args["title"] as? String
                    ?: context.getString(R.string.run_notif_title_fallback)
                val text = args["text"] as? String ?: ""
                val bigText = args["big_text"] as? String
                val paused = args["paused"] as? Boolean ?: false
                post(title, text, bigText, paused)
                result.success(null)
            }
            "ready" -> {
                dartReady = true
                pendingAction?.let { methodChannel.invokeMethod("action", it) }
                pendingAction = null
                result.success(null)
            }
            "clear" -> {
                NotificationManagerCompat.from(context)
                    .cancel(GEOLOCATOR_NOTIFICATION_ID)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /// Forward a lock-screen action ("pause" / "resume" / "stop") to Dart.
    /// Called by MainActivity when a notification-action PendingIntent
    /// relaunches the activity. If Dart hasn't registered its handler yet
    /// (cold start), stash and flush on `ready`.
    fun dispatchAction(action: String) {
        if (dartReady) {
            methodChannel.invokeMethod("action", action)
        } else {
            pendingAction = action
        }
    }

    private fun hasPostNotificationsPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun ensureChannelHasLockScreenVisibility() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        // If geolocator already created the channel with VISIBILITY_PRIVATE
        // we can't mutate lockscreenVisibility in place — but we can delete
        // and recreate. If the channel doesn't exist yet we create it first
        // so our settings stick before geolocator's do.
        val existing = nm.getNotificationChannel(GEOLOCATOR_CHANNEL_ID)
        if (existing != null &&
            existing.lockscreenVisibility == Notification.VISIBILITY_PUBLIC) {
            return
        }
        if (existing != null) nm.deleteNotificationChannel(GEOLOCATOR_CHANNEL_ID)
        val channel = NotificationChannel(
            GEOLOCATOR_CHANNEL_ID,
            context.getString(R.string.run_notif_channel_name),
            // LOW avoids the heads-up buzz while still showing on the
            // lock screen — matches Strava / Nike Run Club behaviour.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    /// PendingIntent that relaunches MainActivity carrying a `run_action`
    /// extra. Distinct request codes keep the three actions' PendingIntents
    /// from collapsing into one another under FLAG_UPDATE_CURRENT.
    private fun actionIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            this.action = "com.threkir.app.RUN_ACTION_$action"
            putExtra(EXTRA_RUN_ACTION, action)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun post(title: String, text: String, bigText: String?, paused: Boolean) {
        // Tapping the notification body returns the user to MainActivity.
        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            context,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(context, GEOLOCATOR_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            // Surface on the lock screen with full content. Geolocator's
            // default is PRIVATE which hides the text — ours is the whole
            // point of this bridge.
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(pending)

        if (!bigText.isNullOrBlank()) {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(bigText))
        }

        // #14: lock-screen controls. Pause toggles to Resume while paused;
        // Stop ends the run. Icon 0 renders text-only, which is fine on a
        // workout notification and avoids shipping new drawables.
        if (paused) {
            builder.addAction(
                0,
                context.getString(R.string.run_notif_action_resume),
                actionIntent(ACTION_RESUME, RC_RESUME),
            )
        } else {
            builder.addAction(
                0,
                context.getString(R.string.run_notif_action_pause),
                actionIntent(ACTION_PAUSE, RC_PAUSE),
            )
        }
        builder.addAction(
            0,
            context.getString(R.string.run_notif_action_stop),
            actionIntent(ACTION_STOP, RC_STOP),
        )

        // Posting with the same (channel, id) that geolocator's foreground
        // service is using replaces the visible row without interfering
        // with the service lifecycle — startForeground() was called with
        // the same id, so Android's tracked foreground notification is
        // still alive; we've just swapped out what it renders.
        NotificationManagerCompat.from(context)
            .notify(GEOLOCATOR_NOTIFICATION_ID, builder.build())
    }

    companion object {
        private const val CHANNEL = "run_app/run_notification"
        // Mirrors com.baseflow.geolocator.GeolocatorLocationService:
        //   CHANNEL_ID = "geolocator_channel_01"
        //   ONGOING_NOTIFICATION_ID = 75415
        // If a future geolocator release changes these, our replacement
        // stops applying silently — update here if you see a second row.
        private const val GEOLOCATOR_CHANNEL_ID = "geolocator_channel_01"
        private const val GEOLOCATOR_NOTIFICATION_ID = 75415

        // #14: notification-action plumbing. MainActivity reads
        // EXTRA_RUN_ACTION off a relaunch intent and forwards it here.
        const val EXTRA_RUN_ACTION = "run_action"
        private const val ACTION_PAUSE = "pause"
        private const val ACTION_RESUME = "resume"
        private const val ACTION_STOP = "stop"
        private const val RC_PAUSE = 101
        private const val RC_RESUME = 102
        private const val RC_STOP = 103

        /// Live instance so MainActivity can forward notification-action
        /// intents into the method channel. The bridge outlives any single
        /// intent because it's created with the application context in
        /// MainActivity.configureFlutterEngine.
        @Volatile
        var instance: RunNotificationBridge? = null
            private set
    }
}

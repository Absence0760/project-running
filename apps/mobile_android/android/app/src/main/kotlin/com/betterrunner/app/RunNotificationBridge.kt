package com.betterrunner.app

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
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

    companion object {
        private const val CHANNEL = "run_app/run_notification"
        private const val GEOLOCATOR_CHANNEL_ID = "geolocator_channel_01"
        private const val GEOLOCATOR_NOTIFICATION_ID = 75415
    }

    private val methodChannel = MethodChannel(messenger, CHANNEL)

    init {
        methodChannel.setMethodCallHandler(this)
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
                val title = args["title"] as? String ?: "Running"
                val text = args["text"] as? String ?: ""
                val bigText = args["big_text"] as? String
                post(title, text, bigText)
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

    private fun post(title: String, text: String, bigText: String?) {
        // Tapping the notification returns the user to MainActivity.
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
            .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(pending)

        if (!bigText.isNullOrBlank()) {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(bigText))
        }

        // Posting with the same (channel, id) that geolocator's foreground
        // service is using replaces the visible row without interfering
        // with the service lifecycle — startForeground() was called with
        // the same id, so Android's tracked foreground notification is
        // still alive; we've just swapped out what it renders.
        NotificationManagerCompat.from(context)
            .notify(GEOLOCATOR_NOTIFICATION_ID, builder.build())
    }
}

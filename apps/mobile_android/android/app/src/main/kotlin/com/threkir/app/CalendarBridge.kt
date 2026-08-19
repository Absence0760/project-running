package com.threkir.app

import android.content.Context
import android.content.Intent
import android.provider.CalendarContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Opens the calendar app's own new-event editor pre-filled from a club event,
/// so adding it costs no calendar permission — ACTION_INSERT hands the values
/// to whichever app the user picked and they confirm the save themselves.
/// Dart side: `lib/calendar_intent.dart` over `run_app/calendar`.
class CalendarBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, "run_app/calendar")

    init {
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "addEvent" -> result.success(insert(call))
            else -> result.notImplemented()
        }
    }

    private fun insert(call: MethodCall): Boolean {
        val title = call.argument<String>("title") ?: return false
        val startMs = call.argument<Number>("startMs")?.toLong() ?: return false
        val intent = Intent(Intent.ACTION_INSERT)
            .setData(CalendarContract.Events.CONTENT_URI)
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startMs)
            .putExtra(CalendarContract.Events.TITLE, title)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        call.argument<Number>("endMs")?.let {
            intent.putExtra(CalendarContract.EXTRA_EVENT_END_TIME, it.toLong())
        }
        call.argument<String>("location")?.let {
            intent.putExtra(CalendarContract.Events.EVENT_LOCATION, it)
        }
        call.argument<String>("rrule")?.let {
            intent.putExtra(CalendarContract.Events.RRULE, it)
        }
        // The insert intent has no URL extra, so the link back to the club
        // event rides along in the notes.
        val notes = listOfNotNull(
            call.argument<String>("description"),
            call.argument<String>("url")
        ).joinToString("\n\n")
        if (notes.isNotEmpty()) {
            intent.putExtra(CalendarContract.Events.DESCRIPTION, notes)
        }

        return try {
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}

package com.runapp.watchwear.tiles

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.sp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.FontStyle
import androidx.wear.protolayout.LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.protolayout.material.Colors
import androidx.wear.protolayout.material.Text
import androidx.wear.protolayout.material.Typography
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders.Tile
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.runapp.watchwear.MainActivity
import com.runapp.watchwear.R
import com.runapp.watchwear.recording.DistanceUnit
import com.runapp.watchwear.recording.RecordingRepository
import com.runapp.watchwear.recording.formatDistance
import com.runapp.watchwear.recording.paceSecPerUnit
import java.util.Locale

/// Glanceable tile that shows the active-run summary on the runner's
/// watch face. Exists in two visual states — chosen at request time
/// from `RecordingRepository.metrics.value`:
///
///   - **Idle**: a single "Tap to start" prompt. Tapping the tile
///     opens the app on the pre-run screen so the runner can pick
///     activity / route and tap GO. The tile is intentionally not
///     a one-tap-start affordance; runners often pick a route from
///     the watch list, and a one-tap "this starts a run NOW" tile
///     would be a foot-gun for a casual swipe.
///   - **Active** (Recording or Paused): elapsed time as the headline
///     plus distance + pace as a stat row. Tapping resumes / opens
///     the running screen.
///
/// Tile updates are pushed externally via [requestUpdate] from the
/// recording service on every state transition (start, pause, stop)
/// and at a coarse cadence during a run — the tile renderer caches
/// the last layout, so we don't need a per-second refresh; the user
/// only sees the tile when they swipe to it. A 30-second freshness
/// window via [TimelineEntry] handles the "swiped while running 5
/// minutes after the last forced refresh" case.
///
/// The tile is registered in `AndroidManifest.xml` with the
/// `androidx.wear.tiles.action.BIND_TILE_PROVIDER` intent filter and
/// the `BIND_TILE_PROVIDER` permission. The XML preview drawable
/// referenced from `<meta-data>` is what watch face customization UI
/// shows when adding the tile.
class ActiveRunTileService : TileService() {

    override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest,
    ): ListenableFuture<Tile> {
        val metrics = RecordingRepository.metrics.value
        val layout = if (metrics.isActive) {
            buildActiveLayout(this, metrics)
        } else {
            buildIdleLayout(this)
        }
        val tile = Tile.Builder()
            .setResourcesVersion(RESOURCES_VERSION)
            .setTileTimeline(
                TimelineBuilders.Timeline.Builder()
                    .addTimelineEntry(
                        TimelineBuilders.TimelineEntry.Builder()
                            .setLayout(
                                LayoutElementBuilders.Layout.Builder()
                                    .setRoot(layout)
                                    .build(),
                            )
                            .build(),
                    )
                    .build(),
            )
            // Re-request the tile after this many ms so a runner who
            // glances at the tile mid-run sees stats no older than 30
            // seconds without us waking up the recording service to
            // push every tick.
            .setFreshnessIntervalMillis(if (metrics.isActive) 30_000L else 0L)
            .build()
        return Futures.immediateFuture(tile)
    }

    override fun onTileResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest,
    ): ListenableFuture<ResourceBuilders.Resources> {
        val resources = ResourceBuilders.Resources.Builder()
            .setVersion(RESOURCES_VERSION)
            .build()
        return Futures.immediateFuture(resources)
    }

    companion object {
        private const val RESOURCES_VERSION = "1"

        /// Tell the platform to re-fetch the tile because the underlying
        /// state changed. Called from `RunRecordingService` whenever
        /// `Stage` transitions or distance ticks past a meaningful
        /// threshold — the platform debounces multiple rapid calls.
        fun requestUpdate(context: Context) {
            getUpdater(context).requestUpdate(ActiveRunTileService::class.java)
        }
    }
}

private fun buildIdleLayout(context: Context): LayoutElementBuilders.LayoutElement {
    val intent = Intent(context, MainActivity::class.java).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    val tapModifier = ModifiersBuilders.Modifiers.Builder()
        .setClickable(
            ModifiersBuilders.Clickable.Builder()
                .setId("idle_tap")
                .setOnClick(
                    androidx.wear.protolayout.ActionBuilders.LaunchAction.Builder()
                        .setAndroidActivity(
                            androidx.wear.protolayout.ActionBuilders.AndroidActivity.Builder()
                                .setClassName(MainActivity::class.java.name)
                                .setPackageName(context.packageName)
                                .build(),
                        )
                        .build(),
                )
                .build(),
        )
        .build()

    return LayoutElementBuilders.Box.Builder()
        .setWidth(androidx.wear.protolayout.DimensionBuilders.expand())
        .setHeight(androidx.wear.protolayout.DimensionBuilders.expand())
        .setHorizontalAlignment(HORIZONTAL_ALIGN_CENTER)
        .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
        .setModifiers(tapModifier)
        .addContent(
            LayoutElementBuilders.Column.Builder()
                .setHorizontalAlignment(HORIZONTAL_ALIGN_CENTER)
                .addContent(
                    Text.Builder(context, context.getString(R.string.tile_run))
                        .setTypography(Typography.TYPOGRAPHY_TITLE3)
                        .setColor(argb(Colors.DEFAULT.primary))
                        .build(),
                )
                .addContent(verticalSpacer(8))
                .addContent(
                    Text.Builder(context, context.getString(R.string.tile_tap_to_start))
                        .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                        .setColor(argb(Colors.DEFAULT.onSurface))
                        .build(),
                )
                .build(),
        )
        .build()
}

private fun buildActiveLayout(
    context: Context,
    metrics: RecordingRepository.Metrics,
): LayoutElementBuilders.LayoutElement {
    val tapModifier = ModifiersBuilders.Modifiers.Builder()
        .setClickable(
            ModifiersBuilders.Clickable.Builder()
                .setId("active_tap")
                .setOnClick(
                    androidx.wear.protolayout.ActionBuilders.LaunchAction.Builder()
                        .setAndroidActivity(
                            androidx.wear.protolayout.ActionBuilders.AndroidActivity.Builder()
                                .setClassName(MainActivity::class.java.name)
                                .setPackageName(context.packageName)
                                .build(),
                        )
                        .build(),
                )
                .build(),
        )
        .build()

    val statusLabel = if (metrics.stage == RecordingRepository.Stage.Paused) {
        context.getString(R.string.tile_paused)
    } else {
        context.getString(R.string.tile_running)
    }

    return LayoutElementBuilders.Box.Builder()
        .setWidth(androidx.wear.protolayout.DimensionBuilders.expand())
        .setHeight(androidx.wear.protolayout.DimensionBuilders.expand())
        .setHorizontalAlignment(HORIZONTAL_ALIGN_CENTER)
        .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
        .setModifiers(tapModifier)
        .addContent(
            LayoutElementBuilders.Column.Builder()
                .setHorizontalAlignment(HORIZONTAL_ALIGN_CENTER)
                .addContent(
                    Text.Builder(context, statusLabel)
                        .setTypography(Typography.TYPOGRAPHY_CAPTION2)
                        .setColor(argb(Colors.DEFAULT.primary))
                        .build(),
                )
                .addContent(verticalSpacer(4))
                .addContent(
                    LayoutElementBuilders.Text.Builder()
                        .setText(formatElapsed(metrics.elapsedMs))
                        .setFontStyle(
                            FontStyle.Builder()
                                .setSize(sp(28f))
                                .setColor(argb(Colors.DEFAULT.onSurface))
                                .setWeight(LayoutElementBuilders.FONT_WEIGHT_MEDIUM)
                                .build(),
                        )
                        .build(),
                )
                .addContent(verticalSpacer(6))
                .addContent(
                    Text.Builder(context, formatStatRow(metrics))
                        .setTypography(Typography.TYPOGRAPHY_BODY2)
                        .setColor(argb(Colors.DEFAULT.onSurface))
                        .build(),
                )
                .build(),
        )
        .build()
}

private fun verticalSpacer(heightDp: Int): LayoutElementBuilders.LayoutElement =
    LayoutElementBuilders.Spacer.Builder()
        .setHeight(dp(heightDp.toFloat()))
        .build()

/// Format `elapsedMs` as `H:MM:SS` (or `MM:SS` under an hour). Pure
/// helper so the unit test can pin the tile's surfaces without
/// running ProtoLayout. Time digits are locale-independent (no decimal
/// separator involved), so the format Locale is fixed for stability.
internal fun formatElapsed(elapsedMs: Long): String {
    val totalSeconds = (elapsedMs / 1000L).coerceAtLeast(0L)
    val hours = totalSeconds / 3600L
    val minutes = (totalSeconds % 3600L) / 60L
    val seconds = totalSeconds % 60L
    return if (hours > 0) {
        String.format(Locale.ROOT, "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format(Locale.ROOT, "%02d:%02d", minutes, seconds)
    }
}

/// Render the secondary stat row: distance and pace separated by a
/// middle-dot, both in the run's [DistanceUnit] (stamped on the metrics
/// at run start from the runner's `preferred_unit` pref). Pure helper so
/// the layout file stays readable and the formatting is testable in
/// isolation. The distance decimal separator follows [locale] (device
/// locale at the call site); the unit word ("km" / "mi") is invariant
/// across the six shipped locales, the same way "km" was inlined before.
internal fun formatStatRow(
    metrics: RecordingRepository.Metrics,
    locale: Locale = Locale.getDefault(),
): String {
    val unit = metrics.preferredUnit
    val unitWord = unitWord(unit)
    val displayValue = when (unit) {
        DistanceUnit.KM -> metrics.distanceM / 1000.0
        DistanceUnit.MI -> metrics.distanceM / com.runapp.watchwear.recording.METRES_PER_MILE
    }
    val decimals = if (displayValue >= 10.0) 1 else 2
    val distLabel = "${formatDistance(metrics.distanceM, unit, decimals, locale)} $unitWord"
    val paceLabel = formatPaceSecPerUnit(metrics.paceSecPerKm, unit)
    return "$distLabel · $paceLabel"
}

internal fun formatPaceSecPerUnit(secPerKm: Double?, unit: DistanceUnit): String {
    val unitWord = unitWord(unit)
    if (secPerKm == null || !secPerKm.isFinite() || secPerKm <= 0.0) return "—:—/$unitWord"
    val perUnit = paceSecPerUnit(secPerKm, unit).toLong()
    val mins = perUnit / 60L
    val secs = perUnit % 60L
    return String.format(Locale.ROOT, "%d:%02d/%s", mins, secs, unitWord)
}

private fun unitWord(unit: DistanceUnit): String = when (unit) {
    DistanceUnit.KM -> "km"
    DistanceUnit.MI -> "mi"
}

@Suppress("unused") // Reserved for a future per-tile launch action that
                    // routes directly to the running screen vs the idle
                    // screen — kept in the same file as the layouts so
                    // the targeting stays adjacent to the modifier.
private fun launchComponent(context: Context): ComponentName =
    ComponentName(context, MainActivity::class.java)

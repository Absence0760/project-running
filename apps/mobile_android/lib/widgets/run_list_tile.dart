import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../l10n/date_format.dart';
import '../activity_type_labels.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../preferences.dart';
import 'run_track_preview.dart';
import 'track_preview.dart';

/// Single leading-slot width for every variant of the row (track preview,
/// selecting checkbox, or activity-icon fallback). Locking this to one value
/// keeps the title column anchored at the same x-position regardless of which
/// leading the row happens to render — and regardless of which surface it is
/// on: the profile's list had picked 56, so the same run's thumbnail was a
/// different size and a different aspect on two adjacent screens.
const double kRunTileLeadingWidth = 72;

/// The run row, wherever a list of runs is drawn.
///
/// Issue #666 C8: the same run rendered two ways on adjacent surfaces. Fitness
/// -> Runs drew a `Card` + `ListTile` with a 72x40 track thumbnail, a signature-
/// coloured activity icon, a bold `titleMedium` distance, a `date - duration -
/// activity - vert` subtitle and a stacked pace value in the trailing slot;
/// Profile -> Runs drew no card, `Divider(height: 1)` separators, a 56x40
/// thumbnail, an `outline`-grey icon, an unstyled distance, no vert chip and
/// the pace crammed into the subtitle — under a comment claiming it *mirrors*
/// the other one.
///
/// Two named constructors rather than nullable parameters, because the surfaces
/// differ in which fields exist rather than in their values (§509): only the
/// owner's own list has a selection mode, an unsynced marker or an inline
/// track, and only a non-owner view has an owner to clip the thumbnail against.
///
/// Not consolidated here, deliberately: `activity_timeline_list`'s
/// `_ActivityRowTile`. It is not a run row — it renders runs, lifts and meals
/// from the `activities` view's thin `summary` jsonb, which carries no
/// `track_url` for a thumbnail to read, and its tinted avatar is what names the
/// modality. Folding it in would delete the cross-modal axis.
class RunListTile extends StatelessWidget {
  const RunListTile.owned({
    super.key,
    required Run run,
    required this.unit,
    required this.api,
    required this.onTap,
    this.onLongPress,
    this.isUnsynced = false,
    this.selecting = false,
    this.selected = false,
  })  : _run = run,
        _row = null,
        ownerUserId = null;

  /// A run read from someone's profile — possibly not the viewer's. [ownerUserId]
  /// routes the thumbnail through the clipping Edge Function when it differs
  /// from the signed-in viewer, so the owner's privacy zones are honoured.
  const RunListTile.public({
    super.key,
    required RunRow row,
    required this.ownerUserId,
    required this.unit,
    required this.api,
    required this.onTap,
  })  : _row = row,
        _run = null,
        onLongPress = null,
        isUnsynced = false,
        selecting = false,
        selected = false;

  final Run? _run;
  final RunRow? _row;
  final String? ownerUserId;
  final DistanceUnit unit;
  final ApiClient? api;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isUnsynced;
  final bool selecting;
  final bool selected;

  // Every accessor discriminates on WHICH source the row was built from, never
  // on whether a value happens to be null: a run with no metadata is ordinary,
  // and reading the absent source's field as a fallback dereferences null.
  String get _id => _run?.id ?? _row!.id;

  DateTime get _startedAt => _run?.startedAt ?? _row!.startedAt;

  double get _distanceMetres => _run?.distanceMetres ?? _row!.distanceM;

  Duration get _duration =>
      _run?.duration ?? Duration(seconds: _row!.durationS);

  Map<String, dynamic>? get _metadata {
    final run = _run;
    if (run != null) return run.metadata;
    final bag = _row!.metadata;
    return bag is Map<String, dynamic> ? bag : null;
  }

  String? get _activityName =>
      _row?.activityType ?? _metadata?['activity_type'] as String?;

  String? get _trackUrl =>
      _row?.trackUrl ?? _metadata?['track_url'] as String?;

  List<Waypoint> get _inlineTrack => _run?.track ?? const [];

  /// Metres of gain, from the promoted column when there is one and the
  /// metadata bag otherwise. Zero and null both mean "no elevation signal", so
  /// the row does not widen on a flat run.
  double get _vertMetres {
    final raw = _row?.elevationGainM ?? _metadata?['elevation_m'];
    return (raw is num && raw > 0) ? raw.toDouble() : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));

    final dist = UnitFormat.distance(_distanceMetres, unit);
    final dur = formatShortDuration(_duration);
    final paceSecPerKm = _distanceMetres < 10
        ? null
        : _duration.inSeconds / (_distanceMetres / 1000);
    final activity = ActivityType.fromName(_activityName);
    final trailingMetric = activity.usesSpeed
        ? '${UnitFormat.speed(paceSecPerKm, unit)} ${UnitFormat.speedLabel(unit)}'
        : '${UnitFormat.pace(paceSecPerKm, unit)} ${UnitFormat.paceLabel(unit)}';
    final date = formatDateShort(_startedAt, tag);
    final vertMetres = _vertMetres;
    final vertLabel = vertMetres > 0
        ? '  ·  ${UnitFormat.elevation(vertMetres, unit)} ↑'
        : '';

    final trackUrl = _trackUrl;
    final hasInlineTrack = _inlineTrack.length >= 2;
    final leading = SizedBox(
      width: kRunTileLeadingWidth,
      height: 40,
      child: Center(
        child: selecting
            ? Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              )
            : hasInlineTrack
                ? TrackPreview(points: _inlineTrack)
                : (trackUrl != null && api != null)
                    ? RunTrackPreview(
                        runId: _id,
                        trackUrl: trackUrl,
                        api: api!,
                        ownerUserId: ownerUserId,
                      )
                    : CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(activity.icon,
                            color: theme.colorScheme.primary),
                      ),
      ),
    );

    final semanticsLabel = [
      '$dist ${activityTypeLabel(l10n, activity).toLowerCase()}',
      date,
      dur,
      trailingMetric,
      if (vertMetres > 0)
        '${UnitFormat.elevation(vertMetres, unit)} elevation gain',
      if (isUnsynced) 'not yet synced',
    ].join(', ');

    // The trailing metric is "{value} {unit}" — pivot on the last space so the
    // numeric reads as the hero and the unit as supporting metadata.
    final lastSpace = trailingMetric.lastIndexOf(' ');
    final trailingValue =
        lastSpace > 0 ? trailingMetric.substring(0, lastSpace) : trailingMetric;
    final trailingUnit =
        lastSpace > 0 ? trailingMetric.substring(lastSpace + 1) : '';

    return Semantics(
      label: semanticsLabel,
      button: true,
      selected: selected,
      child: Card(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
            : null,
        child: ListTile(
          leading: leading,
          title: Row(
            children: [
              Icon(activity.icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                dist,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '$date  ·  $dur  ·  ${activityTypeLabel(l10n, activity).toLowerCase()}$vertLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    trailingValue,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isUnsynced) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: l10n.historyQueuedToSync,
                      child: Icon(
                        Icons.cloud_upload_outlined,
                        size: 16,
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ],
                ],
              ),
              if (trailingUnit.isNotEmpty)
                Text(
                  trailingUnit,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
            ],
          ),
          onTap: onTap,
          onLongPress: onLongPress,
        ),
      ),
    );
  }
}

/// `1h 05m` / `25m 30s` — the compact duration a run row shows beside its date.
String formatShortDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m ${s}s';
}

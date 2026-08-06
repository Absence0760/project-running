import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart';

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';
import '../route_geometry.dart';
import '../route_markers.dart';
import '../route_snap.dart';
import '../undo_queue.dart';
import 'live_run_map.dart';
import 'top_banner.dart';
import 'undo_bar.dart';

/// Course-marker panel for the route-detail screen (Flutter twin of web
/// `RouteMarkerEditor.svelte`). Renders an ordered course-schedule list and
/// an add / edit / delete flow. **Any signed-in viewer** may add their own
/// markers to a route they can see; the route owner's OFFICIAL markers are
/// read-only to a non-owner and badged as the owner's (a marker is official
/// iff `marker.user_id == route.user_id`; anything else is the viewer's own
/// private overlay). A pin drops by tapping the map, by typing lat/lng, or by
/// entering a distance along the route ("mile 5") into the editor sheet — the
/// keyboard / screen-reader placement path, WCAG 2.1.1.
/// The host owns the `LiveRunMap` and forwards map taps via
/// the [GlobalKey]-exposed [RouteMarkersPanelState.placeAt] /
/// [RouteMarkersPanelState.selectMarker]; the panel pushes the rendered pins
/// + placing-mode flag back up through [onPinsChanged] / [onPlacingChanged].
class RouteMarkersPanel extends StatefulWidget {
  final ApiClient? api;
  final String routeId;
  final bool isOwner;

  /// The signed-in viewer's user id (`api.userId`). A marker is editable /
  /// deletable by the viewer iff `marker.userId == viewerId`; null when
  /// signed out (no add / edit affordances).
  final String? viewerId;

  /// The route owner's user id. A marker whose `userId` matches is the
  /// owner's OFFICIAL marker — read-only + badged for a non-owner viewer.
  final String? routeOwnerId;

  /// The route's rendered polyline. A tapped point is projected onto this
  /// line when the "Snap to route line" toggle is on (mirrors web's
  /// `snapToRoute` in `RunMap.svelte`). `position_m` stays server-derived —
  /// this only moves the placed lat/lng onto the course.
  final List<Waypoint> routeLine;

  final ValueChanged<List<MapMarkerPin>> onPinsChanged;
  final ValueChanged<bool> onPlacingChanged;

  /// Test seam: when set, seed the list from here instead of fetching.
  @visibleForTesting
  final List<RouteMarkerRow>? initialMarkers;

  const RouteMarkersPanel({
    super.key,
    required this.api,
    required this.routeId,
    required this.isOwner,
    required this.routeLine,
    required this.onPinsChanged,
    required this.onPlacingChanged,
    this.viewerId,
    this.routeOwnerId,
    this.initialMarkers,
  });

  @override
  State<RouteMarkersPanel> createState() => RouteMarkersPanelState();
}

class RouteMarkersPanelState extends State<RouteMarkersPanel> {
  List<RouteMarkerRow> _markers = const [];
  bool _loaded = false;
  bool _placing = false;
  // True while an add/update round-trip is in flight, so the panel shows a
  // progress bar instead of no feedback until the list refreshes.
  bool _saving = false;
  // Default on: course markers belong on the course (mirrors web's
  // `snapEnabled = true`).
  bool _snapEnabled = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialMarkers != null) {
      _markers = widget.initialMarkers!;
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _publishPins());
    } else {
      _reload();
    }
  }

  Future<void> _reload() async {
    final api = widget.api;
    List<RouteMarkerRow> fetched;
    try {
      fetched =
          api == null ? const [] : await api.fetchRouteMarkers(widget.routeId);
    } catch (e) {
      // L4 auxiliary effect: a course-markers load failure must never break
      // route detail (name / stats / map are the core). Log and show none.
      debugPrint('route markers load failed for ${widget.routeId}: $e');
      fetched = const [];
    }
    final markers = sortMarkerRows(fetched);
    if (!mounted) return;
    setState(() {
      _markers = markers;
      _loaded = true;
    });
    // Defer to after the frame: with a null api this whole method runs
    // synchronously inside initState (no await is reached), so publishing
    // pins directly would call the parent's onPinsChanged -> setState while
    // the parent is still building. Mirrors the initialMarkers path above.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publishPins();
    });
  }

  void _publishPins() {
    widget.onPinsChanged([
      for (final m in _markers)
        MapMarkerPin(
          id: m.id,
          label: m.label,
          color: kindSpec(m.kind).color,
          lat: m.lat,
          lng: m.lng,
        ),
    ]);
  }

  void _setPlacing(bool v) {
    if (_placing == v) return;
    setState(() => _placing = v);
    widget.onPlacingChanged(v);
  }

  /// Called by the host when the map is tapped in placing mode.
  void placeAt(Waypoint wp) {
    if (!_placing) return;
    _setPlacing(false);
    final placed = _maybeSnap(wp);
    _openEditor(lat: placed.lat, lng: placed.lng);
  }

  /// Project a tapped point onto the route line when snapping is on and there
  /// is a line to snap to; otherwise pass it through untouched. Mirrors
  /// `maybeSnap` in web's `RunMap.svelte`.
  ({double lat, double lng}) _maybeSnap(Waypoint wp) {
    if (!_snapEnabled) return (lat: wp.lat, lng: wp.lng);
    final coords = [
      for (final w in widget.routeLine) [w.lng, w.lat],
    ];
    if (coords.length < 2) return (lat: wp.lat, lng: wp.lng);
    final s = snapToPolyline((lng: wp.lng, lat: wp.lat), coords);
    if (s == null) return (lat: wp.lat, lng: wp.lng);
    return (lat: s.lat, lng: s.lng);
  }

  /// A signed-in viewer can add their own markers.
  bool get _canAdd => widget.viewerId != null;

  /// The viewer may edit / delete only markers they own.
  bool _canEditMarker(RouteMarkerRow m) =>
      widget.viewerId != null && m.userId == widget.viewerId;

  /// A marker is OFFICIAL when it belongs to the route owner. Locally-built
  /// routes carry an empty owner id — treat those as having no official set.
  bool _isOfficialMarker(RouteMarkerRow m) =>
      isOfficialMarker(m.userId, widget.routeOwnerId);

  /// Called by the host when a course-marker pin is tapped. Only the viewer's
  /// own markers open the editor; an owner's official marker is read-only.
  ///
  /// While placing, a pin is just another point on the map: the tap places
  /// there rather than opening that marker's editor. The pin's hit box would
  /// otherwise be a dead zone the placement tap can't reach, and opening an
  /// unrelated editor left placing mode stuck on behind it.
  void selectMarker(String id) {
    for (final row in _markers) {
      if (row.id == id) {
        if (_placing) {
          placeAt(Waypoint(lat: row.lat, lng: row.lng));
        } else if (_canEditMarker(row)) {
          _openEditor(existing: row);
        }
        return;
      }
    }
  }

  void _startAdd() {
    _setPlacing(true);
    showTopBanner(context, AppLocalizations.of(context).routeMarkerTapToPlace);
  }

  Future<void> _openEditor({
    RouteMarkerRow? existing,
    double? lat,
    double? lng,
  }) async {
    final result = await showModalBottomSheet<_MarkerDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _MarkerEditorSheet(
        existing: existing,
        lat: lat,
        lng: lng,
        routeLine: widget.routeLine,
      ),
    );
    if (result == null) return;
    final api = widget.api;
    if (api == null) {
      debugPrint('route marker save skipped: api null');
      return;
    }
    if (mounted) setState(() => _saving = true);
    try {
      if (existing != null) {
        await api.updateRouteMarker(
          existing.id,
          kind: result.kind,
          label: result.label,
          lat: result.lat,
          lng: result.lng,
          meta: result.meta,
        );
      } else {
        await api.addRouteMarker(
          routeId: widget.routeId,
          kind: result.kind,
          label: result.label,
          lat: result.lat,
          lng: result.lng,
          meta: result.meta,
        );
      }
      await _reload();
    } catch (e) {
      debugPrint('route marker save failed: $e');
      if (mounted) {
        showTopBanner(
          context,
          AppLocalizations.of(context).routeMarkerSaveFailed(friendlyError(AppLocalizations.of(context), e)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// One pin, no children — and its `position_m` is derived server-side, which
  /// survives precisely BECAUSE the deferred delete never touches the row: a
  /// compensating re-insert would have had to re-derive it (decisions § 514).
  void _delete(RouteMarkerRow row) {
    final api = widget.api;
    if (api == null) return;
    final l10n = AppLocalizations.of(context);
    final snapshot = _markers;
    setState(() => _markers =
        _markers.where((m) => m.id != row.id).toList(growable: false));
    deferDestructive(
      context,
      DeferredDestruction(
        message: l10n.routeMarkerRemoved,
        commit: () => api.deleteRouteMarker(row.id),
        restore: () {
          if (!mounted) return;
          setState(() => _markers = snapshot);
        },
        onCommitError: (e) {
          debugPrint('route marker delete failed: $e');
          if (!mounted) return;
          showTopBanner(
              context, l10n.routeMarkerDeleteFailed(friendlyError(l10n, e)));
        },
      ),
    );
  }

  String _kindLabel(AppLocalizations l10n, String kind) {
    switch (kind) {
      case 'aid_station':
        return l10n.routeMarkerKindAidStation;
      case 'cutoff':
        return l10n.routeMarkerKindCutoff;
      case 'crew_access':
        return l10n.routeMarkerKindCrewAccess;
      case 'hazard':
        return l10n.routeMarkerKindHazard;
      case 'note':
        return l10n.routeMarkerKindNote;
      case 'climb':
        return l10n.routeMarkerKindClimb;
      default:
        return l10n.routeMarkerKindCustom;
    }
  }

  String _detailLine(AppLocalizations l10n, RouteMarkerRow m) {
    final meta = m.meta;
    final spec = kindSpec(m.kind);
    final parts = <String>[];
    if (spec.hasServices && meta is Map && meta['services'] is List) {
      // whereType, not cast: meta is a schemaless jsonb bag, and a cast that
      // throws mid-build takes the whole route-detail list down with it (L4
      // breaking L1) over one malformed marker.
      final services = (meta['services'] as List).whereType<String>().toList();
      if (services.isNotEmpty) {
        parts.add(services.map((s) => serviceLabel(l10n, s)).join(' · '));
      }
    } else if (spec.hasCutoff) {
      final cutoff = parseCutoff(meta);
      // Either form is authorable, so show whichever is set — the elapsed one
      // wins, matching the roadbook's own preference.
      if (cutoff?.elapsedS != null) {
        parts.add(
            l10n.routeMarkerCutoffAt(formatMarkerElapsed(cutoff!.elapsedS!)));
      } else if (cutoff?.clock != null) {
        parts.add(l10n.routeMarkerCutoffAt(cutoff!.clock!));
      }
    } else if (meta is Map && meta['note'] is String) {
      parts.add(meta['note'] as String);
    }
    final target = parseTarget(meta);
    if (target?.elapsedS != null) {
      parts.add(
          l10n.routeMarkerTargetChip(formatMarkerElapsed(target!.elapsedS!)));
    } else if (target?.clock != null) {
      parts.add(l10n.routeMarkerTargetChip(target!.clock!));
    }
    return parts.join(' · ');
  }

  static String serviceLabel(AppLocalizations l10n, String s) {
    switch (s) {
      case 'water':
        return l10n.routeMarkerServiceWater;
      case 'food':
        return l10n.routeMarkerServiceFood;
      case 'medical':
        return l10n.routeMarkerServiceMedical;
      case 'toilets':
        return l10n.routeMarkerServiceToilets;
      case 'drop_bag':
        return l10n.routeMarkerServiceDropBag;
      default:
        return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l10n.routeMarkerHeading,
                  style: theme.textTheme.titleMedium),
            ),
            if (_canAdd && !_placing)
              TextButton.icon(
                onPressed: _startAdd,
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: Text(l10n.routeMarkerAdd),
              ),
          ],
        ),
        if (_saving)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: ProgressBar(value: null),
          ),
        if (_placing) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(l10n.routeMarkerTapToPlace,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary)),
          ),
          InkWell(
            onTap: () => setState(() => _snapEnabled = !_snapEnabled),
            child: Row(
              children: [
                Checkbox(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  value: _snapEnabled,
                  onChanged: (v) =>
                      setState(() => _snapEnabled = v ?? _snapEnabled),
                ),
                Expanded(
                  child: Text(l10n.routeMarkerSnapToggle,
                      style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: () {
                  _setPlacing(false);
                  _openEditor();
                },
                icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                label: Text(l10n.routeMarkerEnterCoords),
              ),
              // Without this, starting a placement is one-way: the Add button
              // hides while placing, so a viewer who changes their mind is
              // left with a map that eats every tap.
              TextButton(
                onPressed: () => _setPlacing(false),
                child: Text(l10n.routeMarkerCancel),
              ),
            ],
          ),
        ],
        if (_loaded && _markers.isEmpty && !_placing)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l10n.routeMarkerEmpty,
                style: theme.textTheme.bodySmall),
          ),
        for (final m in _markers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 4, right: 10),
                  decoration: BoxDecoration(
                    color: _hexColor(kindSpec(m.kind).color),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(m.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                ),
                                if (_isOfficialMarker(m) && !_canEditMarker(m))
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                        start: 6),
                                    child: _OfficialBadge(
                                        label: l10n.routeMarkerOfficialBadge),
                                  ),
                              ],
                            ),
                          ),
                          if (m.positionM != null)
                            Text(_distanceLabel(m.positionM!),
                                style: theme.textTheme.bodySmall),
                        ],
                      ),
                      Text(
                        [
                          _kindLabel(l10n, m.kind),
                          if (_detailLine(l10n, m).isNotEmpty)
                            _detailLine(l10n, m)
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (_canEditMarker(m)) ...[
                  IconButton(
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    tooltip: l10n.routeMarkerEdit,
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () => _openEditor(existing: m),
                  ),
                  IconButton(
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    tooltip: l10n.routeMarkerDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _delete(m),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  String _distanceLabel(double metres) {
    // Compact "X.X km" / "X.X mi" in the viewer's unit preference.
    final unit = activeDistanceUnit;
    final value = unit == DistanceUnit.mi
        ? metres / kMetresPerMile
        : metres / 1000;
    return '${value.toStringAsFixed(1)} ${UnitFormat.distanceLabel(unit)}';
  }
}

/// Small pill flagging a marker as the route owner's official one, shown to a
/// non-owner viewer (their own overlay markers carry no badge).
class _OfficialBadge extends StatelessWidget {
  final String label;
  const _OfficialBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
      ),
    );
  }
}

Color _hexColor(String hex) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  if (v == null) return const Color(0xFF6B7280);
  return Color(0xFF000000 | v);
}

/// Adapts a `RouteMarkerRow` to the twin helper's [MarkerLike] interface.
/// `route_markers.dart` stays free of a `core_models` dependency, and Dart
/// has no structural typing, so the row can't satisfy it directly.
class _SortableMarker implements MarkerLike {
  final RouteMarkerRow row;
  const _SortableMarker(this.row);

  @override
  double? get positionM => row.positionM;

  @override
  DateTime get createdAt => row.createdAt;
}

/// Course-schedule order for a fetched page of rows, delegating to the
/// `route_markers` twin's [sortMarkers] rather than repeating its comparator
/// — a change to the shared ordering rule has to reach this list too.
/// Returns a fresh growable list: `fetchRouteMarkers` hands back an
/// unmodifiable `const []` on its empty / error paths.
List<RouteMarkerRow> sortMarkerRows(List<RouteMarkerRow> rows) => [
      for (final s in sortMarkers([for (final r in rows) _SortableMarker(r)]))
        s.row,
    ];

double? parseMarkerCoordinate(String text, double max) {
  final v = double.tryParse(text.trim());
  if (v == null || v.isNaN || v.abs() > max) return null;
  return v;
}

String formatMarkerCoordinate(double v) {
  return v
      .toStringAsFixed(6)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// Parse a "distance along the route" the user typed (in [unit]) into metres.
/// Returns null for non-numeric / non-finite / negative input. Does NOT clamp
/// to the route length — that happens in [markerPointAtDistance] via the
/// fraction clamp, so callers get a valid on-route point for an over-long
/// value rather than a rejection.
double? parseDistanceAlong(String text, {required DistanceUnit unit}) {
  final v = double.tryParse(text.trim());
  if (v == null || !v.isFinite || v < 0) return null;
  return unit == DistanceUnit.mi ? v * kMetresPerMile : v * 1000;
}

/// "h:mm:ss" / "mm:ss" / bare minutes → elapsed seconds; null = invalid.
/// Mirrors the web editor's parseElapsedText so the two editors accept
/// the same inputs. A two-part value reads as mm:ss unless the marker's
/// position along the route makes the h:mm reading the plausible one
/// (150–1500 s/km implied pace) — an 80 km aid station's "4:30" is
/// 4 h 30, not 4½ minutes.
int? parseMarkerElapsed(String raw, {double? positionM}) {
  final parts = raw.trim().split(':');
  if (parts.isEmpty || parts.length > 3) return null;
  final nums = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p.trim());
    if (n == null || n < 0) return null;
    nums.add(n);
  }
  switch (nums.length) {
    case 1:
      return nums[0] > 0 ? nums[0] * 60 : null;
    case 3:
      final s = nums[0] * 3600 + nums[1] * 60 + nums[2];
      return s > 0 ? s : null;
    default:
      final asHours = nums[0] * 3600 + nums[1] * 60;
      final asMinutes = nums[0] * 60 + nums[1];
      if (positionM != null && positionM > 0 && asHours > 0) {
        final pace = asHours / (positionM / 1000);
        if (pace >= 150 && pace <= 1500) return asHours;
      }
      return asMinutes > 0 ? asMinutes : null;
  }
}

String formatMarkerElapsed(int s) {
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

/// Live-format raw digit entry into an elapsed `h:mm:ss` / `m:ss` string so a
/// marker target time can be typed on a numeric keyboard that offers no `:`
/// separator (the datetime keyboard hides it on many Android IMEs). Digits
/// fill from the right — seconds, then minutes, then hours — and the value
/// always carries at least `m:ss`, so [parseMarkerElapsed] reads it back the
/// same way it round-trips [formatMarkerElapsed] output.
String formatElapsedDigits(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  if (digits.length > 6) digits = digits.substring(digits.length - 6);
  final padded = digits.padLeft(3, '0');
  final sec = padded.substring(padded.length - 2);
  final rest = padded.substring(0, padded.length - 2);
  if (rest.length <= 2) {
    // Drop a leading zero on the minutes ('04' → '4') but keep a lone '0'.
    final min = rest.length == 2 && rest.startsWith('0') ? rest.substring(1) : rest;
    return '$min:$sec';
  }
  final min = rest.substring(rest.length - 2);
  final hrs = rest.substring(0, rest.length - 2);
  return '$hrs:$min:$sec';
}

/// Live-format raw digit entry into a 24-hour `HH:MM` clock for a marker
/// cut-off, so it too can be typed without a `:` key. Digits fill from the
/// left (hours first).
String formatClockDigits(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  // A leading digit above 2 cannot start a 24-hour hour, so it is the hour's
  // ones place — pad it. Without this the natural "930" for 09:30 masks to
  // "93:0", which every reader's parseCutoff then rejects.
  if (digits.codeUnitAt(0) > '2'.codeUnitAt(0)) digits = '0$digits';
  if (digits.length > 4) digits = digits.substring(digits.length - 4);
  if (digits.length <= 2) return digits;
  return '${digits.substring(0, 2)}:${digits.substring(2)}';
}

/// Whether [clock] is a cut-off the readers will accept. Asks [parseCutoff]
/// rather than re-deriving the rule, so the editor can never write a clock
/// string the course-schedule list, roadbook, GPX export, and live cut-off
/// ETA all silently drop.
bool isValidMarkerClock(String clock) =>
    parseCutoff({'cutoff_clock': clock})?.clock != null;

/// A [TextInputFormatter] that live-formats digit entry through [format]
/// (e.g. [formatElapsedDigits] / [formatClockDigits]) and pins the caret at
/// the end, so a time field auto-inserts its `:` separators as the user types
/// digits — no separator key required.
class _MaskedTimeFormatter extends TextInputFormatter {
  final String Function(String) format;
  const _MaskedTimeFormatter(this.format);

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = format(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Clock-vs-elapsed selector for a marker time field. Both `meta` time
/// concepts accept either form, so one field plus this beats four fields.
class _TimeModeToggle extends StatelessWidget {
  final bool elapsed;
  final String clockLabel;
  final String elapsedLabel;
  final ValueChanged<bool> onChanged;
  const _TimeModeToggle({
    required this.elapsed,
    required this.clockLabel,
    required this.elapsedLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ChoiceChipRow<bool>(
        options: [
          ChoiceChipOption(value: false, label: clockLabel),
          ChoiceChipOption(value: true, label: elapsedLabel),
        ],
        selected: elapsed,
        onChanged: onChanged,
      ),
    );
  }
}

class _MarkerDraft {
  final String kind;
  final String label;
  final double lat;
  final double lng;
  final Map<String, dynamic> meta;
  _MarkerDraft(this.kind, this.label, this.lat, this.lng, this.meta);
}

class _MarkerEditorSheet extends StatefulWidget {
  final RouteMarkerRow? existing;
  final double? lat;
  final double? lng;
  final List<Waypoint> routeLine;
  const _MarkerEditorSheet({
    this.existing,
    this.lat,
    this.lng,
    this.routeLine = const [],
  });

  @override
  State<_MarkerEditorSheet> createState() => _MarkerEditorSheetState();
}

class _MarkerEditorSheetState extends State<_MarkerEditorSheet> {
  late String _kind;
  late TextEditingController _label;
  late TextEditingController _note;
  late TextEditingController _cutoff;
  late TextEditingController _target;
  late TextEditingController _lat;
  late TextEditingController _lng;
  late TextEditingController _distanceAlong;
  Set<String> _services = {};
  // Each of the two time concepts stores EITHER a wall clock or an
  // elapsed-from-start value — `parseCutoff` / `parseTarget` read both, and
  // the roadbook prefers the elapsed form. One field per concept with a mode
  // toggle beats four fields, and writing only the selected form keeps the
  // two alternatives from disagreeing.
  bool _cutoffElapsed = false;
  bool _targetClock = false;

  /// The distance-along-route input needs a line with real geometry.
  bool get _canPlaceByDistance => widget.routeLine.length >= 2;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _kind = e?.kind ?? 'aid_station';
    _label = TextEditingController(text: e?.label ?? '');
    _note = TextEditingController(
        text: (e?.meta is Map && (e!.meta as Map)['note'] is String)
            ? (e.meta as Map)['note'] as String
            : '');
    if (e?.meta is Map && (e!.meta as Map)['services'] is List) {
      _services =
          ((e.meta as Map)['services'] as List).whereType<String>().toSet();
    }
    final cutoff = parseCutoff(e?.meta);
    // An existing elapsed value selects that mode, so opening a marker shows
    // the form it was actually saved in.
    _cutoffElapsed = cutoff?.elapsedS != null;
    _cutoff = TextEditingController(
        text: _cutoffElapsed
            ? formatMarkerElapsed(cutoff!.elapsedS!)
            : (cutoff?.clock ?? ''));
    final target = parseTarget(e?.meta);
    _targetClock = target?.elapsedS == null && target?.clock != null;
    _target = TextEditingController(
        text: _targetClock
            ? target!.clock!
            : (target?.elapsedS == null
                ? ''
                : formatMarkerElapsed(target!.elapsedS!)));
    final lat = widget.lat ?? e?.lat;
    final lng = widget.lng ?? e?.lng;
    _lat = TextEditingController(
        text: lat == null ? '' : formatMarkerCoordinate(lat));
    _lng = TextEditingController(
        text: lng == null ? '' : formatMarkerCoordinate(lng));
    // Left empty by design — it is an alternative INPUT to lat/lng, not a
    // mirror of the current position, so an edit that only touches lat/lng
    // isn't silently overridden by a pre-filled distance on save.
    _distanceAlong = TextEditingController();
  }

  @override
  void dispose() {
    _label.dispose();
    _note.dispose();
    _cutoff.dispose();
    _target.dispose();
    _lat.dispose();
    _lng.dispose();
    _distanceAlong.dispose();
    super.dispose();
  }

  String _kindLabel(AppLocalizations l10n, String kind) {
    switch (kind) {
      case 'aid_station':
        return l10n.routeMarkerKindAidStation;
      case 'cutoff':
        return l10n.routeMarkerKindCutoff;
      case 'crew_access':
        return l10n.routeMarkerKindCrewAccess;
      case 'hazard':
        return l10n.routeMarkerKindHazard;
      case 'note':
        return l10n.routeMarkerKindNote;
      case 'climb':
        return l10n.routeMarkerKindClimb;
      default:
        return l10n.routeMarkerKindCustom;
    }
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    if (_label.text.trim().isEmpty) {
      showTopBanner(context, l10n.routeMarkerLabelRequired);
      return;
    }
    // A typed "distance along route" takes precedence over lat/lng: the user
    // is placing "mile 5" rather than a coordinate. Empty → fall through to
    // the map-tap / typed-coordinate path so both stay working.
    final double lat;
    final double lng;
    // How far into the route the marker sits decides the h:mm-vs-mm:ss
    // reading of a two-part target time. A marker placed by distance already
    // knows that, ahead of the server deriving position_m — without it an
    // 80 km aid station's "4:30" saves as 4½ minutes on the first save.
    double? positionM = widget.existing?.positionM;
    final distText = _distanceAlong.text.trim();
    if (distText.isNotEmpty) {
      final metres = parseDistanceAlong(distText, unit: activeDistanceUnit);
      final wp =
          metres == null ? null : markerPointAtDistance(widget.routeLine, metres);
      if (wp == null) {
        showTopBanner(context, l10n.routeMarkerDistanceInvalid);
        return;
      }
      lat = wp.lat;
      lng = wp.lng;
      positionM = metres;
    } else {
      final typedLat = parseMarkerCoordinate(_lat.text, 90);
      final typedLng = parseMarkerCoordinate(_lng.text, 180);
      if (typedLat == null || typedLng == null) {
        showTopBanner(
            context,
            _lat.text.trim().isEmpty && _lng.text.trim().isEmpty
                ? l10n.routeMarkerPlaceRequired
                : l10n.routeMarkerCoordInvalid);
        return;
      }
      lat = typedLat;
      lng = typedLng;
    }
    final spec = kindSpec(_kind);
    // Start from the marker's existing bag rather than a blank one: the sheet
    // owns four keys, but `meta` is a schemaless registry that also holds
    // `cutoff_elapsed_s` and `target_clock` (no input on either platform) and
    // whatever a later version adds. Rebuilding from scratch silently deleted
    // all of them on any edit. Each owned key is explicitly set or removed
    // below, so switching kind still drops the fields that kind can't carry.
    final existing = widget.existing?.meta;
    final meta = <String, dynamic>{
      if (existing is Map) ...existing.cast<String, dynamic>(),
    };
    if (spec.hasServices && _services.isNotEmpty) {
      meta['services'] = _services.toList();
    } else {
      meta.remove('services');
    }
    if (spec.hasCutoff) {
      final raw = _cutoff.text.trim();
      // The two forms are alternatives, so the unselected one is cleared —
      // leaving both would let them disagree, and the roadbook silently
      // prefers the elapsed one.
      meta.remove(_cutoffElapsed ? 'cutoff_clock' : 'cutoff_elapsed_s');
      if (raw.isEmpty) {
        meta.remove(_cutoffElapsed ? 'cutoff_elapsed_s' : 'cutoff_clock');
      } else if (_cutoffElapsed) {
        final s = parseMarkerElapsed(raw, positionM: positionM);
        if (s == null) {
          showTopBanner(context, l10n.routeMarkerTargetInvalid);
          return;
        }
        meta['cutoff_elapsed_s'] = s;
      } else if (!isValidMarkerClock(raw)) {
        showTopBanner(context, l10n.routeMarkerCutoffInvalid);
        return;
      } else {
        meta['cutoff_clock'] = raw;
      }
    } else {
      // Not a cutoff kind any more — the whole cutoff concept goes, including
      // the elapsed form the sheet can't edit.
      meta.remove('cutoff_clock');
      meta.remove('cutoff_elapsed_s');
    }
    final targetRaw = _target.text.trim();
    meta.remove(_targetClock ? 'target_elapsed_s' : 'target_clock');
    if (targetRaw.isEmpty) {
      meta.remove(_targetClock ? 'target_clock' : 'target_elapsed_s');
    } else if (_targetClock) {
      if (!isValidMarkerClock(targetRaw)) {
        showTopBanner(context, l10n.routeMarkerCutoffInvalid);
        return;
      }
      meta['target_clock'] = targetRaw;
    } else {
      final targetS = parseMarkerElapsed(targetRaw, positionM: positionM);
      if (targetS == null) {
        showTopBanner(context, l10n.routeMarkerTargetInvalid);
        return;
      }
      meta['target_elapsed_s'] = targetS;
    }
    if ((_kind == 'note' || _kind == 'hazard') && _note.text.trim().isNotEmpty) {
      meta['note'] = _note.text.trim();
    } else {
      meta.remove('note');
    }
    Navigator.of(context).pop(
        _MarkerDraft(_kind, _label.text.trim(), lat, lng, meta));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spec = kindSpec(_kind);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: InputDecoration(labelText: l10n.routeMarkerKindLabel),
              items: [
                for (final k in routeMarkerKinds)
                  DropdownMenuItem(
                    value: k.kind,
                    child: Text(_kindLabel(l10n, k.kind)),
                  ),
              ],
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: l10n.routeMarkerNameLabel,
                hintText: l10n.routeMarkerNamePlaceholder,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lat,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    decoration: InputDecoration(
                      labelText: l10n.routeMarkerLatLabel,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _lng,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    decoration: InputDecoration(
                      labelText: l10n.routeMarkerLngLabel,
                    ),
                  ),
                ),
              ],
            ),
            if (_canPlaceByDistance) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _distanceAlong,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: InputDecoration(
                  labelText: l10n.routeMarkerDistanceAlongLabel,
                  suffixText: UnitFormat.distanceLabel(activeDistanceUnit),
                ),
              ),
            ],
            if (spec.hasServices) ...[
              const SizedBox(height: 4),
              Text(l10n.routeMarkerServicesLabel,
                  style: Theme.of(context).textTheme.labelLarge),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in aidServices)
                    FilterChip(
                      label: Text(
                          RouteMarkersPanelState.serviceLabel(l10n, s)),
                      selected: _services.contains(s),
                      onSelected: (sel) => setState(() {
                        if (sel) {
                          _services.add(s);
                        } else {
                          _services.remove(s);
                        }
                      }),
                    ),
                ],
              ),
            ],
            if (spec.hasCutoff) ...[
              const SizedBox(height: 12),
              _TimeModeToggle(
                elapsed: _cutoffElapsed,
                clockLabel: l10n.routeMarkerTimeClock,
                elapsedLabel: l10n.routeMarkerTimeElapsed,
                onChanged: (v) => setState(() {
                  _cutoffElapsed = v;
                  // The masks are different shapes; carrying the old digits
                  // across would reinterpret them as a different time.
                  _cutoff.clear();
                }),
              ),
              TextField(
                controller: _cutoff,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  _MaskedTimeFormatter(_cutoffElapsed
                      ? formatElapsedDigits
                      : formatClockDigits)
                ],
                decoration: InputDecoration(
                  labelText: l10n.routeMarkerCutoffLabel,
                  hintText: _cutoffElapsed ? 'h:mm:ss' : 'HH:MM',
                  helperText:
                      _cutoffElapsed ? l10n.routeMarkerTargetHelper : null,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _TimeModeToggle(
              elapsed: !_targetClock,
              clockLabel: l10n.routeMarkerTimeClock,
              elapsedLabel: l10n.routeMarkerTimeElapsed,
              onChanged: (v) => setState(() {
                _targetClock = !v;
                _target.clear();
              }),
            ),
            TextField(
              controller: _target,
              keyboardType: TextInputType.number,
              inputFormatters: [
                _MaskedTimeFormatter(
                    _targetClock ? formatClockDigits : formatElapsedDigits)
              ],
              decoration: InputDecoration(
                labelText: l10n.routeMarkerTargetLabel,
                hintText: _targetClock ? 'HH:MM' : 'h:mm:ss',
                helperText:
                    _targetClock ? null : l10n.routeMarkerTargetHelper,
              ),
            ),
            if (_kind == 'note' || _kind == 'hazard') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLength: 280,
                maxLines: 2,
                decoration: InputDecoration(labelText: l10n.routeMarkerNoteLabel),
              ),
            ],
            const SizedBox(height: 12),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.routeMarkerCancel),
                ),
                FilledButton(
                  onPressed: _save,
                  child: Text(l10n.routeMarkerSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

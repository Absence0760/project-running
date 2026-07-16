import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../route_markers.dart';
import '../route_snap.dart';
import 'live_run_map.dart';
import 'top_banner.dart';

/// Course-marker panel for the route-detail screen (Flutter twin of web
/// `RouteMarkerEditor.svelte`). Renders an ordered course-schedule list and
/// — for the route owner — an add / edit / delete flow that drops a pin by
/// tapping the map or by typing lat/lng into the editor sheet (the
/// keyboard / screen-reader placement path, WCAG 2.1.1).
/// The host owns the `LiveRunMap` and forwards map taps via
/// the [GlobalKey]-exposed [RouteMarkersPanelState.placeAt] /
/// [RouteMarkersPanelState.selectMarker]; the panel pushes the rendered pins
/// + placing-mode flag back up through [onPinsChanged] / [onPlacingChanged].
class RouteMarkersPanel extends StatefulWidget {
  final ApiClient? api;
  final String routeId;
  final bool isOwner;

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
    this.initialMarkers,
  });

  @override
  State<RouteMarkersPanel> createState() => RouteMarkersPanelState();
}

class RouteMarkersPanelState extends State<RouteMarkersPanel> {
  List<RouteMarkerRow> _markers = const [];
  bool _loaded = false;
  bool _placing = false;
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
    // Own a growable copy before sorting: fetchRouteMarkers returns an
    // unmodifiable `const []` on its empty/error paths, and sort() mutates
    // in place — sorting the borrowed list directly throws UnsupportedError.
    final markers = [...fetched];
    markers.sort((a, b) {
      final ap = a.positionM, bp = b.positionM;
      if (ap == null && bp == null) return a.createdAt.compareTo(b.createdAt);
      if (ap == null) return 1;
      if (bp == null) return -1;
      if (ap != bp) return ap.compareTo(bp);
      return a.createdAt.compareTo(b.createdAt);
    });
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

  /// Called by the host when a course-marker pin is tapped.
  void selectMarker(String id) {
    if (!widget.isOwner) return;
    for (final row in _markers) {
      if (row.id == id) {
        _openEditor(existing: row);
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
      builder: (ctx) => _MarkerEditorSheet(existing: existing, lat: lat, lng: lng),
    );
    if (result == null) return;
    final api = widget.api;
    if (api == null) return;
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
    }
  }

  Future<void> _confirmDelete(RouteMarkerRow row) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.routeMarkerDeleteConfirmTitle),
        content: Text(l10n.routeMarkerDeleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.routeMarkerCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.routeMarkerDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final api = widget.api;
    if (api == null) return;
    try {
      await api.deleteRouteMarker(row.id);
      await _reload();
    } catch (e) {
      debugPrint('route marker delete failed: $e');
      if (mounted) {
        showTopBanner(context, l10n.routeMarkerDeleteFailed(friendlyError(l10n, e)));
      }
    }
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
    if (spec.hasServices && meta is Map && meta['services'] is List) {
      final services = (meta['services'] as List).cast<String>();
      if (services.isNotEmpty) {
        return services.map((s) => serviceLabel(l10n, s)).join(' · ');
      }
    }
    if (spec.hasCutoff) {
      final cutoff = parseCutoff(meta);
      if (cutoff?.clock != null) return l10n.routeMarkerCutoffAt(cutoff!.clock!);
    }
    if (meta is Map && meta['note'] is String) return meta['note'] as String;
    return '';
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
            if (widget.isOwner && !_placing)
              TextButton.icon(
                onPressed: _startAdd,
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: Text(l10n.routeMarkerAdd),
              ),
          ],
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
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () {
                _setPlacing(false);
                _openEditor();
              },
              icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
              label: Text(l10n.routeMarkerEnterCoords),
            ),
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
                            child: Text(m.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
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
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (widget.isOwner) ...[
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: l10n.routeMarkerEdit,
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () => _openEditor(existing: m),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: l10n.routeMarkerDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _confirmDelete(m),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  String _distanceLabel(double metres) {
    // Display in km with one decimal — the route-detail surface already
    // formats elsewhere; markers show a compact "X.X km".
    return '${(metres / 1000).toStringAsFixed(1)} km';
  }
}

Color _hexColor(String hex) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  if (v == null) return const Color(0xFF6B7280);
  return Color(0xFF000000 | v);
}

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
  const _MarkerEditorSheet({this.existing, this.lat, this.lng});

  @override
  State<_MarkerEditorSheet> createState() => _MarkerEditorSheetState();
}

class _MarkerEditorSheetState extends State<_MarkerEditorSheet> {
  late String _kind;
  late TextEditingController _label;
  late TextEditingController _note;
  late TextEditingController _cutoff;
  late TextEditingController _lat;
  late TextEditingController _lng;
  Set<String> _services = {};

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
      _services = ((e.meta as Map)['services'] as List).cast<String>().toSet();
    }
    final cutoff = parseCutoff(e?.meta);
    _cutoff = TextEditingController(text: cutoff?.clock ?? '');
    final lat = widget.lat ?? e?.lat;
    final lng = widget.lng ?? e?.lng;
    _lat = TextEditingController(
        text: lat == null ? '' : formatMarkerCoordinate(lat));
    _lng = TextEditingController(
        text: lng == null ? '' : formatMarkerCoordinate(lng));
  }

  @override
  void dispose() {
    _label.dispose();
    _note.dispose();
    _cutoff.dispose();
    _lat.dispose();
    _lng.dispose();
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
    final lat = parseMarkerCoordinate(_lat.text, 90);
    final lng = parseMarkerCoordinate(_lng.text, 180);
    if (lat == null || lng == null) {
      showTopBanner(
          context,
          _lat.text.trim().isEmpty && _lng.text.trim().isEmpty
              ? l10n.routeMarkerPlaceRequired
              : l10n.routeMarkerCoordInvalid);
      return;
    }
    final spec = kindSpec(_kind);
    final meta = <String, dynamic>{};
    if (spec.hasServices && _services.isNotEmpty) {
      meta['services'] = _services.toList();
    }
    if (spec.hasCutoff && _cutoff.text.trim().isNotEmpty) {
      meta['cutoff_clock'] = _cutoff.text.trim();
    }
    if ((_kind == 'note' || _kind == 'hazard') && _note.text.trim().isNotEmpty) {
      meta['note'] = _note.text.trim();
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
              TextField(
                controller: _cutoff,
                decoration: InputDecoration(
                  labelText: l10n.routeMarkerCutoffLabel,
                  hintText: 'HH:MM',
                ),
                keyboardType: TextInputType.datetime,
              ),
            ],
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
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.routeMarkerCancel),
                ),
                const SizedBox(width: 8),
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

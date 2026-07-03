import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../elevation.dart';
import '../fuel_plan.dart';
import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';
import '../roadbook.dart';
import '../route_markers.dart' show kindSpec;
import '../widgets/top_banner.dart';

/// Race roadbook — the crew sheet for a route's course markers + a goal time.
/// Flutter twin of the web `/routes/[id]/roadbook` page. Controls (goal /
/// start / pacing model) are screen-local (mobile has no URL to encode them);
/// the schedule + share-as-text mirror the web surface.
class RoadbookScreen extends StatefulWidget {
  final cm.Route route;
  final List<cm.Waypoint> waypoints;
  final ApiClient? api;

  /// Source of the race-fueling carbs/fluid intake rates (mirrored from the
  /// universal settings bag). Null falls back to the documented defaults.
  final Preferences? preferences;

  /// Test seam: seed markers instead of fetching.
  @visibleForTesting
  final List<cm.RouteMarkerRow>? initialMarkers;

  const RoadbookScreen({
    super.key,
    required this.route,
    required this.waypoints,
    required this.api,
    this.preferences,
    this.initialMarkers,
  });

  @override
  State<RoadbookScreen> createState() => _RoadbookScreenState();
}

class _RoadbookScreenState extends State<RoadbookScreen> {
  static const _defaultSecPerKm = 390; // 6:30/km starting point

  List<cm.RouteMarkerRow> _markers = const [];
  List<double>? _fetchedEle;
  bool _fetchingEle = false;
  late int _goalSeconds;
  int? _startClockMin;
  PacingModel _model = PacingModel.effort;
  bool _fueling = false;
  bool _heat = false;
  late final TextEditingController _goal;

  @override
  void initState() {
    super.initState();
    final km = widget.route.distanceMetres / 1000;
    _goalSeconds = (km * _defaultSecPerKm).round().clamp(60, 1 << 30);
    _goal = TextEditingController(text: _fmtElapsed(_goalSeconds.toDouble()));
    if (widget.initialMarkers != null) {
      _markers = widget.initialMarkers!;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _goal.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = widget.api;
    final markers =
        api == null ? <cm.RouteMarkerRow>[] : await api.fetchRouteMarkers(widget.route.id);
    if (!mounted) return;
    setState(() => _markers = markers);
  }

  List<RoadbookWaypoint> get _rbWaypoints {
    return [
      for (var i = 0; i < widget.waypoints.length; i++)
        RoadbookWaypoint(
          lat: widget.waypoints[i].lat,
          lng: widget.waypoints[i].lng,
          ele: widget.waypoints[i].elevationMetres ?? _fetchedEle?[i],
        ),
    ];
  }

  Roadbook get _roadbook => buildRoadbook(
        _rbWaypoints,
        [
          for (final m in _markers)
            RoadbookMarker(
                positionM: m.positionM, kind: m.kind, label: m.label, meta: m.meta),
        ],
        goalSeconds: _goalSeconds.toDouble(),
        startClockMin: _startClockMin?.toDouble(),
        model: _model,
      );

  FuelPlan _fuelPlanFor(Roadbook rb) => buildFuelPlan(
        [
          for (final leg in rb.legs)
            FuelLegInput(
              projectedElapsedS: leg.projectedElapsedS,
              legDistM: leg.legDistM,
              services: leg.services,
            ),
        ],
        carbsPerHourG: widget.preferences?.carbsPerHourG ?? defaultCarbsPerHourG,
        fluidPerHourMl: widget.preferences?.fluidPerHourMl ?? defaultFluidPerHourMl,
        heatFactor: _heat ? heatFluidFactor : 1.0,
      );

  void _onGoalSubmit(String v) {
    final secs = _parseElapsed(v.trim());
    if (secs != null && secs > 0) {
      setState(() => _goalSeconds = secs);
    }
    _goal.text = _fmtElapsed(_goalSeconds.toDouble());
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startClockMin == null
          ? const TimeOfDay(hour: 6, minute: 0)
          : TimeOfDay(hour: _startClockMin! ~/ 60, minute: _startClockMin! % 60),
    );
    if (picked != null) {
      setState(() => _startClockMin = picked.hour * 60 + picked.minute);
    }
  }

  Future<void> _addElevation() async {
    if (_fetchingEle) return;
    setState(() => _fetchingEle = true);
    try {
      // The "Add elevation" tap is the explicit user action that consents
      // to the Open-Meteo lookup (audit/third-party-data-flows).
      final eles = await fetchElevations(widget.waypoints, consented: true);
      if (mounted &&
          eles.length == widget.waypoints.length &&
          eles.any((e) => e != 0)) {
        setState(() => _fetchedEle = eles);
      } else if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).roadbookElevationUnavailable);
      }
    } catch (_) {
      if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).roadbookElevationUnavailable);
      }
    } finally {
      if (mounted) setState(() => _fetchingEle = false);
    }
  }

  void _share() {
    final l10n = AppLocalizations.of(context);
    final unit = activeDistanceUnit;
    final rb = _roadbook;
    final lines = <String>['${widget.route.name} — ${l10n.roadbookTitle}', ''];
    for (final leg in rb.legs) {
      final name = _checkpointLabel(l10n, leg);
      final arrival = _fmtElapsed(leg.projectedElapsedS) +
          (leg.projectedClockMin != null ? ' (${_fmtClock(leg.projectedClockMin!)})' : '');
      final cut = leg.cutoff != null ? '  ⏱ ${_fmtMargin(leg.cutoff!.marginS)}' : '';
      lines.add('${UnitFormat.distance(leg.cumDistM, unit)}  $name  $arrival$cut');
    }
    Share.share(lines.join('\n'));
  }

  String _checkpointLabel(AppLocalizations l10n, RoadbookLeg leg) {
    if (leg.isStart) return l10n.roadbookStart;
    if (leg.isFinish) return l10n.roadbookFinish;
    return leg.label;
  }

  Color _checkpointColor(RoadbookLeg leg) {
    if (leg.isStart) return const Color(0xFF22C55E);
    if (leg.isFinish) return const Color(0xFFEF4444);
    return _hex(kindSpec(leg.kind ?? 'custom').color);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unit = activeDistanceUnit;
    final rb = _roadbook;
    final fuel = _fueling ? _fuelPlanFor(rb) : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.roadbookTitle),
        actions: [
          if (_markers.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: l10n.roadbookShare,
              onPressed: _share,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _goal,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(
                    labelText: l10n.roadbookGoalTime,
                    hintText: '4:30:00',
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: _onGoalSubmit,
                  onTapOutside: (_) => _onGoalSubmit(_goal.text),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _pickStart,
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(_startClockMin == null
                    ? l10n.roadbookStartTime
                    : _fmtClock(_startClockMin!.toDouble())),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<PacingModel>(
            segments: [
              ButtonSegment(value: PacingModel.effort, label: Text(l10n.roadbookEffort)),
              ButtonSegment(value: PacingModel.even, label: Text(l10n.roadbookEven)),
            ],
            selected: {_model},
            onSelectionChanged: (s) => setState(() => _model = s.first),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.roadbookFuel),
                  value: _fueling,
                  onChanged: (v) => setState(() => _fueling = v),
                ),
              ),
              if (_fueling)
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.roadbookHeat),
                    value: _heat,
                    onChanged: (v) => setState(() => _heat = v),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_markers.isEmpty)
            Text(l10n.roadbookNoMarkers, style: theme.textTheme.bodyMedium)
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.roadbookSummary(
                      UnitFormat.distance(rb.totalDistM, unit),
                      formatElevationForPref(rb.totalGainM),
                      _fmtElapsed(rb.totalSeconds),
                    ),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                if (_model == PacingModel.effort && !rb.hasElevation)
                  TextButton(
                    onPressed: _fetchingEle ? null : _addElevation,
                    child: Text(l10n.roadbookAddElevation),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < rb.legs.length; i++)
              _legRow(context, l10n, rb.legs[i], unit, fuel?.legs[i]),
          ],
        ],
      ),
    );
  }

  Widget _legRow(BuildContext context, AppLocalizations l10n, RoadbookLeg leg,
      DistanceUnit unit, FuelLeg? fuelLeg) {
    final theme = Theme.of(context);
    final cutoff = leg.cutoff;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 4, right: 10),
            decoration: BoxDecoration(color: _checkpointColor(leg), shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(_checkpointLabel(l10n, leg),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Text(UnitFormat.distance(leg.cumDistM, unit),
                        style: theme.textTheme.bodySmall),
                  ],
                ),
                Text(
                  [
                    _fmtElapsed(leg.projectedElapsedS),
                    if (leg.projectedClockMin != null) _fmtClock(leg.projectedClockMin!),
                    if (leg.legGainM >= 1) '+${leg.legGainM.round()}m',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                if (cutoff != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _cutoffColor(cutoff.status).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${l10n.routeMarkerKindCutoff} ${_fmtMargin(cutoff.marginS)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: _cutoffColor(cutoff.status)),
                      ),
                    ),
                  ),
                if (leg.services.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      leg.services.map((s) => _serviceLabel(l10n, s)).join(' · '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                if (fuelLeg != null) ..._fuelLines(context, l10n, fuelLeg),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _fuelLines(
      BuildContext context, AppLocalizations l10n, FuelLeg fuelLeg) {
    final theme = Theme.of(context);
    final carry = fuelLeg.carryToNextAid;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          [
            '${l10n.roadbookCarbs}: ${l10n.roadbookCarbsValue(fuelLeg.carbsG.round().toString())}',
            '${l10n.roadbookFluid}: ${l10n.roadbookFluidValue(fuelLeg.fluidMl.round().toString())}',
          ].join(' · '),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.primary),
        ),
      ),
      if (carry != null && (carry.gels > 0 || carry.fluidMl > 0))
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            l10n.roadbookCarryHint(
              carry.gels.toString(),
              carry.fluidMl.round().toString(),
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
    ];
  }

  Color _cutoffColor(CutoffStatus s) => switch (s) {
        CutoffStatus.miss => const Color(0xFFB91C1C),
        CutoffStatus.tight => const Color(0xFFB45309),
        CutoffStatus.safe => const Color(0xFF15803D),
      };

  static String _serviceLabel(AppLocalizations l10n, String s) => switch (s) {
        'water' => l10n.routeMarkerServiceWater,
        'food' => l10n.routeMarkerServiceFood,
        'medical' => l10n.routeMarkerServiceMedical,
        'toilets' => l10n.routeMarkerServiceToilets,
        'drop_bag' => l10n.routeMarkerServiceDropBag,
        _ => s,
      };

  static Color _hex(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return v == null ? const Color(0xFF6B7280) : Color(0xFF000000 | v);
  }

  static String _fmtElapsed(double seconds) {
    final total = seconds.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static String _fmtClock(double minutesPastMidnight) {
    final h = (minutesPastMidnight ~/ 60) % 24;
    final m = (minutesPastMidnight % 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static String _fmtMargin(double seconds) {
    final sign = seconds < 0 ? '−' : '+';
    return '$sign${_fmtElapsed(seconds.abs())}';
  }

  static int? _parseElapsed(String raw) {
    final parts = raw.split(':');
    if (parts.any((p) => int.tryParse(p) == null)) return null;
    final nums = parts.map(int.parse).toList();
    if (nums.length == 3) return nums[0] * 3600 + nums[1] * 60 + nums[2];
    if (nums.length == 2) return nums[0] * 3600 + nums[1] * 60;
    return null;
  }
}

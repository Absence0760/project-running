import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors, ChoiceChipOption, ChoiceChipRow;

import '../elevation.dart';
import '../fuel_plan.dart';
import '../goal_time.dart';
import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';
import '../roadbook.dart';
import '../route_markers.dart' show kindSpec;
import '../widgets/top_banner.dart';

/// The goal pace a schedule opens at before the runner sets their own — 6:30/km.
///
/// Lives here rather than in `roadbook.dart` because that module is a
/// TS↔Dart parity twin and a Dart-only export would put the pair out of
/// lockstep. It seeds a field the runner is asked to confirm; nothing builds a
/// pushed schedule from it unattended (see [RoadbookPlan]).
const int kRoadbookDefaultSecPerKm = 390;

/// Where a route's race plan is kept between visits. Device-local and per
/// route: a plan is one runner's attempt at one course, not a property of the
/// account or of the shared route row.
String roadbookPlanPrefsKey(String routeId) => 'roadbook_plan.$routeId';

/// The three inputs a race schedule cannot be honest without: the goal time it
/// allocates, the wall-clock start a clock-only cut-off is resolved against,
/// and the model that distributes the goal across the course.
///
/// One persisted record because the crew sheet and the custom-watch push both
/// build a schedule from it. A start clock in particular is not a nicety: with
/// none, `buildRoadbook` cannot turn a "barrier closes at 14:00" marker into an
/// elapsed limit, so the cut-off is dropped from the push entirely and a race
/// whose barriers are all wall-clock reaches the wrist with no cut-offs at all.
class RoadbookPlan {
  final int goalSeconds;
  final int? startClockMin;
  final PacingModel model;

  const RoadbookPlan({
    required this.goalSeconds,
    this.startClockMin,
    this.model = PacingModel.effort,
  });
}

/// Read this route's stored plan, or null when there is none to read. Anything
/// unparseable reads as absent so the caller asks rather than schedules a race
/// against a corrupted goal.
Future<RoadbookPlan?> loadRoadbookPlan(String routeId) async {
  String? raw;
  try {
    raw = (await SharedPreferences.getInstance())
        .getString(roadbookPlanPrefsKey(routeId));
  } catch (e) {
    debugPrint('roadbook plan read failed: $e');
    return null;
  }
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final goal = decoded['goal_s'];
    if (goal is! int || goal <= 0) return null;
    final start = decoded['start_min'];
    return RoadbookPlan(
      goalSeconds: goal,
      startClockMin:
          start is int && start >= 0 && start < 1440 ? start : null,
      model: decoded['model'] == 'even' ? PacingModel.even : PacingModel.effort,
    );
  } catch (e) {
    debugPrint('roadbook plan decode failed: $e');
    return null;
  }
}

Future<void> saveRoadbookPlan(String routeId, RoadbookPlan plan) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      roadbookPlanPrefsKey(routeId),
      jsonEncode({
        'goal_s': plan.goalSeconds,
        if (plan.startClockMin != null) 'start_min': plan.startClockMin,
        'model': plan.model == PacingModel.even ? 'even' : 'effort',
      }),
    );
  } catch (e) {
    debugPrint('roadbook plan persist failed: $e');
  }
}

/// Ask for the goal time and race start a schedule has to be built from.
/// Returns null when the runner backs out, and the caller must then send no
/// schedule at all — a canned pace would put arrivals and cut-off verdicts on
/// the wrist that no surface on the phone agrees with.
///
/// The start clock stays optional: a race whose barriers are all elapsed-based
/// needs none, and refusing to proceed without one would block that runner over
/// a field they have no answer for. Skipping it costs exactly the clock-only
/// cut-offs, which the push already counts and discloses.
Future<RoadbookPlan?> showRoadbookPlanSheet(
  BuildContext context, {
  required double distanceMetres,
}) {
  final l10n = AppLocalizations.of(context);
  final seed = (distanceMetres / 1000 * kRoadbookDefaultSecPerKm)
      .round()
      .clamp(60, 1 << 30);
  final goal = TextEditingController(text: _elapsedLabel(seed.toDouble()));
  int? startClockMin;
  String? goalError;
  return showDialog<RoadbookPlan>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocalState) => AlertDialog(
        title: Text(l10n.roadbookPlanTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.roadbookPlanExplain),
            const SizedBox(height: 12),
            TextField(
              controller: goal,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                labelText: l10n.roadbookGoalTime,
                hintText: '4:30:00',
                errorText: goalError,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showTimePicker(
                  context: ctx,
                  initialTime: startClockMin == null
                      ? const TimeOfDay(hour: 6, minute: 0)
                      : TimeOfDay(
                          hour: startClockMin! ~/ 60,
                          minute: startClockMin! % 60),
                );
                if (picked != null) {
                  setLocalState(
                      () => startClockMin = picked.hour * 60 + picked.minute);
                }
              },
              icon: const Icon(Icons.schedule, size: 18),
              label: Text(startClockMin == null
                  ? l10n.roadbookStartTime
                  : _clockLabel(startClockMin!.toDouble())),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.roadbookPlanCancel),
          ),
          FilledButton(
            onPressed: () {
              final secs =
                  parseGoalTimeS(goal.text, distanceM: distanceMetres);
              if (secs == null || secs <= 0) {
                setLocalState(() => goalError = l10n.roadbookPlanGoalInvalid);
                return;
              }
              Navigator.of(ctx).pop(RoadbookPlan(
                goalSeconds: secs,
                startClockMin: startClockMin,
              ));
            },
            child: Text(l10n.roadbookPlanSend),
          ),
        ],
      ),
    ),
  ).whenComplete(goal.dispose);
}

String _elapsedLabel(double seconds) {
  final total = seconds.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

String _clockLabel(double minutesPastMidnight) {
  final h = (minutesPastMidnight ~/ 60) % 24;
  final m = (minutesPastMidnight % 60).round();
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

String _marginLabel(double seconds) {
  final sign = seconds < 0 ? '−' : '+';
  return '$sign${_elapsedLabel(seconds.abs())}';
}

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
  static const _defaultSecPerKm = kRoadbookDefaultSecPerKm;

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
    _goal = TextEditingController(text: _elapsedLabel(_goalSeconds.toDouble()));
    unawaited(_loadPlan());
    if (widget.initialMarkers != null) {
      _markers = widget.initialMarkers!;
    } else {
      _load();
    }
  }

  /// Adopt this route's stored plan, so the sheet opens on the numbers the
  /// runner last set here — the same record the custom-watch push builds its
  /// schedule from.
  Future<void> _loadPlan() async {
    final plan = await loadRoadbookPlan(widget.route.id);
    if (plan == null || !mounted) return;
    setState(() {
      _goalSeconds = plan.goalSeconds;
      _startClockMin = plan.startClockMin;
      _model = plan.model;
      _goal.text = _elapsedLabel(_goalSeconds.toDouble());
    });
  }

  void _persistPlan() {
    unawaited(saveRoadbookPlan(
      widget.route.id,
      RoadbookPlan(
        goalSeconds: _goalSeconds,
        startClockMin: _startClockMin,
        model: _model,
      ),
    ));
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
    final secs =
        parseGoalTimeS(v, distanceM: widget.route.distanceMetres);
    if (secs != null && secs > 0) {
      setState(() => _goalSeconds = secs);
      _persistPlan();
    }
    _goal.text = _elapsedLabel(_goalSeconds.toDouble());
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startClockMin == null
          ? const TimeOfDay(hour: 6, minute: 0)
          : TimeOfDay(hour: _startClockMin! ~/ 60, minute: _startClockMin! % 60),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() => _startClockMin = picked.hour * 60 + picked.minute);
      _persistPlan();
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
    for (var i = 0; i < rb.legs.length; i++) {
      final leg = rb.legs[i];
      final name = _checkpointLabel(l10n, leg);
      final arrival = _elapsedLabel(leg.projectedElapsedS) +
          (leg.projectedClockMin != null ? ' (${_clockLabel(leg.projectedClockMin!)})' : '');
      final cut = leg.cutoff != null ? '  ⏱ ${_marginLabel(leg.cutoff!.marginS)}' : '';
      final tgt = leg.target != null
          ? '  ${l10n.roadbookColTarget} ${_elapsedLabel(leg.target!.targetElapsedS.toDouble())}'
              ' ${_marginLabel(leg.target!.marginS)} ${_targetStatusLabel(l10n, leg.target!.status)}'
          : '';
      final pace =
          '${l10n.roadbookColLegPace} ${_legPace(rb.legs, i, unit)}';
      lines.add(
          '${UnitFormat.distance(leg.cumDistM, unit)}  $name  $pace  $arrival$tgt$cut');
    }
    Share.share(lines.join('\n'));
  }

  /// Seconds the pacing model allocated to the leg arriving at [i]. The start
  /// row has no preceding leg.
  static double _legSeconds(List<RoadbookLeg> legs, int i) =>
      i <= 0 ? 0 : legs[i].projectedElapsedS - legs[i - 1].projectedElapsedS;

  /// The pace this leg has to be run at to hold the goal. Under the effort
  /// model this is the number that differs between a climb and a flat — the
  /// whole point of the model, and invisible from cumulative arrivals alone.
  static String _legPace(List<RoadbookLeg> legs, int i, DistanceUnit unit) {
    final leg = legs[i];
    if (i <= 0 || leg.legDistM <= 0) return '—';
    final secPerKm = _legSeconds(legs, i) / (leg.legDistM / 1000);
    return '${UnitFormat.pace(secPerKm, unit)} ${UnitFormat.paceLabel(unit)}';
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
                    : _clockLabel(_startClockMin!.toDouble())),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ChoiceChipRow<PacingModel>(
            options: [
              ChoiceChipOption(
                  value: PacingModel.effort, label: l10n.roadbookEffort),
              ChoiceChipOption(value: PacingModel.even, label: l10n.roadbookEven),
            ],
            selected: _model,
            onChanged: (v) {
              setState(() => _model = v);
              _persistPlan();
            },
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
                      _elapsedLabel(rb.totalSeconds),
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
              _legRow(context, l10n, rb.legs[i], unit, fuel?.legs[i],
                  _legPace(rb.legs, i, unit)),
          ],
        ],
      ),
    );
  }

  Widget _legRow(BuildContext context, AppLocalizations l10n, RoadbookLeg leg,
      DistanceUnit unit, FuelLeg? fuelLeg, String legPace) {
    final theme = Theme.of(context);
    final cutoff = leg.cutoff;
    final target = leg.target;
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
                    _elapsedLabel(leg.projectedElapsedS),
                    if (leg.projectedClockMin != null) _clockLabel(leg.projectedClockMin!),
                    if (leg.legGainM >= 1) '+${leg.legGainM.round()}m',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                Padding(
                  key: const Key('roadbook-leg-pace'),
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${l10n.roadbookColLegPace} $legPace',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                if (target != null)
                  _verdictChip(
                    context,
                    key: const Key('roadbook-target'),
                    color: _targetColor(
                        AppSemanticColors.of(context), theme, target.status),
                    text: '${l10n.roadbookColTarget} '
                        '${_elapsedLabel(target.targetElapsedS.toDouble())} · '
                        '${_marginLabel(target.marginS)} '
                        '${_targetStatusLabel(l10n, target.status)}',
                  ),
                if (cutoff != null)
                  _verdictChip(
                    context,
                    color: _cutoffColor(
                        AppSemanticColors.of(context), cutoff.status),
                    text:
                        '${l10n.routeMarkerKindCutoff} ${_marginLabel(cutoff.marginS)}',
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

  Widget _verdictChip(BuildContext context,
      {Key? key, required Color color, required String text}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ),
    );
  }

  Color _cutoffColor(AppSemanticColors semantic, CutoffStatus s) =>
      switch (s) {
        CutoffStatus.miss => semantic.danger,
        CutoffStatus.tight => semantic.warning,
        CutoffStatus.safe => semantic.success,
      };

  /// On-plan is deliberately neutral rather than a third alert colour: a
  /// checkpoint inside the band is the schedule working, and colouring it
  /// would leave nothing on the row that reads as "look here".
  Color _targetColor(
          AppSemanticColors semantic, ThemeData theme, TargetStatus s) =>
      switch (s) {
        TargetStatus.behind => semantic.danger,
        TargetStatus.ahead => semantic.success,
        TargetStatus.on => theme.colorScheme.onSurfaceVariant,
      };

  static String _targetStatusLabel(AppLocalizations l10n, TargetStatus s) =>
      switch (s) {
        TargetStatus.ahead => l10n.roadbookTargetAhead,
        TargetStatus.on => l10n.roadbookTargetOn,
        TargetStatus.behind => l10n.roadbookTargetBehind,
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

}

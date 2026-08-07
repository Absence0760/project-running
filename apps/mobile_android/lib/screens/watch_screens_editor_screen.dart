// Dev-only screen: compose the custom watch's runner-authored data screens
// (SCR1, decisions §364) and push the set.
//
// Reached from the sim-watch link screen, which is itself gated to a loopback
// backend — the watch is research-tier (decisions §71, §209), so this is a
// bench tool rather than a product surface.
//
// The editor's whole job is that an invalid set cannot be built. The encoder
// throws on a metric count that disagrees with its layout and on a fifth
// screen; a runner should meet neither as a failed push, so the draft carries
// exactly `layout.slots` metrics at all times and the add affordance stops at
// the cap.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show ChoiceChipOption, ChoiceChipRow, EmptyState, ListSkeleton;

import '../l10n/gen/app_localizations.dart';
import '../reactive_ble_watch_transport.dart';
import '../sim_watch_sync.dart';
import '../watch_screens.dart';
import '../widgets/confirm_destructive.dart';

/// Where the composed set is kept between visits. Device-local: the set is a
/// property of one watch, not of the account.
const String kWatchScreensPrefsKey = 'watch_composed_screens';

String watchMetricLabel(AppLocalizations l10n, WatchMetric m) {
  switch (m) {
    case WatchMetric.elapsed:
      return l10n.watchMetricElapsed;
    case WatchMetric.distance:
      return l10n.watchMetricDistance;
    case WatchMetric.avgPace:
      return l10n.watchMetricAvgPace;
    case WatchMetric.lapElapsed:
      return l10n.watchMetricLapElapsed;
    case WatchMetric.heartRate:
      return l10n.watchMetricHeartRate;
    case WatchMetric.pacerDelta:
      return l10n.watchMetricPacerDelta;
    case WatchMetric.guidedRunRemaining:
      return l10n.watchMetricGuidedRunRemaining;
    case WatchMetric.workoutRemaining:
      return l10n.watchMetricWorkoutRemaining;
    case WatchMetric.racePrediction:
      return l10n.watchMetricRacePrediction;
    case WatchMetric.cutoffMargin:
      return l10n.watchMetricCutoffMargin;
    case WatchMetric.trainingStress:
      return l10n.watchMetricTrainingStress;
    case WatchMetric.roadbookNext:
      return l10n.watchMetricRoadbookNext;
    case WatchMetric.fuelCarbs:
      return l10n.watchMetricFuelCarbs;
    case WatchMetric.gearWear:
      return l10n.watchMetricGearWear;
    case WatchMetric.easyPace:
      return l10n.watchMetricEasyPace;
    case WatchMetric.vo2Max:
      return l10n.watchMetricVo2Max;
    case WatchMetric.altitude:
      return l10n.watchMetricAltitude;
    case WatchMetric.distanceToStart:
      return l10n.watchMetricDistanceToStart;
    case WatchMetric.daylightCountdown:
      return l10n.watchMetricDaylightCountdown;
    case WatchMetric.waypointDistance:
      return l10n.watchMetricWaypointDistance;
    case WatchMetric.climbGain:
      return l10n.watchMetricClimbGain;
    case WatchMetric.recapDistance:
      return l10n.watchMetricRecapDistance;
    case WatchMetric.currentStreak:
      return l10n.watchMetricCurrentStreak;
    case WatchMetric.syncedMovingTime:
      return l10n.watchMetricSyncedMovingTime;
    case WatchMetric.prAge:
      return l10n.watchMetricPrAge;
    case WatchMetric.planReplanChanges:
      return l10n.watchMetricPlanReplanChanges;
    case WatchMetric.planAdaptiveChanges:
      return l10n.watchMetricPlanAdaptiveChanges;
    case WatchMetric.readinessScore:
      return l10n.watchMetricReadinessScore;
    case WatchMetric.goalPercent:
      return l10n.watchMetricGoalPercent;
    case WatchMetric.turnCueDistance:
      return l10n.watchMetricTurnCueDistance;
    case WatchMetric.routeSimplifyDistance:
      return l10n.watchMetricRouteSimplifyDistance;
    case WatchMetric.autoEffortMatched:
      return l10n.watchMetricAutoEffortMatched;
    case WatchMetric.routeElevTotal:
      return l10n.watchMetricRouteElevTotal;
    case WatchMetric.raceDayDays:
      return l10n.watchMetricRaceDayDays;
    case WatchMetric.sleepBudget:
      return l10n.watchMetricSleepBudget;
    case WatchMetric.timerRemaining:
      return l10n.watchMetricTimerRemaining;
    case WatchMetric.backyardBell:
      return l10n.watchMetricBackyardBell;
    case WatchMetric.stormDelta:
      return l10n.watchMetricStormDelta;
    case WatchMetric.gap:
      return l10n.watchMetricGap;
    case WatchMetric.fluid:
      return l10n.watchMetricFluid;
  }
}

String watchLayoutLabel(AppLocalizations l10n, WatchLayout layout) {
  switch (layout) {
    case WatchLayout.single:
      return l10n.watchLayoutSingle;
    case WatchLayout.duo:
      return l10n.watchLayoutDuo;
    case WatchLayout.trio:
      return l10n.watchLayoutTrio;
  }
}

/// Serialise a composed set for [kWatchScreensPrefsKey].
///
/// Keyed by `wireName` rather than enum index: the names are the stable
/// cross-platform identifiers the firmware pins, so reordering either enum
/// for tidiness cannot silently re-point a saved screen.
String encodeWatchScreenDraft(List<WatchScreen> screens) => jsonEncode([
      for (final s in screens)
        {
          'layout': s.layout.wireName,
          'metrics': [for (final m in s.metrics) m.wireName],
        },
    ]);

/// The inverse, or null for anything that is not exactly a valid set.
///
/// Whole-set fail-closed, mirroring the firmware's own decode rule: a screen
/// restored with one slot quietly dropped would read as a screen the runner
/// composed, and there is nothing in the editor to say otherwise.
List<WatchScreen>? decodeWatchScreenDraft(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! List || decoded.length > kMaxWatchScreens) return null;
  final out = <WatchScreen>[];
  for (final entry in decoded) {
    if (entry is! Map) return null;
    final layout = _layoutByWireName(entry['layout']);
    final rawMetrics = entry['metrics'];
    if (layout == null || rawMetrics is! List) return null;
    final metrics = <WatchMetric>[];
    for (final name in rawMetrics) {
      final metric = _metricByWireName(name);
      if (metric == null) return null;
      metrics.add(metric);
    }
    if (metrics.length != layout.slots) return null;
    out.add(WatchScreen(layout, metrics));
  }
  return out;
}

WatchLayout? _layoutByWireName(Object? name) {
  for (final l in WatchLayout.values) {
    if (l.wireName == name) return l;
  }
  return null;
}

WatchMetric? _metricByWireName(Object? name) {
  for (final m in WatchMetric.values) {
    if (m.wireName == name) return m;
  }
  return null;
}

enum _Phase { loading, ready, unreadable }

class _Draft {
  _Draft(this.layout, this.metrics);

  WatchLayout layout;

  /// Always exactly [layout].slots long — the invariant that makes the
  /// encoder's arity [ArgumentError] unreachable from this screen.
  List<WatchMetric> metrics;
}

class WatchScreensEditorScreen extends StatefulWidget {
  /// Injectable so a widget test can drive the push with a fake BLE
  /// transport (the real one needs a paired watch + a SoftDevice radio).
  final WatchBleTransport Function() transportFactory;

  const WatchScreensEditorScreen({
    super.key,
    this.transportFactory = _defaultTransportFactory,
  });

  static WatchBleTransport _defaultTransportFactory() =>
      ReactiveBleWatchTransport();

  @override
  State<WatchScreensEditorScreen> createState() =>
      _WatchScreensEditorScreenState();
}

class _WatchScreensEditorScreenState extends State<WatchScreensEditorScreen> {
  _Phase _phase = _Phase.loading;
  List<_Draft> _drafts = [];
  bool _pushing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    String? raw;
    try {
      raw = (await SharedPreferences.getInstance())
          .getString(kWatchScreensPrefsKey);
    } catch (e) {
      debugPrint('watch screens read failed: $e');
      if (!mounted) return;
      setState(() => _phase = _Phase.unreadable);
      return;
    }
    if (!mounted) return;
    if (raw == null) {
      setState(() {
        _drafts = [];
        _phase = _Phase.ready;
      });
      return;
    }
    final restored = decodeWatchScreenDraft(raw);
    setState(() {
      if (restored == null) {
        _phase = _Phase.unreadable;
      } else {
        _drafts = [
          for (final s in restored) _Draft(s.layout, List.of(s.metrics)),
        ];
        _phase = _Phase.ready;
      }
    });
  }

  List<WatchScreen> _screens() => [
        for (final d in _drafts) WatchScreen(d.layout, List.of(d.metrics)),
      ];

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          kWatchScreensPrefsKey, encodeWatchScreenDraft(_screens()));
    } catch (e) {
      debugPrint('watch screens persist failed: $e');
    }
  }

  /// The first catalogue metric this screen is not already showing, so a
  /// widened layout seeds a distinct slot rather than a second copy.
  WatchMetric _seedMetric(List<WatchMetric> taken) => WatchMetric.values
      .firstWhere((m) => !taken.contains(m), orElse: () => WatchMetric.elapsed);

  void _addScreen() {
    if (_drafts.length >= kMaxWatchScreens) return;
    setState(() =>
        _drafts.add(_Draft(WatchLayout.single, [WatchMetric.elapsed])));
    unawaited(_persist());
  }

  Future<void> _removeScreen(int index) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmDestructive(
      context,
      title: l10n.watchScreensRemoveTitle(index + 1),
      body: l10n.watchScreensRemoveBody(_drafts[index].metrics.length),
      confirmLabel: l10n.watchScreensRemoveConfirm,
      cancelLabel: l10n.watchScreensCancel,
    );
    if (!confirmed || !mounted) return;
    setState(() => _drafts.removeAt(index));
    unawaited(_persist());
  }

  Future<void> _changeLayout(int index, WatchLayout next) async {
    final draft = _drafts[index];
    if (draft.layout == next) return;
    if (next.slots < draft.metrics.length) {
      final l10n = AppLocalizations.of(context);
      final dropped = draft.metrics.sublist(next.slots);
      final confirmed = await confirmDestructive(
        context,
        title: l10n.watchScreensShrinkTitle(dropped.length),
        body: l10n.watchScreensShrinkBody(
          watchLayoutLabel(l10n, next),
          next.slots,
          dropped.map((m) => watchMetricLabel(l10n, m)).join(', '),
        ),
        confirmLabel: l10n.watchScreensShrinkConfirm,
        cancelLabel: l10n.watchScreensCancel,
      );
      if (!confirmed || !mounted) return;
      setState(() {
        draft.layout = next;
        draft.metrics = draft.metrics.sublist(0, next.slots);
      });
    } else {
      setState(() {
        draft.layout = next;
        while (draft.metrics.length < next.slots) {
          draft.metrics.add(_seedMetric(draft.metrics));
        }
      });
    }
    unawaited(_persist());
  }

  void _setMetric(int index, int slot, WatchMetric metric) {
    setState(() => _drafts[index].metrics[slot] = metric);
    unawaited(_persist());
  }

  void _moveSlot(int index, int slot, int delta) {
    final metrics = _drafts[index].metrics;
    final target = slot + delta;
    if (target < 0 || target >= metrics.length) return;
    setState(() {
      final moved = metrics.removeAt(slot);
      metrics.insert(target, moved);
    });
    unawaited(_persist());
  }

  Future<void> _startOver() async {
    try {
      await (await SharedPreferences.getInstance())
          .remove(kWatchScreensPrefsKey);
    } catch (e) {
      debugPrint('watch screens reset failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _drafts = [];
      _phase = _Phase.ready;
    });
  }

  Future<void> _push() async {
    if (_pushing) return;
    final l10n = AppLocalizations.of(context);
    final screens = _screens();
    setState(() {
      _pushing = true;
      _message = null;
    });
    try {
      final client = WatchSyncClient(
        transport: widget.transportFactory(),
        // A screens push never pulls a run, so nothing reaches this sink.
        onRun: (_) async {},
      );
      await client.pushScreens(encodeWatchScreens(screens));
      if (!mounted) return;
      setState(() => _message = screens.isEmpty
          ? l10n.watchScreensCleared
          : l10n.watchScreensPushed(screens.length));
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = l10n.watchScreensPushFailed('$e'));
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.watchScreensTitle),
        actions: [
          IconButton(
            tooltip: l10n.watchScreensPushAction,
            icon: _pushing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload),
            onPressed: _pushing || _phase != _Phase.ready ? null : _push,
          ),
        ],
      ),
      body: switch (_phase) {
        _Phase.loading => ListSkeleton(
            label: l10n.commonLoading,
            rows: 3,
            rowHeight: 96,
            hasLeading: false,
          ),
        _Phase.unreadable => _UnreadableState(onStartOver: _startOver),
        _Phase.ready => _buildEditor(context, l10n),
      },
    );
  }

  Widget _buildEditor(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final full = _drafts.length >= kMaxWatchScreens;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_message != null) ...[
          Text(_message!, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
        ],
        Text(
          l10n.watchScreensCount(_drafts.length, kMaxWatchScreens),
          style: theme.textTheme.labelLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (_drafts.isEmpty)
          EmptyState(
            icon: Icons.dashboard_customize,
            title: l10n.watchScreensEmptyTitle,
            body: l10n.watchScreensEmptyBody,
          )
        else
          for (var i = 0; i < _drafts.length; i++)
            _ScreenCard(
              index: i,
              draft: _drafts[i],
              onLayout: (next) => _changeLayout(i, next),
              onMetric: (slot, metric) => _setMetric(i, slot, metric),
              onMove: (slot, delta) => _moveSlot(i, slot, delta),
              onRemove: () => _removeScreen(i),
            ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: full ? null : _addScreen,
          icon: const Icon(Icons.add),
          label: Text(l10n.watchScreensAdd),
        ),
        if (full) ...[
          const SizedBox(height: 8),
          Text(
            l10n.watchScreensFull(kMaxWatchScreens),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _UnreadableState extends StatelessWidget {
  final VoidCallback onStartOver;

  const _UnreadableState({required this.onStartOver});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              l10n.watchScreensLoadFailed,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onStartOver,
              icon: const Icon(Icons.restart_alt),
              label: Text(l10n.watchScreensStartOver),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenCard extends StatelessWidget {
  final int index;
  final _Draft draft;
  final ValueChanged<WatchLayout> onLayout;
  final void Function(int slot, WatchMetric metric) onMetric;
  final void Function(int slot, int delta) onMove;
  final VoidCallback onRemove;

  const _ScreenCard({
    required this.index,
    required this.draft,
    required this.onLayout,
    required this.onMetric,
    required this.onMove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.watchScreensHeading(index + 1),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: l10n.watchScreensRemove,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onRemove,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChipRow<WatchLayout>(
                options: [
                  for (final layout in WatchLayout.values)
                    ChoiceChipOption(
                      value: layout,
                      label: watchLayoutLabel(l10n, layout),
                    ),
                ],
                selected: draft.layout,
                onChanged: onLayout,
              ),
            ),
            const SizedBox(height: 8),
            for (var slot = 0; slot < draft.metrics.length; slot++)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<WatchMetric>(
                        initialValue: draft.metrics[slot],
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.watchScreensSlot(slot + 1),
                          isDense: true,
                        ),
                        items: [
                          for (final m in WatchMetric.values)
                            DropdownMenuItem(
                              value: m,
                              child: Text(
                                watchMetricLabel(l10n, m),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (m) {
                          if (m != null) onMetric(slot, m);
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.watchScreensMoveUp,
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: slot == 0 ? null : () => onMove(slot, -1),
                    ),
                    IconButton(
                      tooltip: l10n.watchScreensMoveDown,
                      icon: const Icon(Icons.arrow_downward),
                      onPressed: slot == draft.metrics.length - 1
                          ? null
                          : () => onMove(slot, 1),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

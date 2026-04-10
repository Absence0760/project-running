import 'dart:async';
import 'dart:ui';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:run_recorder/run_recorder.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio_cues.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../widgets/live_run_map.dart';

/// Main run recording screen with GPS tracking, live stats, sync, audio cues,
/// auto-pause, countdown, and optional route following.
class RunScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final Preferences preferences;
  final AudioCues audioCues;
  final cm.Route? initialRoute;

  const RunScreen({
    super.key,
    this.apiClient,
    required this.runStore,
    required this.routeStore,
    required this.preferences,
    required this.audioCues,
    this.initialRoute,
  });

  @override
  State<RunScreen> createState() => _RunScreenState();
}

enum _ScreenState { idle, countdown, recording, paused, finished }

class _RunScreenState extends State<RunScreen> {
  _ScreenState _state = _ScreenState.idle;
  RunRecorder? _recorder;
  StreamSubscription<RunSnapshot>? _snapshotSub;

  // Countdown
  int _countdownValue = 3;
  Timer? _countdownTimer;

  // Selected route (optional)
  cm.Route? _selectedRoute;

  // Live stats
  Duration _elapsed = Duration.zero;
  double _distanceMetres = 0;
  double? _pace;
  List<cm.Waypoint> _track = [];
  int _lastTickNotified = 0;

  // Pause state
  Timer? _autoPauseCheckTimer;
  DateTime? _lastMovementAt;
  bool _autoPaused = false;
  bool _manualPaused = false;

  // Laps
  int _lapCount = 0;

  // Activity type
  ActivityType _activityType = ActivityType.run;

  // Pace alerts
  DateTime? _lastPaceAlertAt;

  // Off-route
  double? _offRouteDistance;
  bool _offRouteWarned = false;
  static const double _offRouteThresholdMetres = 40;

  // Distance remaining on selected route
  double? _routeRemaining;

  // Step tracking
  StreamSubscription<StepCount>? _stepSub;
  int _startSteps = 0;
  int _steps = 0;
  int _cadence = 0;
  final List<_StepSample> _stepSamples = [];

  // Finished run
  cm.Run? _finishedRun;
  bool _synced = false;
  String? _syncError;

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_onPrefsChange);
    _selectedRoute = widget.initialRoute;
  }

  @override
  void didUpdateWidget(covariant RunScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialRoute != null &&
        widget.initialRoute != oldWidget.initialRoute &&
        _state == _ScreenState.idle) {
      setState(() => _selectedRoute = widget.initialRoute);
    }
  }

  void _onPrefsChange() {
    if (mounted) setState(() {});
  }

  Future<bool> _ensurePermission() async {
    final status = await Permission.location.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required to record runs')),
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _selectRoute() async {
    final routes = widget.routeStore.routes;
    if (routes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No routes saved. Import one from the Routes tab.')),
      );
      return;
    }
    final unit = widget.preferences.unit;
    final picked = await showModalBottomSheet<cm.Route?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('No route'),
              onTap: () => Navigator.pop(ctx, null),
            ),
            const Divider(),
            ...routes.map((r) => ListTile(
                  leading: const Icon(Icons.route),
                  title: Text(r.name),
                  subtitle: Text(UnitFormat.distance(r.distanceMetres, unit)),
                  onTap: () => Navigator.pop(ctx, r),
                )),
          ],
        ),
      ),
    );
    setState(() => _selectedRoute = picked);
  }

  Future<void> _beginCountdown() async {
    if (!await _ensurePermission()) return;
    setState(() {
      _state = _ScreenState.countdown;
      _countdownValue = 3;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdownValue <= 1) {
        t.cancel();
        _start();
      } else {
        setState(() => _countdownValue--);
      }
    });
  }

  void _start() {
    _recorder = RunRecorder();
    _snapshotSub = _recorder!.snapshots.listen((snapshot) {
      final unit = widget.preferences.unit;

      // Detect movement for auto-pause
      if (snapshot.distanceMetres > _distanceMetres) {
        _lastMovementAt = DateTime.now();
        if (_autoPaused) {
          _recorder?.resume();
          setState(() => _autoPaused = false);
        }
      }

      setState(() {
        _elapsed = snapshot.elapsed;
        _distanceMetres = snapshot.distanceMetres;
        _pace = snapshot.currentPaceSecondsPerKm;
        _track = snapshot.track;
        _offRouteDistance = snapshot.offRouteDistanceMetres;
        _routeRemaining = snapshot.routeRemainingMetres;
      });

      // Off-route warning
      final off = snapshot.offRouteDistanceMetres;
      if (off != null) {
        if (off > _offRouteThresholdMetres && !_offRouteWarned) {
          _offRouteWarned = true;
          if (widget.preferences.audioCues) {
            widget.audioCues.announceOffRoute();
          }
        } else if (off < _offRouteThresholdMetres / 2) {
          _offRouteWarned = false;
        }
      }

      // Pace alert (skip for cycling — pace target doesn't apply)
      final target = widget.preferences.targetPaceSecPerKm;
      if (!_activityType.usesSpeed &&
          target > 0 &&
          _pace != null &&
          widget.preferences.audioCues) {
        final diff = _pace! - target;
        final lastAlert = _lastPaceAlertAt;
        final canAlert = lastAlert == null ||
            DateTime.now().difference(lastAlert).inSeconds > 30;
        if (canAlert && diff.abs() > 30) {
          _lastPaceAlertAt = DateTime.now();
          widget.audioCues.announcePaceAlert(tooSlow: diff > 0);
        }
      }

      // Distance tick notification + audio cue
      // Use activity-aware interval: 5km for cycling, 1km/mi for everything else.
      final tickInterval = _activityType.splitIntervalMetres;
      final currentTick = UnitFormat.activityTicks(_distanceMetres, tickInterval);
      if (currentTick > _lastTickNotified && currentTick > 0) {
        _lastTickNotified = currentTick;
        final totalDistanceMetres = currentTick * tickInterval;
        final tail = _activityType.usesSpeed
            ? '${UnitFormat.speed(_pace, unit)} ${UnitFormat.speedLabel(unit)}'
            : '${UnitFormat.pace(_pace, unit)} ${UnitFormat.paceLabel(unit)}';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${UnitFormat.distance(totalDistanceMetres, unit)} — $tail'),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        if (widget.preferences.audioCues) {
          widget.audioCues.announceSplit(
            distanceTicks: currentTick,
            paceSecondsPerKm: _pace,
            unit: unit,
            useSpeed: _activityType.usesSpeed,
            tickIntervalMetres: tickInterval,
          );
        }
      }
    });
    _recorder!.start(
      route: _selectedRoute,
      distanceFilterMetres: _activityType.gpsDistanceFilter,
      minMovementMetres: _activityType.minMovementMetres,
    );

    // Keep screen awake during run
    WakelockPlus.enable();

    // Step counter
    _stepSub = Pedometer.stepCountStream.listen((event) {
      if (_startSteps == 0) _startSteps = event.steps;
      final newSteps = event.steps - _startSteps;
      _stepSamples.add(_StepSample(DateTime.now(), newSteps));
      final cutoff = DateTime.now().subtract(const Duration(seconds: 10));
      _stepSamples.removeWhere((s) => s.time.isBefore(cutoff));
      if (_stepSamples.length >= 2) {
        final first = _stepSamples.first;
        final last = _stepSamples.last;
        final dt = last.time.difference(first.time).inMilliseconds / 1000.0;
        if (dt > 1) {
          _cadence = ((last.steps - first.steps) / dt * 60).round();
        }
      }
      setState(() => _steps = newSteps);
    }, onError: (_) {});

    // Auto-pause check (every 2s)
    _lastMovementAt = DateTime.now();
    _autoPauseCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!widget.preferences.autoPause || _state != _ScreenState.recording) return;
      final last = _lastMovementAt;
      if (last == null) return;
      final stillFor = DateTime.now().difference(last);
      if (stillFor.inSeconds >= 10 && !_autoPaused) {
        _recorder?.pause();
        setState(() => _autoPaused = true);
      }
    });

    if (widget.preferences.audioCues) widget.audioCues.announceStart();

    setState(() => _state = _ScreenState.recording);
  }

  void _toggleManualPause() {
    if (_recorder == null) return;
    if (_manualPaused) {
      _recorder!.resume();
      setState(() => _manualPaused = false);
      _lastMovementAt = DateTime.now();
    } else {
      _recorder!.pause();
      setState(() => _manualPaused = true);
    }
  }

  void _markLap() {
    if (_recorder == null) return;
    final n = _recorder!.lap();
    if (n > 0) {
      setState(() => _lapCount = n);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lap $n marked'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _stop() async {
    final raw = await _recorder!.stop();
    _snapshotSub?.cancel();
    _stepSub?.cancel();
    _autoPauseCheckTimer?.cancel();
    WakelockPlus.disable();

    // Tag the run with the chosen activity type
    final metadata = Map<String, dynamic>.from(raw.metadata ?? {});
    metadata['activity_type'] = _activityType.name;

    final run = cm.Run(
      id: raw.id,
      startedAt: raw.startedAt,
      duration: raw.duration,
      distanceMetres: raw.distanceMetres,
      track: raw.track,
      routeId: raw.routeId,
      source: raw.source,
      externalId: raw.externalId,
      metadata: metadata,
      createdAt: raw.createdAt,
    );

    setState(() {
      _finishedRun = run;
      _state = _ScreenState.finished;
    });

    if (widget.preferences.audioCues) {
      widget.audioCues.announceFinish(
        distanceMetres: run.distanceMetres,
        elapsed: run.duration,
        unit: widget.preferences.unit,
      );
    }

    await widget.runStore.save(run);

    final api = widget.apiClient;
    if (api != null && api.userId != null) {
      try {
        await api.saveRun(run);
        await widget.runStore.markSynced(run.id);
        if (mounted) setState(() => _synced = true);
      } catch (e) {
        debugPrint('Auto-sync failed: $e');
        if (mounted) setState(() => _syncError = 'Saved offline. Sync from History.');
      }
    } else {
      if (mounted) setState(() => _syncError = 'Saved offline.');
    }
  }

  Future<void> _confirmDiscardMidRun() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard run?'),
        content: const Text('Your progress will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep running'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok == true) _discard();
  }

  void _discard() {
    _snapshotSub?.cancel();
    _stepSub?.cancel();
    _autoPauseCheckTimer?.cancel();
    _countdownTimer?.cancel();
    _recorder?.dispose();
    _recorder = null;
    WakelockPlus.disable();
    setState(() {
      _state = _ScreenState.idle;
      _elapsed = Duration.zero;
      _distanceMetres = 0;
      _pace = null;
      _track = [];
      _lastTickNotified = 0;
      _steps = 0;
      _startSteps = 0;
      _cadence = 0;
      _finishedRun = null;
      _synced = false;
      _syncError = null;
      _autoPaused = false;
      _manualPaused = false;
      _lapCount = 0;
      _offRouteDistance = null;
      _offRouteWarned = false;
      _routeRemaining = null;
      _lastPaceAlertAt = null;
    });
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_onPrefsChange);
    _snapshotSub?.cancel();
    _stepSub?.cancel();
    _countdownTimer?.cancel();
    _autoPauseCheckTimer?.cancel();
    _recorder?.dispose();
    super.dispose();
  }

  // ──────────────── Formatting ────────────────

  DistanceUnit get _unit => widget.preferences.unit;

  String get _formattedTime {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes % 60;
    final s = _elapsed.inSeconds % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _formattedDistance => UnitFormat.distance(_distanceMetres, _unit);

  String get _formattedDistanceValue =>
      UnitFormat.distanceValue(_distanceMetres, _unit);

  String get _formattedPaceValue => UnitFormat.pace(_pace, _unit);

  String get _formattedAvgPaceValue {
    if (_distanceMetres < 10 || _elapsed.inSeconds < 1) return '--:--';
    final secPerKm = _elapsed.inSeconds / (_distanceMetres / 1000);
    return UnitFormat.pace(secPerKm, _unit);
  }

  String get _formattedAvgSpeedValue {
    if (_distanceMetres < 10 || _elapsed.inSeconds < 1) return '--';
    final secPerKm = _elapsed.inSeconds / (_distanceMetres / 1000);
    return UnitFormat.speed(secPerKm, _unit);
  }

  String get _formattedCalories {
    // Assume 70 kg body weight; multiplier varies by activity.
    final cals = (70 * _activityType.kcalPerKgPerKm * _distanceMetres / 1000).round();
    return '$cals';
  }

  String get _formattedElevation {
    if (_track.length < 2) return '0';
    double gain = 0;
    for (int i = 1; i < _track.length; i++) {
      final prev = _track[i - 1].elevationMetres;
      final curr = _track[i].elevationMetres;
      if (prev != null && curr != null && curr > prev) gain += curr - prev;
    }
    return '${gain.round()}';
  }

  // ──────────────── Build ────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_state) {
        _ScreenState.idle => _buildIdle(context),
        _ScreenState.countdown => _buildCountdown(context),
        _ScreenState.recording || _ScreenState.paused => _buildRecording(context),
        _ScreenState.finished => _buildFinished(context),
      },
    );
  }

  Widget _buildIdle(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary.withOpacity(0.15),
                      theme.colorScheme.tertiary.withOpacity(0.1),
                    ],
                  ),
                ),
                child: Icon(_activityType.icon,
                    size: 48, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 24),
              Text(
                'Ready to ${_activityType.label}',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _selectedRoute != null
                    ? 'Following: ${_selectedRoute!.name}'
                    : 'GPS tracking and live map will activate\nwhen you press start',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              // Activity type chips
              Wrap(
                spacing: 8,
                children: ActivityType.values.map((t) {
                  final selected = t == _activityType;
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.icon, size: 16),
                        const SizedBox(width: 4),
                        Text(t.label),
                      ],
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() => _activityType = t),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Route selector
              OutlinedButton.icon(
                onPressed: _selectRoute,
                icon: const Icon(Icons.route),
                label: Text(_selectedRoute == null ? 'Choose route' : 'Change route'),
              ),

              const SizedBox(height: 32),

              // Start button
              GestureDetector(
                onTap: _beginCountdown,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF22C55E).withOpacity(0.3),
                      width: 3,
                    ),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x4022C55E),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'START',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountdown(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            '$_countdownValue',
            key: ValueKey(_countdownValue),
            style: const TextStyle(
              fontSize: 200,
              fontWeight: FontWeight.w900,
              color: Color(0xFF22C55E),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecording(BuildContext context) {
    return Stack(
      children: [
        LiveRunMap(track: _track, plannedRoute: _selectedRoute?.waypoints),

        // "X to go" badge — top right when a route is selected
        if (_routeRemaining != null)
          Positioned(
            top: 56,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 8),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.flag_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${UnitFormat.distance(_routeRemaining!, _unit)} to go',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

        if (_autoPaused)
          const Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Card(
                color: Color(0xFFF59E0B),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Auto-paused — start moving to resume',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        if (_offRouteDistance != null &&
            _offRouteDistance! > _offRouteThresholdMetres)
          Positioned(
            top: _autoPaused ? 110 : 60,
            left: 0,
            right: 0,
            child: Center(
              child: Card(
                color: const Color(0xFFEF4444),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Off route — ${_offRouteDistance!.round()}m away',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _StatsOverlay(
            time: _formattedTime,
            distanceValue: _formattedDistanceValue,
            distanceUnit: UnitFormat.distanceLabel(_unit),
            primaryValue: _activityType.usesSpeed
                ? UnitFormat.speed(_pace, _unit)
                : _formattedPaceValue,
            primaryUnit: _activityType.usesSpeed
                ? UnitFormat.speedLabel(_unit)
                : UnitFormat.paceLabel(_unit),
            primaryLabel: _activityType.usesSpeed ? 'Speed' : 'Pace',
            secondaryValue: _activityType.usesSpeed
                ? _formattedAvgSpeedValue
                : _formattedAvgPaceValue,
            secondaryLabel: _activityType.usesSpeed ? 'Avg Speed' : 'Avg Pace',
            calories: _formattedCalories,
            elevation: _formattedElevation,
            steps: '$_steps',
            cadence: '$_cadence',
            lapCount: _lapCount,
            paused: _manualPaused,
            onStop: _stop,
            onDiscard: _confirmDiscardMidRun,
            onPauseToggle: _toggleManualPause,
            onLap: _markLap,
          ),
        ),
      ],
    );
  }

  Widget _buildFinished(BuildContext context) {
    final theme = Theme.of(context);
    final track = _finishedRun?.track ?? <cm.Waypoint>[];

    return Column(
      children: [
        Expanded(
          flex: 3,
          child: LiveRunMap(track: track, followRunner: false),
        ),
        Expanded(
          flex: 4,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Run Complete', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatColumn(label: 'Distance', value: _formattedDistance),
                      _StatColumn(label: 'Time', value: _formattedTime),
                      _StatColumn(
                        label: _activityType.usesSpeed ? 'Avg Speed' : 'Pace',
                        value: _activityType.usesSpeed
                            ? _formattedAvgSpeedValue
                            : _formattedAvgPaceValue,
                        unit: _activityType.usesSpeed
                            ? UnitFormat.speedLabel(_unit)
                            : UnitFormat.paceLabel(_unit),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_synced) ...[
                    const Icon(Icons.cloud_done, color: Colors.green, size: 36),
                    const SizedBox(height: 4),
                    const Text('Synced'),
                  ] else if (_syncError != null) ...[
                    const Icon(Icons.cloud_off, size: 36, color: Colors.orange),
                    const SizedBox(height: 4),
                    Text(_syncError!,
                        style: const TextStyle(color: Colors.orange, fontSize: 13)),
                  ] else ...[
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(height: 4),
                    const Text('Syncing...'),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _discard, child: const Text('Done')),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Frosted glass stats bar overlaid on the map during recording.
class _StatsOverlay extends StatelessWidget {
  final String time;
  final String distanceValue;
  final String distanceUnit;
  final String primaryValue;
  final String primaryUnit;
  final String primaryLabel;
  final String secondaryValue;
  final String secondaryLabel;
  final String calories;
  final String elevation;
  final String steps;
  final String cadence;
  final int lapCount;
  final bool paused;
  final VoidCallback onStop;
  final VoidCallback onDiscard;
  final VoidCallback onPauseToggle;
  final VoidCallback onLap;

  const _StatsOverlay({
    required this.time,
    required this.distanceValue,
    required this.distanceUnit,
    required this.primaryValue,
    required this.primaryUnit,
    required this.primaryLabel,
    required this.secondaryValue,
    required this.secondaryLabel,
    required this.calories,
    required this.elevation,
    required this.steps,
    required this.cadence,
    required this.lapCount,
    required this.paused,
    required this.onStop,
    required this.onDiscard,
    required this.onPauseToggle,
    required this.onLap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(context).padding.bottom + 16,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                time,
                style: theme.textTheme.displayMedium?.copyWith(
                  fontFeatures: [const FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: _StatColumn(
                          label: 'Distance', value: distanceValue, unit: distanceUnit)),
                  _divider(theme),
                  Expanded(
                      child: _StatColumn(
                          label: primaryLabel, value: primaryValue, unit: primaryUnit)),
                  _divider(theme),
                  Expanded(
                      child: _StatColumn(
                          label: secondaryLabel, value: secondaryValue, unit: primaryUnit)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _StatColumn(label: 'Calories', value: calories, unit: 'kcal')),
                  _divider(theme),
                  Expanded(child: _StatColumn(label: 'Elevation', value: elevation, unit: 'm')),
                  _divider(theme),
                  Expanded(child: _StatColumn(label: 'Steps', value: steps)),
                  _divider(theme),
                  Expanded(child: _StatColumn(label: 'Cadence', value: cadence, unit: 'spm')),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Discard button
                  GestureDetector(
                    onTap: onDiscard,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.surfaceContainerHighest,
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        size: 26,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Pause / Resume
                  GestureDetector(
                    onTap: onPauseToggle,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: paused ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                      ),
                      child: Center(
                        child: Icon(
                          paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Stop button
                  GestureDetector(
                    onTap: onStop,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x40EF4444),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.stop_rounded, size: 36, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Lap button
                  GestureDetector(
                    onTap: onLap,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.primaryContainer,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.flag_rounded,
                            size: 28,
                            color: theme.colorScheme.primary,
                          ),
                          if (lapCount > 0)
                            Positioned(
                              right: 6,
                              top: 6,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.red,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 14,
                                  minHeight: 14,
                                ),
                                child: Text(
                                  '$lapCount',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider(ThemeData theme) {
    return Container(width: 1, height: 28, color: theme.dividerColor);
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  const _StatColumn({required this.label, required this.value, this.unit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 2),
              Text(
                unit!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _StepSample {
  final DateTime time;
  final int steps;
  const _StepSample(this.time, this.steps);
}

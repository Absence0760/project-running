import 'dart:async';
import 'dart:ui';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:run_recorder/run_recorder.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio_cues.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../widgets/collapsible_panel.dart';
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
  cm.Waypoint? _currentPosition;
  int _lastTickNotified = 0;

  // Pause state
  Timer? _autoPauseCheckTimer;
  DateTime? _lastMovementAt;
  DateTime? _lastSnapshotAt;
  DateTime? _recordingStartedAt;
  cm.Waypoint? _lastMovementCheckPosition;
  bool _autoPaused = false;
  bool _manualPaused = false;

  // Grace period after _begin() during which auto-pause is suppressed, to
  // give the GPS radio time to warm up without false-pausing the runner.
  static const _autoPauseGracePeriod = Duration(seconds: 15);
  // Maximum staleness of the last snapshot we'll trust when deciding to
  // auto-pause. If GPS has been silent longer than this we don't know the
  // runner's state, so we don't pause.
  static const _autoPauseMaxSnapshotGap = Duration(seconds: 6);

  // Reentrancy guard on start — prevents rapid taps from spawning
  // multiple recorders.
  bool _startRequested = false;

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
  int _latestPedometerSteps = 0;
  final List<_StepSample> _stepSamples = [];

  // Prepare-phase state. The recorder, GPS stream, pedometer, and wakelock
  // are warmed up at the start of the countdown so begin() is instant when
  // the 3 seconds are up.
  Future<void>? _prepareFuture;

  // Finished run
  cm.Run? _finishedRun;
  bool _synced = false;
  String? _syncError;

  // Measured height of the stats overlay — used to offset the map camera so
  // the blue dot sits in the visible area above the overlay, not behind it.
  final GlobalKey _statsOverlayKey = GlobalKey();
  double _statsOverlayHeight = 300;

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
    if (_startRequested || _state != _ScreenState.idle) return;
    _startRequested = true;
    if (!await _ensurePermission()) {
      _startRequested = false;
      return;
    }
    setState(() {
      _state = _ScreenState.countdown;
      _countdownValue = 3;
    });

    // Warm up everything that would otherwise delay the start of the run —
    // GPS stream, pedometer sensor, wakelock — while the countdown ticks.
    _preload();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdownValue <= 1) {
        t.cancel();
        _begin();
      } else {
        setState(() => _countdownValue--);
      }
    });
  }

  /// Kick off all asynchronous setup that's needed before the run can start
  /// cleanly. Runs during the countdown so the user doesn't see a delay when
  /// it ends.
  void _preload() {
    _recorder = RunRecorder();
    _snapshotSub = _recorder!.snapshots.listen(_onSnapshot);

    // Pedometer sensor stream. We subscribe now, but don't count steps
    // toward the run until _begin sets a baseline.
    _stepSub = Pedometer.stepCountStream.listen((event) {
      _latestPedometerSteps = event.steps;
      if (_state != _ScreenState.recording) return;
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
      if (mounted) setState(() => _steps = newSteps);
    }, onError: (_) {});

    // Keep the screen awake from the start of the countdown onward.
    WakelockPlus.enable();

    // Open the GPS stream now so the first fix is already in hand when the
    // run starts. Positions received during this phase drive the blue dot
    // but don't accumulate into the track or distance.
    _prepareFuture = _recorder!
        .prepare(
      route: _selectedRoute,
      distanceFilterMetres: _activityType.gpsDistanceFilter,
      minMovementMetres: _activityType.minMovementMetres,
    )
        .catchError((e, st) {
      debugPrint('RunRecorder.prepare failed: $e');
    });
  }

  /// Flip the run on. All expensive setup was already done in [_preload];
  /// this is synchronous aside from a last-resort await on the prepare
  /// future in case it hasn't completed yet.
  Future<void> _begin() async {
    // In the common case prepare has already completed during the 3-second
    // countdown, so this await is a no-op. On a slow device it waits for
    // the GPS stream to come up before starting the clock.
    await _prepareFuture;

    if (!mounted || _recorder == null) return;

    _recorder!.begin();

    // Reset the pedometer baseline so steps taken during the countdown
    // don't count toward the run.
    _startSteps = _latestPedometerSteps;
    _steps = 0;
    _cadence = 0;
    _stepSamples.clear();

    // Auto-pause check (every 2s). Only meaningful once recording starts.
    _lastMovementAt = DateTime.now();
    _lastMovementCheckPosition = null;
    _recordingStartedAt = DateTime.now();
    _autoPauseCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!widget.preferences.autoPause ||
          _state != _ScreenState.recording) return;

      // Grace period after start — GPS is still warming up, no false pause.
      final startedAt = _recordingStartedAt;
      if (startedAt != null &&
          DateTime.now().difference(startedAt) < _autoPauseGracePeriod) {
        return;
      }

      // Snapshot freshness gate — if we haven't received a GPS fix recently,
      // we don't know whether the runner is moving, so don't pause.
      final lastSnap = _lastSnapshotAt;
      if (lastSnap == null ||
          DateTime.now().difference(lastSnap) > _autoPauseMaxSnapshotGap) {
        return;
      }

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

  void _onSnapshot(RunSnapshot snapshot) {
      final unit = widget.preferences.unit;

      // Record that a fresh GPS-backed snapshot arrived. Auto-pause uses
      // this to avoid firing when GPS is silent (we don't know the runner's
      // state, so pausing would be wrong).
      _lastSnapshotAt = DateTime.now();

      // Detect movement for auto-pause. We compare raw waypoint positions
      // instead of the track's distanceMetres, because the track threshold
      // (3 m by default) can make distanceMetres look "stuck" for 10+ seconds
      // at slow walking pace even though the runner is genuinely moving.
      if (_state == _ScreenState.recording) {
        final curr = snapshot.currentPosition;
        final prev = _lastMovementCheckPosition;
        if (prev == null) {
          _lastMovementCheckPosition = curr;
          _lastMovementAt = DateTime.now();
        } else {
          final moved = Geolocator.distanceBetween(
            prev.lat, prev.lng, curr.lat, curr.lng,
          );
          if (moved > 1.5) {
            _lastMovementAt = DateTime.now();
            _lastMovementCheckPosition = curr;
            if (_autoPaused) {
              _recorder?.resume();
              setState(() => _autoPaused = false);
            }
          }
        }
      }

      setState(() {
        _elapsed = snapshot.elapsed;
        _distanceMetres = snapshot.distanceMetres;
        _pace = snapshot.currentPaceSecondsPerKm;
        _track = snapshot.track;
        _currentPosition = snapshot.currentPosition;
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
        final totalDistanceMetres = (currentTick * tickInterval).toDouble();
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
    _prepareFuture = null;
    _stepSamples.clear();
    _latestPedometerSteps = 0;
    _lastMovementCheckPosition = null;
    _lastSnapshotAt = null;
    _recordingStartedAt = null;
    _startRequested = false;
    WakelockPlus.disable();
    setState(() {
      _state = _ScreenState.idle;
      _elapsed = Duration.zero;
      _distanceMetres = 0;
      _pace = null;
      _track = [];
      _currentPosition = null;
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
    // Measure the stats overlay after layout so the map can offset its
    // follow-cam by the real height rather than a hard-coded guess.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _statsOverlayKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final h = box.size.height;
      if ((h - _statsOverlayHeight).abs() > 1 && mounted) {
        setState(() => _statsOverlayHeight = h);
      }
    });

    return Stack(
      children: [
        LiveRunMap(
          track: _track,
          currentPosition: _currentPosition,
          plannedRoute: _selectedRoute?.waypoints,
          bottomPadding: _statsOverlayHeight,
        ),

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
          child: CollapsiblePanel(
            key: _statsOverlayKey,
            collapsedChild: _CollapsedStatsBar(
              time: _formattedTime,
              onStop: _stop,
            ),
            expandedChild: _StatsOverlay(
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
              secondaryLabel:
                  _activityType.usesSpeed ? 'Avg Speed' : 'Avg Pace',
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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

/// Minimal stats bar shown when the overlay is collapsed. Keeps time visible
/// plus a stop button so the runner can still abort without expanding first.
class _CollapsedStatsBar extends StatelessWidget {
  final String time;
  final VoidCallback onStop;

  const _CollapsedStatsBar({required this.time, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              time,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFeatures: [const FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          GestureDetector(
            onTap: onStop,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red,
              ),
              child: const Center(
                child: Icon(Icons.stop_rounded, size: 26, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

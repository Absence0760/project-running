import 'dart:async';
import 'dart:ui';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:run_recorder/run_recorder.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio_cues.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../run_stats.dart';
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

  // Manual pause only — there is no longer any auto-pause layer. The clock
  // runs continuously during a run (except when the user explicitly taps
  // pause), and "moving time" is computed as a derived metric on the
  // finished-run screen from the GPS track.
  bool _manualPaused = false;
  DateTime? _lastSnapshotAt;

  // Reentrancy guard on start — prevents rapid taps from spawning
  // multiple recorders.
  bool _startRequested = false;

  // Crash-safe incremental persistence. A partial Run is serialised every
  // [_incrementalSaveInterval] during a recording; the id is generated at
  // _begin() so the saved run has a stable identity across ticks and across
  // a crash+recover cycle.
  static const _incrementalSaveInterval = Duration(seconds: 10);
  static const _uuid = Uuid();
  Timer? _incrementalSaveTimer;
  String? _runId;
  DateTime? _runStartedAtWall;

  // GPS signal state. If snapshots stop arriving for > _gpsLostThreshold we
  // show a banner warning the runner so they're not surprised at stop time.
  static const _gpsLostThreshold = Duration(seconds: 10);
  bool _gpsLost = false;
  Timer? _gpsLostCheckTimer;

  // Permission watchdog — polls Geolocator.checkPermission() so we can
  // warn the runner if location permission is revoked mid-run in Android
  // settings.
  Timer? _permissionWatchdogTimer;
  bool _permissionLost = false;

  // Pedometer resubscribe back-off — if the stream errors we wait a bit,
  // then try again. Failures during a run shouldn't silently drop the
  // cadence widget forever.
  int _pedometerRetries = 0;
  static const _pedometerMaxRetries = 5;

  // Hold-to-stop progress (0..1) — drives the circular progress ring on
  // the big red stop button, preventing accidental one-tap stops.
  static const _holdToStopDuration = Duration(milliseconds: 800);
  Timer? _holdToStopTicker;
  double _holdToStopProgress = 0.0;

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
    widget.runStore.addListener(_onPrefsChange);
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
    _subscribeToPedometer();

    // Keep the screen awake from the start of the countdown onward.
    WakelockPlus.enable();

    // Open the GPS stream now so the first fix is already in hand when the
    // run starts. Positions received during this phase drive the blue dot
    // but don't accumulate into the track or distance.
    final adv = widget.preferences.advancedGps;
    _prepareFuture = _recorder!
        .prepare(
      route: _selectedRoute,
      distanceFilterMetres: adv ? 2 : _activityType.gpsDistanceFilter,
      minMovementMetres: adv ? 1 : _activityType.minMovementMetres,
      maxSpeedMps: _activityType.maxSpeedMps,
      accuracy: adv ? LocationAccuracy.best : LocationAccuracy.high,
      accuracyGateMetres: adv ? 10 : 20,
    )
        .catchError((e, st) {
      debugPrint('RunRecorder.prepare failed: $e');
    });
  }

  /// Subscribe to the pedometer stream. On error, wait a bit and retry —
  /// a transient sensor glitch shouldn't kill the cadence widget for the
  /// rest of the run.
  void _subscribeToPedometer() {
    _stepSub?.cancel();
    _stepSub = Pedometer.stepCountStream.listen((event) {
      _pedometerRetries = 0; // reset back-off on successful event
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
    }, onError: (e) {
      debugPrint('Pedometer stream error: $e');
      if (_pedometerRetries >= _pedometerMaxRetries) return;
      _pedometerRetries++;
      // Exponential-ish backoff capped at 16s.
      final delay = Duration(seconds: (1 << _pedometerRetries).clamp(1, 16));
      Future.delayed(delay, () {
        if (!mounted) return;
        if (_state == _ScreenState.idle ||
            _state == _ScreenState.finished) return;
        _subscribeToPedometer();
      });
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

    // Stable run id + wall-clock start time for incremental persistence.
    _runId = _uuid.v4();
    _runStartedAtWall = DateTime.now();

    // Reset the pedometer baseline so steps taken during the countdown
    // don't count toward the run.
    _startSteps = _latestPedometerSteps;
    _steps = 0;
    _cadence = 0;
    _stepSamples.clear();

    // Crash-safe incremental persistence — every 10s, write the current
    // track + stats to a separate file so a force-kill mid-run is recoverable.
    _incrementalSaveTimer =
        Timer.periodic(_incrementalSaveInterval, (_) => _saveInProgress());

    // GPS-lost banner watchdog — flag stale signal in the UI.
    _gpsLostCheckTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _checkGpsHealth());

    // Location permission watchdog — catch cases where the runner toggles
    // permission off in Android settings while the run is in flight.
    _permissionWatchdogTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkPermission(),
    );

    if (widget.preferences.audioCues) widget.audioCues.announceStart();

    setState(() => _state = _ScreenState.recording);
  }

  void _onSnapshot(RunSnapshot snapshot) {
      final unit = widget.preferences.unit;

      // Record that a fresh GPS-backed snapshot arrived. The GPS-lost
      // banner uses this to know whether the sensor is alive.
      _lastSnapshotAt = DateTime.now();

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

      // Distance tick notification + audio cue.
      // Custom interval from preferences overrides the activity-type default.
      final customInterval = widget.preferences.splitIntervalMetres;
      final tickInterval = customInterval > 0
          ? customInterval.toDouble()
          : _activityType.splitIntervalMetres;
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

  /// Serialise the in-progress run to disk. Runs every 10s via
  /// [_incrementalSaveTimer] so a crash mid-run is recoverable.
  Future<void> _saveInProgress() async {
    final id = _runId;
    final startedAt = _runStartedAtWall;
    if (id == null || startedAt == null) return;
    if (_state != _ScreenState.recording) return;

    final metadata = <String, dynamic>{
      'activity_type': _activityType.name,
      'in_progress_saved_at': DateTime.now().toIso8601String(),
    };
    final run = cm.Run(
      id: id,
      startedAt: startedAt,
      duration: _elapsed,
      distanceMetres: _distanceMetres,
      track: List.unmodifiable(_track),
      source: cm.RunSource.app,
      metadata: metadata,
    );
    try {
      await widget.runStore.saveInProgress(run);
    } catch (e) {
      debugPrint('Incremental save failed: $e');
    }
  }

  /// Update [_gpsLost] based on snapshot freshness. Drives the warning
  /// banner rendered in [_buildRecording].
  void _checkGpsHealth() {
    if (_state != _ScreenState.recording) return;
    final last = _lastSnapshotAt;
    final lost = last == null ||
        DateTime.now().difference(last) > _gpsLostThreshold;
    if (lost != _gpsLost && mounted) {
      setState(() => _gpsLost = lost);
    }
  }

  /// Poll location permission so we can surface a banner if the runner
  /// toggles it off in Android settings mid-run. The recorder's position
  /// stream will silently stall otherwise.
  Future<void> _checkPermission() async {
    if (_state != _ScreenState.recording) return;
    try {
      final p = await Geolocator.checkPermission();
      final lost = p == LocationPermission.denied ||
          p == LocationPermission.deniedForever;
      if (lost != _permissionLost && mounted) {
        setState(() => _permissionLost = lost);
      }
    } catch (e) {
      debugPrint('Permission check failed: $e');
    }
  }

  void _toggleManualPause() {
    if (_recorder == null) return;
    if (_manualPaused) {
      _recorder!.resume();
      setState(() => _manualPaused = false);
    } else {
      _recorder!.pause();
      setState(() => _manualPaused = true);
    }
  }

  // Hold-to-stop gesture: ticker animates a progress ring around the stop
  // button, calling _stop() when the full duration elapses. Cancelled if
  // the user lifts their finger early.
  void _startHoldToStop() {
    _holdToStopTicker?.cancel();
    final start = DateTime.now();
    _holdToStopTicker = Timer.periodic(const Duration(milliseconds: 16), (t) {
      final elapsed = DateTime.now().difference(start);
      final progress =
          (elapsed.inMilliseconds / _holdToStopDuration.inMilliseconds)
              .clamp(0.0, 1.0);
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _holdToStopProgress = progress);
      if (progress >= 1.0) {
        t.cancel();
        _holdToStopProgress = 0;
        _stop();
      }
    });
  }

  void _cancelHoldToStop() {
    _holdToStopTicker?.cancel();
    _holdToStopTicker = null;
    if (_holdToStopProgress != 0 && mounted) {
      setState(() => _holdToStopProgress = 0);
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
    _incrementalSaveTimer?.cancel();
    _gpsLostCheckTimer?.cancel();
    _permissionWatchdogTimer?.cancel();
    _holdToStopTicker?.cancel();
    WakelockPlus.disable();

    // Tag the run with the chosen activity type + step count so the web
    // and future mobile views can display a consistent summary.
    final metadata = Map<String, dynamic>.from(raw.metadata ?? {});
    metadata['activity_type'] = _activityType.name;
    if (_steps > 0) metadata['steps'] = _steps;

    // Prefer the stable id generated at _begin() over the recorder's
    // stop-time uuid so the saved run matches any incremental in-progress
    // file that may have been written while recording.
    final runId = _runId ?? raw.id;
    final run = cm.Run(
      id: runId,
      startedAt: _runStartedAtWall ?? raw.startedAt,
      duration: raw.duration,
      distanceMetres: raw.distanceMetres,
      track: raw.track,
      routeId: _selectedRoute?.id ?? raw.routeId,
      source: raw.source,
      externalId: raw.externalId,
      metadata: metadata,
      createdAt: raw.createdAt,
    );

    // Clear the in-progress file now that we've got the authoritative run.
    await widget.runStore.clearInProgress();

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
    _countdownTimer?.cancel();
    _incrementalSaveTimer?.cancel();
    _gpsLostCheckTimer?.cancel();
    _permissionWatchdogTimer?.cancel();
    _holdToStopTicker?.cancel();
    _recorder?.dispose();
    _recorder = null;
    _prepareFuture = null;
    _stepSamples.clear();
    _latestPedometerSteps = 0;
    _lastSnapshotAt = null;
    _startRequested = false;
    _runId = null;
    _runStartedAtWall = null;
    _pedometerRetries = 0;
    _gpsLost = false;
    _permissionLost = false;
    _holdToStopProgress = 0;
    // Fire-and-forget — if we discarded mid-run, drop the in-progress file.
    widget.runStore.clearInProgress();
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
    widget.runStore.removeListener(_onPrefsChange);
    _snapshotSub?.cancel();
    _stepSub?.cancel();
    _countdownTimer?.cancel();
    _incrementalSaveTimer?.cancel();
    _gpsLostCheckTimer?.cancel();
    _permissionWatchdogTimer?.cancel();
    _holdToStopTicker?.cancel();
    _recorder?.dispose();
    super.dispose();
  }

  // ──────────────── Formatting ────────────────

  DistanceUnit get _unit => widget.preferences.unit;

  String get _formattedTime => _formatDuration(_elapsed);

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
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

  /// Average pace computed against a supplied moving time rather than the
  /// full elapsed time. Used on the finished-run screen so the headline
  /// pace excludes stops.
  String _formattedAvgPaceValueFromMoving(Duration movingTime) {
    if (_distanceMetres < 10 || movingTime.inSeconds < 1) return '--:--';
    final secPerKm = movingTime.inSeconds / (_distanceMetres / 1000);
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
    final lastRun = _mostRecentRun();
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 32,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    Center(
                      child: Wrap(
                        spacing: 8,
                        children: ActivityType.values.map((t) {
                          final selected = t == _activityType;
                          return ChoiceChip(
                            showCheckmark: false,
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(t.icon, size: 16),
                                const SizedBox(width: 4),
                                Text(t.label),
                              ],
                            ),
                            selected: selected,
                            onSelected: (_) {
                              if (_state != _ScreenState.idle) return;
                              setState(() => _activityType = t);
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: _selectRoute,
                        icon: const Icon(Icons.route),
                        label: Text(
                          _selectedRoute == null
                              ? 'Choose route'
                              : 'Change route',
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_selectedRoute != null)
                      _RoutePreviewCard(route: _selectedRoute!)
                    else if (lastRun != null)
                      _LastRunCard(run: lastRun)
                    else
                      _FirstRunPrompt(theme: theme),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: GestureDetector(
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  cm.Run? _mostRecentRun() {
    final runs = widget.runStore.runs;
    if (runs.isEmpty) return null;
    final sorted = [...runs]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sorted.first;
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

        if (_offRouteDistance != null &&
            _offRouteDistance! > _offRouteThresholdMetres)
          Positioned(
            top: 60,
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
        if (_permissionLost)
          const Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Card(
                color: Color(0xFFDC2626),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_off, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Location permission revoked',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else if (_gpsLost)
          const Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Card(
                color: Color(0xFFEF4444),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.gps_off, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'GPS signal lost — move to open sky',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ],
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
              holdProgress: _holdToStopProgress,
              onHoldStart: _startHoldToStop,
              onHoldCancel: _cancelHoldToStop,
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
              holdProgress: _holdToStopProgress,
              onHoldStart: _startHoldToStop,
              onHoldCancel: _cancelHoldToStop,
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
    // Derived metric: "moving time" — elapsed with stops excluded, computed
    // from the GPS track. Replaces the old live auto-pause.
    final movingTime = movingTimeOf(track);

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
                        label: 'Moving',
                        value: _formatDuration(movingTime),
                      ),
                      _StatColumn(
                        label: _activityType.usesSpeed ? 'Avg Speed' : 'Pace',
                        value: _activityType.usesSpeed
                            ? _formattedAvgSpeedValue
                            : _formattedAvgPaceValueFromMoving(movingTime),
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
  final double holdProgress;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldCancel;
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
    required this.holdProgress,
    required this.onHoldStart,
    required this.onHoldCancel,
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
                  // Stop button — hold-to-stop, 800ms. Prevents accidental
                  // one-tap stops mid-run.
                  _HoldToStopButton(
                    progress: holdProgress,
                    onHoldStart: onHoldStart,
                    onHoldCancel: onHoldCancel,
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
/// plus a hold-to-stop button so the runner can still abort without
/// expanding first.
class _CollapsedStatsBar extends StatelessWidget {
  final String time;
  final double holdProgress;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldCancel;

  const _CollapsedStatsBar({
    required this.time,
    required this.holdProgress,
    required this.onHoldStart,
    required this.onHoldCancel,
  });

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
          _HoldToStopButton(
            progress: holdProgress,
            size: 48,
            iconSize: 24,
            onHoldStart: onHoldStart,
            onHoldCancel: onHoldCancel,
          ),
        ],
      ),
    );
  }
}

/// Big red stop button that must be *held* for ~800 ms before the run is
/// actually stopped. The circular progress ring grows during the hold so
/// the user gets clear visual feedback. Cancels cleanly on release.
class _HoldToStopButton extends StatelessWidget {
  final double progress;
  final double size;
  final double iconSize;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldCancel;

  const _HoldToStopButton({
    required this.progress,
    required this.onHoldStart,
    required this.onHoldCancel,
    this.size = 68,
    this.iconSize = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onHoldStart(),
      onPointerUp: (_) => onHoldCancel(),
      onPointerCancel: (_) => onHoldCancel(),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
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
              child: Center(
                child: Icon(Icons.stop_rounded,
                    size: iconSize, color: Colors.white),
              ),
            ),
            if (progress > 0)
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 4,
                  color: Colors.white,
                  backgroundColor: Colors.transparent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatAgo(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 60) {
    return diff.inMinutes <= 1 ? 'Just now' : '${diff.inMinutes} min ago';
  }
  if (diff.inHours < 24) {
    return diff.inHours == 1 ? '1 hour ago' : '${diff.inHours} hours ago';
  }
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  if (diff.inDays < 30) {
    final weeks = (diff.inDays / 7).floor();
    return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
  }
  final months = (diff.inDays / 30).floor();
  return months == 1 ? '1 month ago' : '$months months ago';
}

String _formatKm(double metres) => (metres / 1000).toStringAsFixed(2);

String _formatPace(Duration duration, double metres) {
  if (metres < 10) return '--:--';
  final secondsPerKm = duration.inSeconds / (metres / 1000);
  final m = secondsPerKm ~/ 60;
  final s = (secondsPerKm % 60).round();
  return '$m:${s.toString().padLeft(2, '0')}';
}

class _LastRunCard extends StatelessWidget {
  final cm.Run run;
  const _LastRunCard({required this.run});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          if (run.track.length >= 2)
            SizedBox(
              width: 72,
              height: 56,
              child: CustomPaint(
                painter: _TrackSparkPainter(
                  track: run.track,
                  color: theme.colorScheme.primary,
                ),
              ),
            )
          else
            Container(
              width: 72,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.directions_run,
                color: theme.colorScheme.primary.withOpacity(0.6),
              ),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Last ${run.distanceMetres < 50 ? "activity" : "run"}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatAgo(run.startedAt),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _metricPill(
                      theme,
                      '${_formatKm(run.distanceMetres)} km',
                    ),
                    const SizedBox(width: 6),
                    _metricPill(
                      theme,
                      '${_formatPace(run.duration, run.distanceMetres)} /km',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricPill(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RoutePreviewCard extends StatelessWidget {
  final cm.Route route;
  const _RoutePreviewCard({required this.route});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 56,
            child: route.waypoints.length >= 2
                ? CustomPaint(
                    painter: _TrackSparkPainter(
                      track: route.waypoints,
                      color: theme.colorScheme.secondary,
                    ),
                  )
                : Icon(Icons.route, color: theme.colorScheme.secondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'FOLLOWING',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  route.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.straighten,
                      size: 14,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_formatKm(route.distanceMetres)} km',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (route.elevationGainMetres > 0) ...[
                      const SizedBox(width: 12),
                      Icon(
                        Icons.terrain,
                        size: 14,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${route.elevationGainMetres.round()} m',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FirstRunPrompt extends StatelessWidget {
  final ThemeData theme;
  const _FirstRunPrompt({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.rocket_launch, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your first run is one tap away.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scales a waypoint list to fit a small rect and paints a rounded polyline.
/// Cheap — used for last-run and route-preview cards on the Run tab idle view.
class _TrackSparkPainter extends CustomPainter {
  final List<cm.Waypoint> track;
  final Color color;

  _TrackSparkPainter({required this.track, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (track.length < 2) return;
    double minLat = track.first.lat, maxLat = track.first.lat;
    double minLng = track.first.lng, maxLng = track.first.lng;
    for (final w in track) {
      if (w.lat < minLat) minLat = w.lat;
      if (w.lat > maxLat) maxLat = w.lat;
      if (w.lng < minLng) minLng = w.lng;
      if (w.lng > maxLng) maxLng = w.lng;
    }
    final dLat = (maxLat - minLat).abs();
    final dLng = (maxLng - minLng).abs();
    if (dLat == 0 && dLng == 0) return;

    const pad = 4.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    final scale = dLat == 0
        ? w / dLng
        : dLng == 0
            ? h / dLat
            : (w / dLng < h / dLat ? w / dLng : h / dLat);
    final xOff = pad + (w - dLng * scale) / 2;
    final yOff = pad + (h - dLat * scale) / 2;

    final path = Path();
    for (int i = 0; i < track.length; i++) {
      final x = xOff + (track[i].lng - minLng) * scale;
      final y = yOff + (maxLat - track[i].lat) * scale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final bg = Paint()
      ..color = color.withOpacity(0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(10),
      ),
      bg,
    );

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _TrackSparkPainter old) =>
      old.track != track || old.color != color;
}

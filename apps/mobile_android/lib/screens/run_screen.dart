import 'dart:async';
import 'dart:ui';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:run_recorder/run_recorder.dart';

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

  const RunScreen({
    super.key,
    this.apiClient,
    required this.runStore,
    required this.routeStore,
    required this.preferences,
    required this.audioCues,
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

  // Auto-pause
  Timer? _autoPauseCheckTimer;
  DateTime? _lastMovementAt;
  bool _autoPaused = false;

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
        if (_autoPaused) setState(() => _autoPaused = false);
      }

      setState(() {
        _elapsed = snapshot.elapsed;
        _distanceMetres = snapshot.distanceMetres;
        _pace = snapshot.currentPaceSecondsPerKm;
        _track = snapshot.track;
      });

      // Distance tick notification + audio cue
      final currentTick = UnitFormat.distanceTicks(_distanceMetres, unit);
      if (currentTick > _lastTickNotified && currentTick > 0) {
        _lastTickNotified = currentTick;
        final paceLabel = UnitFormat.paceLabel(unit);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$currentTick ${UnitFormat.distanceLabel(unit)} — '
                  '${UnitFormat.pace(_pace, unit)} $paceLabel'),
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
          );
        }
      }
    });
    _recorder!.start();

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
        setState(() => _autoPaused = true);
      }
    });

    if (widget.preferences.audioCues) widget.audioCues.announceStart();

    setState(() => _state = _ScreenState.recording);
  }

  Future<void> _stop() async {
    final run = await _recorder!.stop();
    _snapshotSub?.cancel();
    _stepSub?.cancel();
    _autoPauseCheckTimer?.cancel();

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

  void _discard() {
    _recorder?.dispose();
    _recorder = null;
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

  String get _formattedCalories {
    final cals = (70 * _distanceMetres / 1000).round();
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
                child: Icon(Icons.directions_run,
                    size: 48, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 24),
              Text(
                'Ready to Run',
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
        LiveRunMap(track: _track),
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
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _StatsOverlay(
            time: _formattedTime,
            distanceValue: _formattedDistanceValue,
            distanceUnit: UnitFormat.distanceLabel(_unit),
            pace: _formattedPaceValue,
            paceUnit: UnitFormat.paceLabel(_unit),
            avgPace: _formattedAvgPaceValue,
            calories: _formattedCalories,
            elevation: _formattedElevation,
            steps: '$_steps',
            cadence: '$_cadence',
            onStop: _stop,
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
                        label: 'Pace',
                        value: _formattedAvgPaceValue,
                        unit: UnitFormat.paceLabel(_unit),
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
  final String pace;
  final String paceUnit;
  final String avgPace;
  final String calories;
  final String elevation;
  final String steps;
  final String cadence;
  final VoidCallback onStop;

  const _StatsOverlay({
    required this.time,
    required this.distanceValue,
    required this.distanceUnit,
    required this.pace,
    required this.paceUnit,
    required this.avgPace,
    required this.calories,
    required this.elevation,
    required this.steps,
    required this.cadence,
    required this.onStop,
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
                  Expanded(child: _StatColumn(label: 'Pace', value: pace, unit: paceUnit)),
                  _divider(theme),
                  Expanded(child: _StatColumn(label: 'Avg Pace', value: avgPace, unit: paceUnit)),
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

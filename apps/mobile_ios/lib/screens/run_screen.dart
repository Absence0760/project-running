import 'dart:async';
import 'dart:ui';

import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:run_recorder/run_recorder.dart';
import 'package:uuid/uuid.dart';

import '../local_run_store.dart';
import '../preferences.dart';

/// Main run recording screen wired to RunRecorder for background GPS.
///
/// State machine: idle → countdown → recording → paused → finished.
/// Saves the completed run to [LocalRunStore] on stop.
class RunScreen extends StatefulWidget {
  final LocalRunStore runStore;
  final Preferences preferences;

  const RunScreen({
    super.key,
    required this.runStore,
    required this.preferences,
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

  // Live stats
  Duration _elapsed = Duration.zero;
  double _distanceMetres = 0;
  double? _paceSecPerKm;
  List<cm.Waypoint> _track = [];

  // Incremental crash-safe persistence
  static const _incrementalSaveInterval = Duration(seconds: 10);
  static const _uuid = Uuid();
  Timer? _incrementalSaveTimer;
  String? _runId;
  DateTime? _runStartedAt;

  // Reentrancy guard
  bool _startRequested = false;

  // Finished run
  cm.Run? _finishedRun;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _incrementalSaveTimer?.cancel();
    _snapshotSub?.cancel();
    _recorder?.dispose();
    super.dispose();
  }

  Future<void> _requestStart() async {
    if (_startRequested) return;
    _startRequested = true;

    _runId = _uuid.v4();
    _runStartedAt = DateTime.now();

    setState(() {
      _state = _ScreenState.countdown;
      _countdownValue = 3;
    });

    final recorder = RunRecorder();
    _recorder = recorder;

    // Prepare GPS during countdown so the first fix arrives before we begin.
    try {
      await recorder.prepare();
    } catch (e) {
      debugPrint('RunScreen: GPS prepare failed — $e');
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final next = _countdownValue - 1;
      if (next <= 0) {
        t.cancel();
        _begin(recorder);
      } else {
        setState(() => _countdownValue = next);
      }
    });

    _startRequested = false;
  }

  void _begin(RunRecorder recorder) {
    recorder.begin();

    _snapshotSub = recorder.snapshots.listen((snap) {
      setState(() {
        _elapsed = snap.elapsed;
        _distanceMetres = snap.distanceMetres;
        _paceSecPerKm = snap.currentPaceSecondsPerKm;
        _track = List<cm.Waypoint>.from(snap.track);
      });
    });

    _incrementalSaveTimer = Timer.periodic(_incrementalSaveInterval, (_) {
      _saveInProgress();
    });

    setState(() => _state = _ScreenState.recording);
  }

  void _saveInProgress() {
    final id = _runId;
    final startedAt = _runStartedAt;
    if (id == null || startedAt == null) return;
    final run = cm.Run(
      id: id,
      startedAt: startedAt,
      duration: _elapsed,
      distanceMetres: _distanceMetres,
      track: List<cm.Waypoint>.from(_track),
      source: cm.RunSource.app,
    );
    widget.runStore.saveInProgress(run).catchError((Object e) {
      debugPrint('RunScreen: incremental save failed — $e');
    });
  }

  void _pause() {
    _recorder?.pause();
    setState(() => _state = _ScreenState.paused);
  }

  void _resume() {
    _recorder?.resume();
    setState(() => _state = _ScreenState.recording);
  }

  Future<void> _stop() async {
    _countdownTimer?.cancel();
    _incrementalSaveTimer?.cancel();
    _snapshotSub?.cancel();
    _snapshotSub = null;

    final id = _runId ?? _uuid.v4();
    final startedAt = _runStartedAt ?? DateTime.now();
    final run = cm.Run(
      id: id,
      startedAt: startedAt,
      duration: _elapsed,
      distanceMetres: _distanceMetres,
      track: List<cm.Waypoint>.from(_track),
      source: cm.RunSource.app,
    );

    try {
      await widget.runStore.save(run);
    } catch (e) {
      debugPrint('RunScreen: save failed — $e');
    }

    try {
      await widget.runStore.clearInProgress();
    } catch (e) {
      debugPrint('RunScreen: clearInProgress failed — $e');
    }

    _recorder?.dispose();
    _recorder = null;

    setState(() {
      _finishedRun = run;
      _state = _ScreenState.finished;
    });
  }

  void _discard() {
    _countdownTimer?.cancel();
    _incrementalSaveTimer?.cancel();
    _snapshotSub?.cancel();
    _snapshotSub = null;
    _recorder?.dispose();
    _recorder = null;
    widget.runStore.clearInProgress().catchError((Object e) {
      debugPrint('RunScreen: clearInProgress on discard failed — $e');
    });
    setState(() {
      _state = _ScreenState.idle;
      _elapsed = Duration.zero;
      _distanceMetres = 0;
      _paceSecPerKm = null;
      _track = [];
      _finishedRun = null;
      _runId = null;
      _runStartedAt = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      _ScreenState.idle => _buildIdle(),
      _ScreenState.countdown => _buildCountdown(),
      _ScreenState.recording => _buildRecording(),
      _ScreenState.paused => _buildPaused(),
      _ScreenState.finished => _buildFinished(),
    };
  }

  Widget _buildIdle() {
    return Scaffold(
      appBar: AppBar(title: const Text('Run')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: FilledButton(
                onPressed: _requestStart,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: Colors.green,
                ),
                child: const Text(
                  'Start',
                  style: TextStyle(fontSize: 24, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdown() {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Get ready')),
      body: Center(
        child: Text(
          '$_countdownValue',
          style: theme.textTheme.displayLarge?.copyWith(
            fontSize: 120,
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget _buildRecording() {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    return Scaffold(
      appBar: AppBar(title: const Text('Running')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _formatElapsed(_elapsed),
              style: theme.textTheme.displayLarge?.copyWith(
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatColumn(
                  label: 'Distance',
                  value: _formatDistance(_distanceMetres, unit),
                ),
                _StatColumn(
                  label: 'Pace',
                  value: _formatPace(_paceSecPerKm, unit),
                ),
              ],
            ),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(
                  onPressed: _pause,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                  ),
                  child: const Text('Pause'),
                ),
                FilledButton(
                  onPressed: _stop,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                  ),
                  child: const Text('Stop'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaused() {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    return Scaffold(
      appBar: AppBar(title: const Text('Paused')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _formatElapsed(_elapsed),
              style: theme.textTheme.displayLarge?.copyWith(
                color: theme.colorScheme.outline,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatColumn(
                  label: 'Distance',
                  value: _formatDistance(_distanceMetres, unit),
                ),
                _StatColumn(
                  label: 'Pace',
                  value: _formatPace(_paceSecPerKm, unit),
                ),
              ],
            ),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(
                  onPressed: _discard,
                  child: const Text('Discard'),
                ),
                FilledButton(
                  onPressed: _resume,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                  ),
                  child: const Text('Resume'),
                ),
                FilledButton(
                  onPressed: _stop,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                  ),
                  child: const Text('Stop'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinished() {
    final theme = Theme.of(context);
    final run = _finishedRun;
    final unit = widget.preferences.unit;
    return Scaffold(
      appBar: AppBar(title: const Text('Run complete')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            Text('Run saved', style: theme.textTheme.headlineSmall),
            if (run != null) ...[
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _StatColumn(
                    label: 'Time',
                    value: _formatElapsed(run.duration),
                  ),
                  _StatColumn(
                    label: 'Distance',
                    value: _formatDistance(run.distanceMetres, unit),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 48),
            FilledButton(
              onPressed: _discard,
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

String _formatElapsed(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String _formatDistance(double metres, DistanceUnit unit) {
  return UnitFormat.distance(metres, unit);
}

String _formatPace(double? secPerKm, DistanceUnit unit) {
  return UnitFormat.pace(secPerKm, unit);
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:run_recorder/run_recorder.dart';

/// Main run recording screen with GPS tracking, live stats, and sync.
class RunScreen extends StatefulWidget {
  final ApiClient apiClient;
  const RunScreen({super.key, required this.apiClient});

  @override
  State<RunScreen> createState() => _RunScreenState();
}

enum _ScreenState { idle, recording, finished }

class _RunScreenState extends State<RunScreen> {
  _ScreenState _state = _ScreenState.idle;
  RunRecorder? _recorder;
  StreamSubscription<RunSnapshot>? _snapshotSub;

  // Live stats
  Duration _elapsed = Duration.zero;
  double _distanceMetres = 0;
  double? _pace;
  int _trackPoints = 0;

  // Finished run
  Run? _finishedRun;
  bool _syncing = false;
  bool _synced = false;
  String? _syncError;

  void _start() {
    _recorder = RunRecorder();
    _snapshotSub = _recorder!.snapshots.listen((snapshot) {
      setState(() {
        _elapsed = snapshot.elapsed;
        _distanceMetres = snapshot.distanceMetres;
        _pace = snapshot.currentPaceSecondsPerKm;
        _trackPoints++;
      });
    });
    _recorder!.start();
    setState(() => _state = _ScreenState.recording);
  }

  Future<void> _stop() async {
    final run = await _recorder!.stop();
    _snapshotSub?.cancel();
    setState(() {
      _finishedRun = run;
      _state = _ScreenState.finished;
    });
  }

  Future<void> _sync() async {
    if (_finishedRun == null) return;
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      await widget.apiClient.saveRun(_finishedRun!);
      setState(() {
        _syncing = false;
        _synced = true;
      });
    } catch (e) {
      setState(() {
        _syncing = false;
        _syncError = e.toString();
      });
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
      _trackPoints = 0;
      _finishedRun = null;
      _syncing = false;
      _synced = false;
      _syncError = null;
    });
  }

  String get _formattedTime {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes % 60;
    final s = _elapsed.inSeconds % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _formattedDistance =>
      '${(_distanceMetres / 1000).toStringAsFixed(2)} km';

  String get _formattedPace {
    if (_pace == null || _pace! <= 0) return '--:-- /km';
    final m = _pace! ~/ 60;
    final s = (_pace! % 60).toInt();
    return '$m:${s.toString().padLeft(2, '0')} /km';
  }

  @override
  void dispose() {
    _snapshotSub?.cancel();
    _recorder?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Run')),
      body: Center(
        child: switch (_state) {
          _ScreenState.idle => _buildIdle(theme),
          _ScreenState.recording => _buildRecording(theme),
          _ScreenState.finished => _buildFinished(theme),
        },
      ),
    );
  }

  Widget _buildIdle(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.directions_run, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        Text('Ready to Run', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 48),
        SizedBox(
          width: 120,
          height: 120,
          child: FilledButton(
            onPressed: _start,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              backgroundColor: Colors.green,
            ),
            child: const Text('Start', style: TextStyle(fontSize: 24, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildRecording(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _formattedTime,
          style: theme.textTheme.displayLarge?.copyWith(
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _StatColumn(label: 'Distance', value: _formattedDistance),
            _StatColumn(label: 'Pace', value: _formattedPace),
          ],
        ),
        const SizedBox(height: 8),
        Text('$_trackPoints GPS points',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            )),
        const SizedBox(height: 48),
        SizedBox(
          width: 120,
          height: 120,
          child: FilledButton(
            onPressed: _stop,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              backgroundColor: theme.colorScheme.error,
            ),
            child: const Text('Stop', style: TextStyle(fontSize: 24, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildFinished(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('Run Complete', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatColumn(label: 'Distance', value: _formattedDistance),
              _StatColumn(label: 'Time', value: _formattedTime),
              _StatColumn(label: 'Pace', value: _formattedPace),
            ],
          ),
          const SizedBox(height: 8),
          Text('${_finishedRun?.track.length ?? 0} GPS points recorded',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 32),
          if (_synced) ...[
            const Icon(Icons.cloud_done, color: Colors.green, size: 48),
            const SizedBox(height: 8),
            const Text('Synced'),
            const SizedBox(height: 16),
            FilledButton(onPressed: _discard, child: const Text('Done')),
          ] else ...[
            if (_syncError != null) ...[
              Text(_syncError!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: _syncing ? null : _sync,
              icon: _syncing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload),
              label: Text(_syncing ? 'Syncing...' : 'Sync Run'),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _discard, child: const Text('Discard')),
          ],
        ],
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

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:run_recorder/run_recorder.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'heart_rate_service.dart';
import 'local_run_store.dart';

enum _Stage { preRun, running, postRun }

class RunWatchScreen extends StatefulWidget {
  final ApiClient apiClient;
  final LocalRunStore runStore;

  const RunWatchScreen({
    super.key,
    required this.apiClient,
    required this.runStore,
  });

  @override
  State<RunWatchScreen> createState() => _RunWatchScreenState();
}

class _RunWatchScreenState extends State<RunWatchScreen> {
  _Stage _stage = _Stage.preRun;
  final RunRecorder _recorder = RunRecorder();
  final HeartRateService _hr = HeartRateService();
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<RunSnapshot>? _snapshotSub;
  StreamSubscription<int>? _hrSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  RunSnapshot? _snapshot;
  Run? _finishedRun;
  int? _currentBPM;
  final List<int> _bpmSamples = [];

  bool _syncing = false;
  String? _syncError;
  bool _authed = false;

  @override
  void initState() {
    super.initState();
    _ensureAuth();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        _drainQueue();
      }
    });
  }

  Future<void> _ensureAuth() async {
    if (widget.apiClient.userId != null) {
      setState(() => _authed = true);
      _drainQueue();
      return;
    }
    try {
      await widget.apiClient.signIn(
        email: 'runner@test.com',
        password: 'testtest',
      );
      if (!mounted) return;
      setState(() => _authed = true);
      _drainQueue();
    } catch (_) {
      if (mounted) setState(() => _authed = false);
    }
  }

  /// Try to push every run currently in the store. Called on app start, on
  /// connectivity change, and after a recording finishes. Runs that fail
  /// (offline, transient server error) stay queued for the next trigger.
  Future<void> _drainQueue() async {
    if (!_authed) return;
    for (final run in List<Run>.from(widget.runStore.unsynced)) {
      try {
        await widget.apiClient.saveRun(run);
        await widget.runStore.remove(run.id);
      } catch (_) {
        // Leave queued; next trigger retries.
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    try {
      await _recorder.prepare();
      _recorder.begin();
      _snapshotSub = _recorder.snapshots.listen((s) {
        if (mounted) setState(() => _snapshot = s);
      });
      await _hr.start();
      _hrSub = _hr.bpm.listen((bpm) {
        _bpmSamples.add(bpm);
        if (mounted) setState(() => _currentBPM = bpm);
      });
      await WakelockPlus.enable();
      setState(() {
        _stage = _Stage.running;
        _currentBPM = null;
        _bpmSamples.clear();
        _syncError = null;
      });
    } catch (e) {
      setState(() => _syncError = e.toString());
    }
  }

  Future<void> _stop() async {
    await _hr.stop();
    await _hrSub?.cancel();
    _hrSub = null;

    final baseRun = await _recorder.stop();
    await _snapshotSub?.cancel();
    _snapshotSub = null;
    await WakelockPlus.disable();

    // Fold HR average into metadata alongside whatever `run_recorder` put
    // there (e.g. `laps`).
    final run = _bpmSamples.isEmpty
        ? baseRun
        : Run(
            id: baseRun.id,
            startedAt: baseRun.startedAt,
            duration: baseRun.duration,
            distanceMetres: baseRun.distanceMetres,
            track: baseRun.track,
            routeId: baseRun.routeId,
            source: baseRun.source,
            externalId: baseRun.externalId,
            metadata: {
              ...?baseRun.metadata,
              'avg_bpm': _bpmSamples.reduce((a, b) => a + b) / _bpmSamples.length,
            },
            createdAt: baseRun.createdAt,
          );

    await widget.runStore.save(run);
    if (!mounted) return;
    setState(() {
      _finishedRun = run;
      _stage = _Stage.postRun;
    });
    // Opportunistic push — succeeds silently if online, leaves run queued if not.
    _drainQueue();
  }

  Future<void> _sync() async {
    final run = _finishedRun;
    if (run == null) return;
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      await widget.apiClient.saveRun(run);
      await widget.runStore.remove(run.id);
      if (mounted) setState(() => _syncing = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncError = e.toString();
        });
      }
    }
  }

  void _startNextRun() {
    setState(() {
      _finishedRun = null;
      _snapshot = null;
      _currentBPM = null;
      _bpmSamples.clear();
      _syncError = null;
      _stage = _Stage.preRun;
    });
  }

  Future<void> _discard() async {
    final id = _finishedRun?.id;
    if (id != null) await widget.runStore.remove(id);
    if (mounted) _startNextRun();
  }

  @override
  void dispose() {
    _snapshotSub?.cancel();
    _hrSub?.cancel();
    _connectivitySub?.cancel();
    _hr.stop();
    _recorder.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentRunSynced = _finishedRun != null &&
        !widget.runStore.contains(_finishedRun!.id);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: switch (_stage) {
            _Stage.preRun => _PreRun(
                onStart: _start,
                unsyncedCount: widget.runStore.unsyncedCount,
                authed: _authed,
              ),
            _Stage.running => _Running(
                snapshot: _snapshot,
                currentBPM: _currentBPM,
                onStop: _stop,
              ),
            _Stage.postRun => _PostRun(
                run: _finishedRun,
                syncing: _syncing,
                syncError: _syncError,
                synced: currentRunSynced,
                onSync: _sync,
                onStartNext: _startNextRun,
                onDiscard: _discard,
              ),
          },
        ),
      ),
    );
  }
}

// ----- Sub-views -----

class _PreRun extends StatelessWidget {
  final VoidCallback onStart;
  final int unsyncedCount;
  final bool authed;

  const _PreRun({
    required this.onStart,
    required this.unsyncedCount,
    required this.authed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Ready to Run', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 6),
        if (unsyncedCount > 0)
          Text(
            '$unsyncedCount run${unsyncedCount == 1 ? '' : 's'} to sync',
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        if (!authed)
          const Text(
            'Offline',
            style: TextStyle(fontSize: 11, color: Colors.orange),
          ),
        const SizedBox(height: 12),
        FilledButton(onPressed: onStart, child: const Text('Start')),
      ],
    );
  }
}

class _Running extends StatelessWidget {
  final RunSnapshot? snapshot;
  final int? currentBPM;
  final VoidCallback onStop;

  const _Running({
    required this.snapshot,
    required this.currentBPM,
    required this.onStop,
  });

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatPace(double? secondsPerKm) {
    if (secondsPerKm == null || secondsPerKm <= 0) return '--:--';
    final m = (secondsPerKm / 60).floor();
    final s = (secondsPerKm % 60).round();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          s == null ? '00:00' : _formatElapsed(s.elapsed),
          style: const TextStyle(
            fontSize: 28,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          s == null ? '0.00 km' : '${(s.distanceMetres / 1000).toStringAsFixed(2)} km',
          style: const TextStyle(fontSize: 14),
        ),
        Text(
          s == null ? '--:-- /km' : '${_formatPace(s.currentPaceSecondsPerKm)} /km',
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
        Text(
          currentBPM == null ? '— bpm' : '$currentBPM bpm',
          style: const TextStyle(fontSize: 11, color: Colors.redAccent),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(onPressed: onStop, child: const Text('Stop')),
      ],
    );
  }
}

class _PostRun extends StatelessWidget {
  final Run? run;
  final bool syncing;
  final String? syncError;
  final bool synced;
  final VoidCallback onSync;
  final VoidCallback onStartNext;
  final VoidCallback onDiscard;

  const _PostRun({
    required this.run,
    required this.syncing,
    required this.syncError,
    required this.synced,
    required this.onSync,
    required this.onStartNext,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final r = run;
    final avgBpm = r?.metadata?['avg_bpm'];
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Run Complete', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 6),
          if (r != null) ...[
            Text(
              '${(r.distanceMetres / 1000).toStringAsFixed(2)} km',
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              '${r.duration.inMinutes}m ${r.duration.inSeconds % 60}s',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
            if (avgBpm is num)
              Text(
                '${avgBpm.round()} bpm avg',
                style: const TextStyle(fontSize: 11, color: Colors.redAccent),
              ),
          ],
          const SizedBox(height: 8),
          if (syncError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                syncError!,
                style: const TextStyle(fontSize: 10, color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
            ),
          if (synced) ...[
            const Text('Synced', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            FilledButton(onPressed: onStartNext, child: const Text('Done')),
          ] else ...[
            FilledButton(
              onPressed: syncing ? null : onSync,
              child: syncing
                  ? const SizedBox(
                      height: 12,
                      width: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sync'),
            ),
            TextButton(
              onPressed: onStartNext,
              child: const Text('Start next run',
                  style: TextStyle(fontSize: 11)),
            ),
            TextButton(
              onPressed: onDiscard,
              child: const Text('Discard',
                  style: TextStyle(fontSize: 11, color: Colors.redAccent)),
            ),
          ],
        ],
      ),
    );
  }
}

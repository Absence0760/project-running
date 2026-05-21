import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'local_run_store.dart';

/// Pushes unsynced runs to the backend whenever:
///
/// 1. Connectivity changes from offline to online (e.g. wifi reconnects)
/// 2. The app comes back to the foreground
/// 3. The user is signed in and there are unsynced runs
///
/// Sync attempts are silent and best-effort — failures are logged but don't
/// surface to the UI. The user can still trigger an explicit sync from the
/// Runs screen.
///
/// After a failure the service enters an exponential backoff window (60 s,
/// 2 min, 4 min, … capped at 30 min) so a flaky upstream doesn't see N×
/// the request volume on every connectivity flap. The 'manual' reason
/// bypasses backoff so a user-initiated retry from the Runs screen always
/// fires. A successful cycle resets the counter.
class SyncService with WidgetsBindingObserver {
  final ApiClient? apiClient;
  final LocalRunStore runStore;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _syncing = false;

  DateTime? _lastFailureAt;
  int _consecutiveFailures = 0;

  static const Duration _baseBackoff = Duration(seconds: 60);
  static const Duration _maxBackoff = Duration(minutes: 30);

  SyncService({required this.apiClient, required this.runStore});

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = Connectivity().onConnectivityChanged.listen(_onConnectivity);
    _trySync('startup');
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _trySync('foreground');
    }
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    final online = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
    if (online) _trySync('connectivity');
  }

  /// Test-only: drives the same code path the connectivity / lifecycle
  /// observers do. Lets unit tests exercise the sync loop without the
  /// `WidgetsBindingObserver` subscription.
  @visibleForTesting
  Future<void> debugTrySync(String reason) => _trySync(reason);

  /// Test-only: drives the connectivity branch directly without the
  /// `Connectivity().onConnectivityChanged` stream subscription.
  /// Production calls land here via [_onConnectivity].
  @visibleForTesting
  void debugOnConnectivity(List<ConnectivityResult> results) =>
      _onConnectivity(results);

  /// Test-only: read the current backoff state for assertions.
  @visibleForTesting
  ({int failures, DateTime? lastFailureAt, Duration backoff}) debugBackoffState() =>
      (
        failures: _consecutiveFailures,
        lastFailureAt: _lastFailureAt,
        backoff: _currentBackoff(),
      );

  /// Test-only: zero the backoff window without touching anything else.
  @visibleForTesting
  void debugClearBackoff() {
    _lastFailureAt = null;
    _consecutiveFailures = 0;
  }

  Duration _currentBackoff() {
    if (_consecutiveFailures == 0) return Duration.zero;
    final shift = _consecutiveFailures - 1;
    // Cap the shift before it overflows 32-bit ints (1 << 30 ≈ 1.1 G secs);
    // the _maxBackoff clamp below would catch it anyway, but the explicit
    // ceiling keeps the math obvious.
    final cappedShift = shift.clamp(0, 20);
    final secs = _baseBackoff.inSeconds * (1 << cappedShift);
    return Duration(
      seconds: secs.clamp(0, _maxBackoff.inSeconds).toInt(),
    );
  }

  bool _isInBackoff() {
    final last = _lastFailureAt;
    if (last == null || _consecutiveFailures == 0) return false;
    return DateTime.now().isBefore(last.add(_currentBackoff()));
  }

  void _onCycleSuccess() {
    _lastFailureAt = null;
    _consecutiveFailures = 0;
  }

  void _onCycleFailure() {
    _consecutiveFailures += 1;
    _lastFailureAt = DateTime.now();
    debugPrint(
      'SyncService: backoff active for ${_currentBackoff().inSeconds}s '
      '(failure #$_consecutiveFailures)',
    );
  }

  Future<void> _trySync(String reason) async {
    if (_syncing) return;
    if (reason != 'manual' && _isInBackoff()) {
      debugPrint('SyncService: in backoff, skipping ($reason)');
      return;
    }
    final api = apiClient;
    if (api == null || api.userId == null) return;
    final unsynced = runStore.unsyncedRuns;
    final hasPendingDeletes = runStore.pendingRemoteDeleteIds.isNotEmpty;
    if (unsynced.isEmpty && !hasPendingDeletes) return;

    _syncing = true;
    var anyFailure = false;
    try {
      if (unsynced.isNotEmpty) {
        debugPrint('SyncService: pushing ${unsynced.length} runs ($reason)');
        try {
          final failed = await api.saveRunsBatch(unsynced);
          // Mark only the runs whose track upload succeeded — the
          // failed-track set comes back from saveRunsBatch so a single
          // corrupted run no longer blocks the rest of the queue.
          // (The full batch-throw path stays for catastrophic
          // failures like an auth error — we land in the catch below.)
          final succeededIds = unsynced
              .where((r) => !failed.contains(r.id))
              .map((r) => r.id);
          await runStore.markManySynced(succeededIds);
          debugPrint(
            'SyncService: pushed ${unsynced.length - failed.length} '
            '(skipped ${failed.length} on track-upload failure)',
          );
          if (failed.isNotEmpty) anyFailure = true;
        } catch (e) {
          debugPrint('SyncService: batch push failed ($reason): $e');
          anyFailure = true;
        }
      }
      if (hasPendingDeletes) {
        final ok = await _drainPendingDeletes(reason);
        if (!ok) anyFailure = true;
      }
    } finally {
      _syncing = false;
      if (anyFailure) {
        _onCycleFailure();
      } else {
        _onCycleSuccess();
      }
    }
  }

  /// Retry remote-side deletes that failed on first attempt (e.g. the
  /// user batch-deleted runs while offline). Each id is attempted
  /// independently so one persistent failure (e.g. an RLS rejection
  /// on a malformed id) doesn't poison the rest of the queue. On
  /// success the local copy is also removed — runs_screen kept it
  /// around precisely so the local list stayed consistent with the
  /// cloud, and now that the cloud row is gone the local row should
  /// follow.
  ///
  /// Returns `true` iff every pending id was drained without error.
  Future<bool> _drainPendingDeletes(String reason) async {
    final api = apiClient;
    if (api == null) return true;
    final ids = runStore.pendingRemoteDeleteIds.toList();
    if (ids.isEmpty) return true;
    debugPrint(
      'SyncService: retrying ${ids.length} pending remote deletes ($reason)',
    );
    var ok = 0;
    var failed = 0;
    for (final id in ids) {
      try {
        await api.deleteRunById(id);
        await runStore.delete(id);
        await runStore.clearPendingRemoteDelete(id);
        ok++;
      } catch (e) {
        debugPrint('SyncService: retry delete failed for $id: $e');
        failed++;
      }
    }
    debugPrint('SyncService: drained $ok / ${ids.length} pending deletes');
    return failed == 0;
  }
}

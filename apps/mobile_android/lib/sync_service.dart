import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'local_route_store.dart';
import 'local_run_store.dart';
import 'social_service.dart';

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
  /// Optional — when provided, the sync cycle also drains unsynced
  /// routes (created offline / while signed out via the in-app route
  /// builder). When null, route drain is a no-op so older callers
  /// that don't wire a route store don't blow up.
  final LocalRouteStore? routeStore;
  /// Optional — when provided, a successful run push fires an opportunistic
  /// challenge-completion recompute for the just-synced runs (the offline-first
  /// mobile analogue of web's on-save fan-out). When null, the daily cron sweep
  /// remains the only completion path.
  final SocialService? socialService;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _syncing = false;

  DateTime? _lastFailureAt;
  int _consecutiveFailures = 0;

  static const Duration _baseBackoff = Duration(seconds: 60);
  static const Duration _maxBackoff = Duration(minutes: 30);

  /// Reasons that bypass the in-backoff guard in [_trySync].
  ///
  /// - `manual` — explicit user tap on the runs-screen "Sync all" button.
  /// - `signin` — a fresh auth session is a strong signal that any
  ///   prior auth-rejection backoff is stale (the session that produced
  ///   the 401 is gone). Without this, a user who signs out, the queue
  ///   piles up, they sign back in, the next automatic trigger is
  ///   silently skipped for 30 min because the backoff window from the
  ///   signed-out cycle is still ticking — and their freshly-recorded
  ///   offline run sits unsynced until the user backgrounds + foregrounds
  ///   the app or manually taps "Sync all".
  static const _backoffBypassReasons = <String>{'manual', 'signin'};

  SyncService({
    required this.apiClient,
    required this.runStore,
    this.routeStore,
    this.socialService,
  });

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = Connectivity().onConnectivityChanged.listen(_onConnectivity);
    _fireSync('startup');
  }

  /// The cycle a fire-and-forget trigger started, until it finishes.
  ///
  /// [start] and [didChangeAppLifecycleState] cannot await a cycle — an
  /// observer callback returns `void` — but discarding the future left
  /// NOTHING able to know when one had finished, and a cycle outlives the
  /// call that started it by however long its store writes take. Holding it
  /// is what lets a caller (today, a test whose teardown deletes the store
  /// directory the cycle is still writing into) wait for the real thing
  /// rather than for a proxy that happens to be fast enough.
  Future<void>? _inFlight;

  @visibleForTesting
  Future<void>? get debugInFlightSync => _inFlight;

  void _fireSync(String reason) {
    final cycle = _trySync(reason);
    _inFlight = cycle;
    cycle.whenComplete(() {
      if (identical(_inFlight, cycle)) _inFlight = null;
    });
  }

  /// Public entry point for callers that need to drive a sync from a
  /// known event (auth state change, post-import save, recovery
  /// promotion). [reason] is a short tag used for log lines and to
  /// decide whether to bypass the backoff window (see
  /// [_backoffBypassReasons]).
  Future<void> triggerSync(String reason) => _trySync(reason);

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fireSync('foreground');
    }
  }

  Future<void> _onConnectivity(List<ConnectivityResult> results) async {
    final online = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
    if (online) await _trySync('connectivity');
  }

  /// Test-only: drives the same code path the connectivity / lifecycle
  /// observers do. Lets unit tests exercise the sync loop without the
  /// `WidgetsBindingObserver` subscription.
  @visibleForTesting
  Future<void> debugTrySync(String reason) => _trySync(reason);

  /// Test-only: drives the connectivity branch directly without the
  /// `Connectivity().onConnectivityChanged` stream subscription.
  /// Production calls land here via [_onConnectivity].
  ///
  /// Returns the cycle's future so a caller can await it. A test that
  /// fires this and then pumps the event queue is racing real disk I/O
  /// inside the cycle: while it is still in flight [_trySync]'s
  /// reentrancy guard silently drops the next trigger, so a second
  /// event asserts against one push instead of two.
  @visibleForTesting
  Future<void> debugOnConnectivity(List<ConnectivityResult> results) =>
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
    if (!_backoffBypassReasons.contains(reason) && _isInBackoff()) {
      debugPrint('SyncService: in backoff, skipping ($reason)');
      return;
    }
    final api = apiClient;
    if (api == null || api.userId == null) return;
    final allUnsynced = runStore.unsyncedRuns;
    // Owner-tag filter: skip runs whose `metadata.created_by_user_id`
    // names a different user. Without this, on a shared device where
    // User A records a run, signs out, and User B signs in, User B's
    // sync would try to push A's runs under B's account — RLS would
    // reject every row, the queue would never drain, and B's "X
    // unsynced" badge would be stuck forever. Runs without the tag
    // (legacy, or saved when no provider was wired) adopt to the
    // current user. See `docs/architecture/decisions.md § 67`.
    final unsyncedForOwner = filterRunsForCurrentUser(allUnsynced, api.userId);
    final skippedForeignOwner = allUnsynced.length - unsyncedForOwner.length;
    if (skippedForeignOwner > 0) {
      debugPrint(
        'SyncService: skipping $skippedForeignOwner runs owned by a '
        'different user (signed in as ${api.userId})',
      );
    }
    // Use the per-user view for the early-bail check so a cycle isn't
    // wasted when the only queued deletes are owned by a different
    // user. Without this, on a shared device with User A's queued
    // deletes in the store + User B signed in, every sync trigger
    // would walk into _drainPendingDeletes just to no-op.
    final pendingDeleteIds = runStore.pendingRemoteDeletesForUser(api.userId);
    final hasPendingDeletes = pendingDeleteIds.isNotEmpty;
    // A run queued for deletion is never pushed, even if it was never
    // synced. Without this, a run deleted offline before its first
    // push (never-synced + queued for pending-delete in the same
    // window) gets its full track uploaded — recreating the row the
    // user just asked to delete — and only THEN removed by the delete
    // drain below. If the delete step fails right after (partial-cycle
    // failure), the recreated row is left on the server until a later
    // cycle's drain catches up. See issue #675.
    final unsynced = unsyncedForOwner
        .where((r) => !pendingDeleteIds.contains(r.id))
        .toList();
    final unsyncedRoutes = routeStore?.unsyncedRoutes ?? const [];
    final hasPendingRouteDeletes =
        routeStore?.pendingRemoteDeletesForUser(api.userId).isNotEmpty ??
            false;
    if (unsynced.isEmpty &&
        !hasPendingDeletes &&
        unsyncedRoutes.isEmpty &&
        !hasPendingRouteDeletes) return;

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
          final succeeded =
              unsynced.where((r) => !failed.contains(r.id)).toList();
          await runStore.markManySynced(succeeded);
          debugPrint(
            'SyncService: pushed ${unsynced.length - failed.length} '
            '(skipped ${failed.length} on track-upload failure)',
          );
          if (failed.isNotEmpty) anyFailure = true;
          if (succeeded.isNotEmpty) {
            await socialService
                ?.recomputeChallengesForRuns(succeeded.map((r) => r.startedAt));
          }
        } catch (e) {
          debugPrint('SyncService: batch push failed ($reason): $e');
          anyFailure = true;
        }
      }
      if (hasPendingDeletes) {
        final ok = await drainPendingDeletes(api, runStore, reason: reason);
        if (!ok) anyFailure = true;
      }
      final store = routeStore;
      if (store != null && unsyncedRoutes.isNotEmpty) {
        final ok = await drainUnsyncedRoutes(api, store, reason: reason);
        if (!ok) anyFailure = true;
      }
      if (store != null && hasPendingRouteDeletes) {
        final ok = await drainPendingRouteDeletes(api, store, reason: reason);
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
/// Only deletes owned by the currently-signed-in user are attempted
/// — entries owned by a different user stay in the queue for their
/// rightful owner to drain on their next sync (the parallel of the
/// run owner-tag guard). Untagged entries (legacy / queued-while-
/// signed-out) adopt to the current user.
///
/// Returns `true` iff every pending id was drained without error.
///
/// Shared free function so the foreground [SyncService] and the
/// WorkManager `background_sync.dart#runBackgroundSyncCycle` drain
/// the same queue the same way and can't drift.
Future<bool> drainPendingDeletes(
  ApiClient api,
  LocalRunStore runStore, {
  String reason = 'background',
}) async {
  final ids = runStore.pendingRemoteDeletesForUser(api.userId).toList();
  if (ids.isEmpty) return true;
  debugPrint('Sync: retrying ${ids.length} pending remote deletes ($reason)');
  var ok = 0;
  var failed = 0;
  for (final id in ids) {
    try {
      await api.deleteRunById(id);
      await runStore.delete(id);
      await runStore.clearPendingRemoteDelete(id);
      ok++;
    } catch (e) {
      debugPrint('Sync: retry delete failed for $id: $e');
      failed++;
    }
  }
  debugPrint('Sync: drained $ok / ${ids.length} pending deletes');
  return failed == 0;
}

/// Push routes the user created offline (signed-out, network down,
/// Supabase init failed at app launch) to the cloud. Each route is
/// attempted independently so one bad row (e.g. RLS rejection on a
/// stale club_id) doesn't poison the rest of the queue. Successful
/// pushes are marked synced (and owner-tagged, §67); failures stay
/// unsynced for the next cycle.
///
/// Returns `true` iff every route was drained without error.
///
/// Shared free function so the foreground [SyncService] and the
/// WorkManager `background_sync.dart#runBackgroundSyncCycle` drain
/// the same queue the same way and can't drift.
Future<bool> drainUnsyncedRoutes(
  ApiClient api,
  LocalRouteStore routeStore, {
  String reason = 'background',
}) async {
  // A route queued for deletion is never pushed, even if it was never
  // synced — the routes counterpart of issue #675's run-side guard.
  // Filtered here (inside the shared drain) rather than at each call
  // site so the foreground and background paths can't drift.
  final pendingDeleteIds = routeStore.pendingRemoteDeletesForUser(api.userId);
  final unsyncedRoutes = routeStore.unsyncedRoutes
      .where((r) => !pendingDeleteIds.contains(r.id))
      .toList();
  if (unsyncedRoutes.isEmpty) return true;
  debugPrint(
    'Sync: pushing ${unsyncedRoutes.length} unsynced routes ($reason)',
  );
  var ok = 0;
  var failed = 0;
  final succeededIds = <String>[];
  for (final route in unsyncedRoutes) {
    try {
      await api.saveRoute(route);
      succeededIds.add(route.id);
      ok++;
    } catch (e) {
      debugPrint('Sync: route push failed for ${route.id}: $e');
      failed++;
    }
  }
  if (succeededIds.isNotEmpty) {
    await routeStore.markManyRoutesSynced(succeededIds);
    // Adoption stamp (§67 semantics, issue #229): an untagged
    // (signed-out-built) route that just landed in this account now
    // belongs to it — tag it so it stops rendering for other accounts.
    final uid = api.userId;
    if (uid != null && uid.isNotEmpty) {
      await routeStore.tagRoutesOwner(succeededIds, uid);
    }
  }
  debugPrint(
    'Sync: drained $ok / ${unsyncedRoutes.length} unsynced routes',
  );
  return failed == 0;
}

/// Retry remote-side route deletes that failed on first attempt (e.g.
/// the user batch-deleted routes while offline). Each id is attempted
/// independently so one persistent failure doesn't poison the rest of
/// the queue. On success the local copy is also removed — the routes
/// screen kept it around precisely so the local list stayed consistent
/// with the cloud, and now that the cloud row is gone the local row
/// should follow. Mirrors [drainPendingDeletes] for runs.
///
/// Only deletes owned by the currently-signed-in user are attempted —
/// entries owned by a different user stay in the queue for their
/// rightful owner to drain on their next sync. Untagged entries
/// (legacy / queued-while-signed-out) adopt to the current user.
///
/// Returns `true` iff every pending id was drained without error.
///
/// Shared free function so the foreground [SyncService] and the
/// WorkManager `background_sync.dart#runBackgroundSyncCycle` drain
/// the same queue the same way and can't drift.
Future<bool> drainPendingRouteDeletes(
  ApiClient api,
  LocalRouteStore routeStore, {
  String reason = 'background',
}) async {
  final ids = routeStore.pendingRemoteDeletesForUser(api.userId).toList();
  if (ids.isEmpty) return true;
  debugPrint(
    'Sync: retrying ${ids.length} pending remote route deletes ($reason)',
  );
  var ok = 0;
  var failed = 0;
  for (final id in ids) {
    try {
      await api.deleteRoute(id);
      await routeStore.delete(id);
      await routeStore.clearPendingRemoteDelete(id);
      ok++;
    } catch (e) {
      debugPrint('Sync: retry route delete failed for $id: $e');
      failed++;
    }
  }
  debugPrint('Sync: drained $ok / ${ids.length} pending route deletes');
  return failed == 0;
}

/// Filter [runs] to those the currently-signed-in [userId] can push.
/// Used by both [SyncService._trySync] (foreground sync) and
/// `background_sync.dart#callbackDispatcher` (WorkManager periodic
/// sync) to avoid pushing User A's runs under User B's account on a
/// shared device.
///
/// A run is pushable when:
///
///  * `metadata.created_by_user_id` is **null** or absent — the run
///    was either saved before owner-tagging shipped (legacy) or
///    saved while signed-out. The first signed-in user adopts it.
///  * `metadata.created_by_user_id` **equals** [userId] — the run
///    belongs to this user, push it.
///
/// A run with a `created_by_user_id` that names a different user is
/// dropped from the push set — its rightful owner will see it on
/// the queue when they sign back in. See `docs/architecture/decisions.md § 67`.
///
/// Pure helper — no state, no I/O. Public so background_sync (which
/// runs in its own process and can't reach a SyncService instance)
/// can apply the same guard.
List<Run> filterRunsForCurrentUser(List<Run> runs, String? userId) {
  if (userId == null) return const [];
  return runs.where((r) {
    final owner = r.metadata?['created_by_user_id'];
    if (owner is! String || owner.isEmpty) return true;
    return owner == userId;
  }).toList();
}

/// Why a run's cloud push cannot be retried.
///
/// One member, deliberately. decisions § 986 refused to build a terminal-error
/// taxonomy while the category had no reachable member; § 1009 measured the
/// first one. A second member is earned by measuring a second permanent
/// failure, not by anticipating one.
///
/// The reason is persisted by id in `LocalRunStore`'s `blocked_runs.json`
/// sidecar, so its `name` is an on-disk value: renaming a member orphans the
/// runs already parked under the old spelling, which then read as retryable
/// again.
enum RunPushBlockReason {
  /// The run's gzipped GPS trace is larger than the `runs` bucket will hold.
  /// The same waypoints gzip to the same bytes on every attempt, so the drain
  /// re-sends a payload the server has already refused, forever (§ 1009).
  trackTooLarge,
}

/// The per-run verdict of a batch push.
///
/// Two states, because the drain has exactly two behaviours: try again next
/// cycle, or stop trying. A run named by neither landed.
class RunPushOutcome {
  /// Runs whose push failed in a way a later attempt can succeed at — a lost
  /// connection, a 5xx, an expired token, a corrupt local file.
  final Set<String> retryable;

  /// Runs whose push can never succeed as they stand, mapped to why.
  final Map<String, RunPushBlockReason> blocked;

  const RunPushOutcome({
    this.retryable = const <String>{},
    this.blocked = const <String, RunPushBlockReason>{},
  });

  /// Every run that did NOT land, whichever way it failed. The set a caller
  /// subtracts from the batch before marking the rest synced.
  Set<String> get failedIds => <String>{...retryable, ...blocked.keys};

  int get failedCount => retryable.length + blocked.length;

  bool get isEmpty => retryable.isEmpty && blocked.isEmpty;

  @override
  String toString() =>
      'RunPushOutcome(retryable: ${retryable.length}, blocked: $blocked)';
}

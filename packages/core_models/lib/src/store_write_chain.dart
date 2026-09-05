import 'dart:async';

/// One serial chain per on-disk store directory.
///
/// `writeStringAtomic` gives every in-flight write its own `.tmp` sibling, so
/// two writes to one file cannot collide on a temp path. That is the whole of
/// what it promises, and it was read as more: nothing ordered two *operations*
/// over a store directory against each other. A delete that overtakes an
/// in-flight write to the same id removes `<id>.json` and the write's `rename`
/// puts it straight back; a directory wipe deletes the `.tmp` of a write still
/// in flight. See `docs/architecture/decisions.md` § 821 and § 828.
///
/// Keyed on the DIRECTORY, not on the owning object: every interleaving that
/// matters is between two instances over one directory — a sign-out wipe built
/// as a throwaway store, the WorkManager isolate's own store, a screen holding
/// one while a service holds another.
final Map<String, Future<void>> _chains = <String, Future<void>>{};

String _reentrancyMarker(String key) => 'storeWriteChain:$key';

/// Test-only observer of every operation the chain queues.
///
/// The defect a widget test walks into is DYNAMIC: a fake-zone `tester.tap`
/// starts a store write, nothing waits for it, and the write is still in
/// flight when `tearDown` deletes the temp directory out from under it. Three
/// successive censuses tried to count that population by grepping for helper
/// names and all three counted something else (decisions § 1097). This reports
/// the property itself — what was queued, from where, and what had not
/// finished by the time the test ended.
///
/// [onSettled] fires from the same continuation that completes the queueing
/// caller's future, which is deliberately the caller's own zone: a write whose
/// chain link is a fake-zone microtask nothing will ever run has not settled
/// as far as that test is concerned, and must not be reported as if it had.
abstract class StoreWriteObserver {
  void onQueued(int id, String key, StackTrace queuedAt);

  void onSettled(int id);
}

/// Installed by a test harness; null in every other build, so the cost here is
/// one static null test per queued operation and no stack is ever captured.
/// `package:meta` is not a dependency of this package, so the annotation this
/// would otherwise carry is a doc comment: nothing in `lib/` may set it.
StoreWriteObserver? debugStoreWriteObserver;

int _nextStoreWriteId = 0;

/// Run [body] after every operation already queued for [key], and before
/// every operation queued after it.
///
/// Re-entrant by design: a [body] that calls back in on the same [key] — a
/// public `save` whose shared `_persistIndex` helper is itself serialised —
/// runs inline instead of queueing behind itself. Queueing would deadlock, and
/// a deadlocked write on the recording stack is worse than the race this
/// closes: the caller's future never completes and the row is never persisted.
///
/// Per-ISOLATE, because Dart statics are. A second isolate over the same
/// directory (the WorkManager background sync) is out of reach of this, which
/// is why every sidecar writer merges rather than replaces and why
/// `kAtomicOrphanMinAge` exists.
Future<T> serialiseStoreWrite<T>(String key, Future<T> Function() body) {
  final marker = _reentrancyMarker(key);
  if (Zone.current[marker] == true) return body();

  final observer = debugStoreWriteObserver;
  final id = observer == null ? -1 : _nextStoreWriteId++;
  observer?.onQueued(id, key, StackTrace.current);

  final completer = Completer<T>();
  final prior = _chains[key] ?? Future<void>.value();
  // The chain must never become an error future, or one failed write would
  // reject every write queued behind it. The failure goes to its own caller.
  final link = prior.then((_) async {
    try {
      completer.complete(
        await runZoned(body, zoneValues: <Object, Object>{marker: true}),
      );
    } catch (e, st) {
      completer.completeError(e, st);
    } finally {
      observer?.onSettled(id);
    }
  });
  _chains[key] = link;
  // Keep the map bounded: a link that finished with nothing queued behind it
  // is the whole chain, and a fresh one starts from `Future.value()` anyway.
  link.whenComplete(() {
    if (identical(_chains[key], link)) _chains.remove(key);
  });
  return completer.future;
}

/// How long [storeWritesSettled] waits before reporting its wait as
/// unsatisfiable rather than continuing to wait. Far above any write this
/// helper serialises (a JSON file, milliseconds) and far below the test
/// runner's own timeout, so the deadlock below surfaces as its own diagnosis
/// instead of as an unexplained hang.
const Duration kStoreWritesSettledBound = Duration(seconds: 20);

/// How long after the bound expires [storeWritesSettled] waits before deciding
/// its diagnosis never reached the awaiter and sending it to
/// [debugStoreWritesSettledSink] instead.
///
/// A `Completer`'s error is delivered through the AWAITING zone's
/// continuation, and no property of that zone says in advance whether it will
/// ever be resumed — decisions § 1093 measured that zone identity carries no
/// signal at all. So it is answered after the fact: an awaiter that could be
/// resumed has been by the time this elapses, since resuming it is one
/// microtask, and one that could not is the fake-zone-with-no-pump case the
/// bound alone cannot reach.
const Duration kStoreWritesSettledReportGrace = Duration(seconds: 1);

/// Test-only sink for [storeWritesSettled]'s diagnosis when the awaiting zone
/// never receives it.
///
/// Row 5 of decisions § 1093's table — a write queued from a widget test's
/// fake zone and awaited from the fake zone with no pump behind it — still
/// hangs to the test runner's own timeout, because the bound's `StateError` is
/// a fake-zone continuation like everything else. Measured at that point: the
/// runner prints a bare `TimeoutException` naming neither the store nor the
/// call site. This sink is called from [Zone.root], so the diagnosis reaches
/// the runner whether or not the awaiter can ever run again.
///
/// `core_models` cannot reach `package:flutter_test`, so the Flutter side
/// installs it (`apps/mobile_android/test/flutter_test_config.dart`).
/// `package:meta` is not a dependency of this package, so the annotation this
/// would otherwise carry is a doc comment: nothing in `lib/` may set it.
void Function(Object error, StackTrace callSite)? debugStoreWritesSettledSink;

/// A future that completes once every operation queued for [key] so far has
/// finished. For a test whose only signal is an in-memory row installed before
/// the file write, and for a store shutting a directory down.
///
/// **Only awaitable when the operations it is waiting on can complete in the
/// zone the caller is awaiting from.** [serialiseStoreWrite] links its chain
/// with `.then`, so a write queued from a widget test's fake-async zone has
/// its continuation scheduled as a fake-zone microtask, and awaiting the chain
/// across that boundary waits on something nothing will run. Measured over
/// five configurations (decisions § 1093): queued inside `tester.runAsync` and
/// awaited from `runAsync` settles; queued from the fake zone settles from
/// neither `runAsync` nor the fake zone, with or without an intervening pump.
/// After a fake-zone `tester.tap`, wait on an observable outcome with
/// `pumpUntil` instead.
///
/// Rather than hang, the wait is bounded and reports itself. The bound is
/// armed on [Zone.root]: a caller inside the fake zone would otherwise arm a
/// fake timer, which is the very queue the wait is stuck on. [bound] is
/// widened or narrowed only by this helper's own tests.
///
/// The diagnosis is delivered twice over, because one channel cannot reach
/// both callers. Completing the returned future is the useful form for an
/// awaiter that can be resumed — the test fails where it asked. An awaiter
/// that cannot be resumed never sees it, so [kStoreWritesSettledReportGrace]
/// after the bound the same diagnosis goes to [debugStoreWritesSettledSink]
/// from [Zone.root], which is a channel the test RUNNER can read even while
/// the body is wedged.
Future<void> storeWritesSettled(
  String key, {
  Duration bound = kStoreWritesSettledBound,
}) {
  final settled = serialiseStoreWrite(key, () async {});
  final callSite = StackTrace.current;
  final out = Completer<void>();
  var observed = false;
  Timer? unreported;
  final watchdog = Zone.root.createTimer(bound, () {
    if (out.isCompleted) return;
    final error = StateError(
      'storeWritesSettled("$key") did not settle within '
      '${bound.inSeconds}s. The operation it is waiting on was queued from '
      'a zone this await cannot drain — in a widget test that means a write '
      'started by a fake-zone tap, whose chain link is a fake-zone '
      'microtask. Wait on an observable outcome with pumpUntil instead; '
      'debugWritesSettled is for a write queued from inside '
      'tester.runAsync. See decisions.md § 1072 and § 1093.',
    );
    out.completeError(error, callSite);
    unreported = Zone.root.createTimer(kStoreWritesSettledReportGrace, () {
      if (observed) return;
      debugStoreWritesSettledSink?.call(error, callSite);
    });
  });
  settled.then(
    (_) {
      watchdog.cancel();
      if (!out.isCompleted) out.complete();
    },
    onError: (Object e, StackTrace st) {
      watchdog.cancel();
      if (!out.isCompleted) out.completeError(e, st);
    },
  );
  return out.future.whenComplete(() {
    observed = true;
    watchdog.cancel();
    unreported?.cancel();
  });
}

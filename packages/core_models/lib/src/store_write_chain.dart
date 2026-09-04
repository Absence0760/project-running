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
Future<void> storeWritesSettled(
  String key, {
  Duration bound = kStoreWritesSettledBound,
}) {
  final settled = serialiseStoreWrite(key, () async {});
  final callSite = StackTrace.current;
  final out = Completer<void>();
  final watchdog = Zone.root.createTimer(bound, () {
    if (out.isCompleted) return;
    out.completeError(
      StateError(
        'storeWritesSettled("$key") did not settle within '
        '${bound.inSeconds}s. The operation it is waiting on was queued from '
        'a zone this await cannot drain — in a widget test that means a write '
        'started by a fake-zone tap, whose chain link is a fake-zone '
        'microtask. Wait on an observable outcome with pumpUntil instead; '
        'debugWritesSettled is for a write queued from inside '
        'tester.runAsync. See decisions.md § 1072 and § 1093.',
      ),
      callSite,
    );
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
  return out.future;
}

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

/// A future that completes once every operation queued for [key] so far has
/// finished. For a test whose only signal is an in-memory row installed before
/// the file write, and for a store shutting a directory down.
Future<void> storeWritesSettled(String key) =>
    serialiseStoreWrite(key, () async {});

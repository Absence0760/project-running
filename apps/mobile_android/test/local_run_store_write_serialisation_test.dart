import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_run_store.dart';

/// Two operations in flight over one run store used to interleave on the same
/// files. Every caller awaits its own call, so these fire a second operation
/// WITHOUT awaiting the first — the shape a screen firing a save unawaited, a
/// drain running against a live edit, or a bulk delete landing mid-save
/// produces. See `docs/architecture/decisions.md` § 828.
Run _run(String id, {int waypoints = 0}) => Run(
      id: id,
      startedAt: DateTime.utc(2026, 1, 1),
      duration: const Duration(minutes: 10),
      distanceMetres: 2000,
      source: RunSource.app,
      track: [
        for (var i = 0; i < waypoints; i++)
          Waypoint(lat: 51.5 + i / 100000, lng: -0.1 + i / 100000),
      ],
    );

void main() {
  late Directory dir;
  late LocalRunStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('run_store_serialise');
    store = LocalRunStore();
    await store.init(overrideDirectory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<String> filenames() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  test('a delete is not undone by a save that was in flight', () async {
    await store.save(_run('u1'));

    // Unserialised: the delete removed `u1.json`, the save's rename put it
    // back, and the save then reinstalled the row in `_runs` + `_summaries`
    // — so memory and disk agreed on a row the user had asked to delete.
    final write = store.save(_run('u1'));
    final del = store.delete('u1');
    await Future.wait([write, del]);

    expect(store.runs.map((r) => r.id), isNot(contains('u1')));
    expect(store.summaries.map((s) => s.id), isNot(contains('u1')));
    expect(filenames(), isNot(contains('u1.json')));

    final reloaded = LocalRunStore();
    await reloaded.init(overrideDirectory: dir);
    expect(reloaded.summaries.map((s) => s.id), isNot(contains('u1')));
  });

  test('a bulk delete is not undone by a save that was in flight', () async {
    await store.save(_run('u1'));
    await store.save(_run('u2'));

    final write = store.save(_run('u1'));
    final del = store.deleteMany(['u1', 'u2']);
    await Future.wait([write, del]);

    expect(store.summaries, isEmpty);
    expect(filenames(), isNot(contains('u1.json')));
  });

  test('two instances over one directory order against each other', () async {
    await store.save(_run('u1'));
    // The real shape: `background_sync.dart` builds its own LocalRunStore over
    // this same directory, so a per-instance chain would leave the two free to
    // race exactly as before.
    final other = LocalRunStore();
    await other.init(overrideDirectory: dir);

    final write = store.save(_run('u1'));
    final del = other.delete('u1');
    await Future.wait([write, del]);

    final reloaded = LocalRunStore();
    await reloaded.init(overrideDirectory: dir);
    expect(reloaded.summaries.map((s) => s.id), isNot(contains('u1')));
  });

  test('the index survives overlapping saves', () async {
    await Future.wait([
      for (var i = 0; i < 8; i++) store.save(_run('u$i')),
    ]);

    final raw =
        jsonDecode(File('${dir.path}/index.json').readAsStringSync()) as Map;
    final ids = [
      for (final e in raw['summaries'] as List) (e as Map)['id'] as String,
    ]..sort();
    expect(ids, [for (var i = 0; i < 8; i++) 'u$i']);
  });

  test('the pending-remote-delete sidecar survives overlapping marks',
      () async {
    await Future.wait([
      for (var i = 0; i < 8; i++)
        store.markPendingRemoteDelete('u$i', ownerUserId: 'owner'),
    ]);

    final raw = jsonDecode(
        File('${dir.path}/pending_remote_deletes.json').readAsStringSync());
    final deletes = ((raw as Map)['deletes'] as Map).keys.toList()..sort();
    expect(deletes, [for (var i = 0; i < 8; i++) 'u$i'],
        reason: 'the sidecar is read-modify-write, so an overlapping mark '
            'must not merge from a snapshot taken before the other wrote');
  });

  test('an in-progress recording write lands while the chain is blocked',
      () async {
    // The L1 crash-recovery append is deliberately off the chain: it owns
    // `in_progress.json`, which no chained operation touches, and its own
    // `_inFlightSave` guard already makes overlapping ticks exclusive. Hold
    // the store's chain open indefinitely (its key is the directory path) and
    // a recording tick must still land — a queued write that never lands is
    // worse than the race this closes.
    final gate = Completer<void>();
    final held = serialiseStoreWrite(dir.path, () => gate.future);

    var chainedLanded = false;
    unawaited(store.save(_run('queued')).then((_) => chainedLanded = true));

    await store
        .saveInProgress(_run('live', waypoints: 50))
        .timeout(const Duration(seconds: 5));
    expect(File('${dir.path}/in_progress.json').existsSync(), isTrue);

    final recovered = await store.loadInProgress();
    expect(recovered?.track.length, 50);

    await store.clearInProgress().timeout(const Duration(seconds: 5));
    expect(File('${dir.path}/in_progress.json').existsSync(), isFalse);

    // And the gate really was holding: the chained save had not run.
    expect(chainedLanded, isFalse);
    gate.complete();
    await held;
    await store.debugWritesSettled();
    expect(chainedLanded, isTrue);
  });

  test('debugWritesSettled waits for an operation started but not awaited',
      () async {
    store.save(_run('u1'));
    await store.debugWritesSettled();

    expect(File('${dir.path}/u1.json').existsSync(), isTrue);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/local_gear_store.dart';

/// Two writes in flight over one store used to interleave on the same files.
/// Every caller awaits its own call, so these fire a second write WITHOUT
/// awaiting the first — the shape a screen firing a save unawaited, a drain
/// running against a live edit, or sign-out landing mid-save produces.
void main() {
  late Directory dir;
  late LocalGearStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('offline_sync_serialise');
    store = LocalGearStore();
    await store.init(overrideDirectory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<String> filenames() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  test('clear() cannot delete the temp sibling of an in-flight write',
      () async {
    final gear = await store.createLocal(name: 'Pegasus', kind: 'shoes');

    // clear() deletes EVERY file in the directory, including the `.tmp` the
    // in-flight write is about to rename into place. Unserialised, that write's
    // rename failed with a PathNotFoundException naming a temp path.
    final write = store.updateLocal(gear.id, {'name': 'Pegasus 41'});
    final wipe = store.clear();
    await expectLater(Future.wait([write, wipe]), completes);

    // And the wipe is the one that won, as its caller was told: nothing of the
    // signed-out user survives, not even a resurrected row file.
    expect(filenames(), isEmpty);
    expect(store.debugStored(gear.id), isNull);
  });

  test('a delete cannot be overtaken by an in-flight write to the same row',
      () async {
    final gear = await store.createLocal(name: 'Pegasus', kind: 'shoes');
    expect(filenames(), contains('${gear.id}.json'));

    // Unserialised: the delete removed `<id>.json`, then the write's rename put
    // it back. `rowsById` said the row was gone while the file was on disk, so
    // the next cold-load resurrected a deleted row with no exception anywhere.
    final write = store.updateLocal(gear.id, {'name': 'Pegasus 41'});
    final delete = store.deleteLocal(gear.id);
    await Future.wait([write, delete]);

    expect(store.debugStored(gear.id), isNull);
    expect(filenames(), isNot(contains('${gear.id}.json')),
        reason: 'a deleted row must not be left on disk by a write that was '
            'in flight when the delete landed');

    // Prove it by reloading: the row must not come back.
    final reloaded = LocalGearStore();
    await reloaded.init(overrideDirectory: dir);
    expect(reloaded.debugStored(gear.id), isNull);
  });

  test('concurrent writes to one row leave disk agreeing with memory',
      () async {
    final gear = await store.createLocal(name: 'Pegasus', kind: 'shoes');

    await Future.wait([
      store.updateLocal(gear.id, {'name': 'first'}),
      store.updateLocal(gear.id, {'name': 'second'}),
    ]);

    final onDisk = jsonDecode(
        File('${dir.path}/${gear.id}.json').readAsStringSync()) as Map;
    expect((onDisk['row'] as Map)['name'],
        store.debugStored(gear.id)!.row['name']);
  });

  test('debugWritesSettled waits for a write started but not awaited',
      () async {
    final gear = await store.createLocal(name: 'Pegasus', kind: 'shoes');
    // Deliberately not awaited — the caller only holds the in-memory signal.
    store.updateLocal(gear.id, {'name': 'Pegasus 41'});
    await store.debugWritesSettled();

    final onDisk = jsonDecode(
        File('${dir.path}/${gear.id}.json').readAsStringSync()) as Map;
    expect((onDisk['row'] as Map)['name'], 'Pegasus 41');
  });
}

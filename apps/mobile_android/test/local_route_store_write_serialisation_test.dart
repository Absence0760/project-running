import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_route_store.dart';

/// Two operations in flight over one route store used to interleave on the
/// same files. Every caller awaits its own call, so these fire a second
/// operation WITHOUT awaiting the first — the shape a screen firing a save
/// unawaited, a remote pull landing mid-edit, or the sync drain's
/// `tagRoutesOwner` running against a live save produces. See
/// `docs/architecture/decisions.md` § 828.
Route _route(String id) => Route(
      id: id,
      name: 'Loop $id',
      waypoints: const [Waypoint(lat: 51.5, lng: -0.1)],
      distanceMetres: 1000,
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  late Directory dir;
  late LocalRouteStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('route_store_serialise');
    store = LocalRouteStore();
    await store.init(overrideDirectory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<String> filenames() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  test('a delete is not undone by a save that was in flight', () async {
    await store.save(_route('r1'));

    // Unserialised: the delete removed `r1.json`, the save's rename put it
    // back, and the save then re-inserted the row into `_routes` — so memory
    // and disk agreed on a route the user had asked to delete.
    final write = store.save(_route('r1'));
    final del = store.delete('r1');
    await Future.wait([write, del]);

    expect(store.routes.map((r) => r.id), isNot(contains('r1')));
    expect(filenames(), isNot(contains('r1.json')));

    final reloaded = LocalRouteStore();
    await reloaded.init(overrideDirectory: dir);
    expect(reloaded.routes.map((r) => r.id), isNot(contains('r1')));
  });

  test('a bulk delete is not undone by a save that was in flight', () async {
    await store.save(_route('r1'));
    await store.save(_route('r2'));

    final write = store.save(_route('r1'));
    final del = store.deleteMany(['r1', 'r2']);
    await Future.wait([write, del]);

    expect(store.routes, isEmpty);
    expect(filenames(), isNot(contains('r1.json')));
  });

  test('overlapping saves keep every §67 owner tag', () async {
    // The sidecar is read-modify-write and `_ownerTagsTouched` is cleared by
    // whichever write lands first, so unserialised saves merged from a
    // snapshot taken before their sibling wrote: as few as two of these eight
    // routes kept a tag, and an untagged route is visible to — and drainable
    // into the cloud account of — every other account on the device.
    store.currentUserIdProvider = () => 'userA';
    await Future.wait([
      for (var i = 0; i < 8; i++) store.save(_route('r$i')),
    ]);

    final raw = jsonDecode(
        File('${dir.path}/route_owner_tags.json').readAsStringSync()) as Map;
    final tagged = (raw['tags'] as Map).keys.toList()..sort();
    expect(tagged, [for (var i = 0; i < 8; i++) 'r$i']);

    final asOtherUser = LocalRouteStore();
    asOtherUser.currentUserIdProvider = () => 'userB';
    await asOtherUser.init(overrideDirectory: dir);
    expect(asOtherUser.routes, isEmpty,
        reason: "user A's routes must not become visible to user B because "
            'two of their saves overlapped');
  });

  test('the synced-ids sidecar survives overlapping saves', () async {
    await Future.wait([
      for (var i = 0; i < 8; i++) store.save(_route('r$i'), markSynced: true),
    ]);

    final raw = jsonDecode(
        File('${dir.path}/synced_route_ids.json').readAsStringSync()) as Map;
    final ids = (raw['ids'] as List).cast<String>().toList()..sort();
    expect(ids, [for (var i = 0; i < 8; i++) 'r$i']);
  });

  test('two instances over one directory order against each other', () async {
    await store.save(_route('r1'));
    final other = LocalRouteStore();
    await other.init(overrideDirectory: dir);

    final write = store.save(_route('r1'));
    final del = other.delete('r1');
    await Future.wait([write, del]);

    final reloaded = LocalRouteStore();
    await reloaded.init(overrideDirectory: dir);
    expect(reloaded.routes.map((r) => r.id), isNot(contains('r1')));
  });

  test('no .lock sidecar is left behind', () async {
    await store.save(_route('r1'));
    await store.pinOffline('r1');
    await store.markPendingRemoteDelete('r1', ownerUserId: 'userA');

    expect(filenames().where((f) => f.endsWith('.lock')), isEmpty);
  });

  test('a queued operation still lands after the one ahead of it fails',
      () async {
    // The chain must never become an error future: a failure belongs to its
    // own caller, not to everything behind it.
    final failing = serialiseStoreWrite(dir.path, () async {
      throw StateError('boom');
    });
    final after = store.save(_route('r1'));

    await expectLater(failing, throwsStateError);
    await after.timeout(const Duration(seconds: 5));
    expect(filenames(), contains('r1.json'));
  });

  test('debugWritesSettled waits for an operation started but not awaited',
      () async {
    store.save(_route('r1'));
    await store.debugWritesSettled();

    expect(File('${dir.path}/r1.json').existsSync(), isTrue);
  });
}

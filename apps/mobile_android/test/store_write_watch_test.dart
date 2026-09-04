// The write watch, proved against the shape it exists for: a fake-zone
// `tester.tap` that starts a real store write, with and without anything
// waiting for it. Both tests drive `LocalRouteStore.save` through a button so
// the write is queued exactly where a screen queues one — decisions § 1129.

import 'dart:io';

import 'package:core_models/core_models.dart' as models;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_route_store.dart';
import 'pump_until.dart';
import 'store_write_watch.dart';

models.Route _route(String id) => models.Route(
      id: id,
      name: 'Loop $id',
      waypoints: const [models.Waypoint(lat: 51.5, lng: -0.1)],
      distanceMetres: 1000,
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  late Directory dir;
  late LocalRouteStore store;
  var saved = false;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('store_write_watch_');
    store = LocalRouteStore();
    saved = false;
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pumpButton(WidgetTester tester) async {
    await tester.runAsync(() => store.init(overrideDirectory: dir));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              store.save(_route('r1')).then((_) => saved = true);
            },
            child: const Text('Save'),
          ),
        ),
      ),
    ));
  }

  testWidgets('a tap that starts a store write nobody waits for is named',
      (tester) async {
    await pumpButton(tester);
    await tester.tap(find.text('Save'));
    await tester.pump();

    final verdict = takeStoreWriteWatchVerdict();
    expect(verdict, isNotNull);
    expect(verdict, contains(dir.path));
    expect(verdict, contains('pumpUntil'));

    // Drain it before the teardown deletes the directory under it — which is
    // the race the verdict is about.
    await pumpUntil(tester, () => saved, describe: 'the tapped save to land');
  });

  testWidgets('a tap whose write is waited for is not named', (tester) async {
    await pumpButton(tester);
    await tester.tap(find.text('Save'));
    await pumpUntil(tester, () => saved, describe: 'the tapped save to land');

    expect(takeStoreWriteWatchVerdict(), isNull);
    expect(File('${dir.path}/r1.json').existsSync(), isTrue);
  });
}

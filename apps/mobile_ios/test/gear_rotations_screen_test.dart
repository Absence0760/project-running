import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gear_store.dart';
import '../lib/screens/gear_rotations_screen.dart';

GearRotationWithMembers _rot({
  String id = 'r1',
  String name = 'Daily trainers',
  List<String> gearIds = const ['g1'],
}) =>
    GearRotationWithMembers(
      rotation: GearRotationRow(
        id: id,
        ownerId: 'viewer-1',
        name: name,
        createdAt: DateTime(2026, 6, 20),
        updatedAt: DateTime(2026, 6, 20),
      ),
      gearIds: gearIds,
    );

class _RotApi extends ApiClient {
  _RotApi({List<GearRotationWithMembers>? seed})
      : _rows = List.of(seed ?? const []);

  final List<GearRotationWithMembers> _rows;
  int createCalls = 0;
  int deleteCalls = 0;
  String? lastCreateName;
  String? lastSetRotationId;
  List<String>? lastSetMembers;

  @override
  String? get userId => 'viewer-1';

  @override
  Future<List<GearRotationWithMembers>> fetchMyGearRotations() async =>
      List.of(_rows);

  @override
  Future<GearRotationRow> createGearRotation(String name) async {
    createCalls++;
    lastCreateName = name;
    return _rot(id: 'new', name: name, gearIds: const []).rotation;
  }

  @override
  Future<void> renameGearRotation(String id, String name) async {}

  @override
  Future<void> deleteGearRotation(String id) async {
    deleteCalls++;
  }

  @override
  Future<void> setGearRotationMembers(
      String rotationId, List<String> gearIds) async {
    lastSetRotationId = rotationId;
    lastSetMembers = gearIds;
  }
}

Future<({LocalGearStore store, Directory dir})> _setup(String tag) async {
  SharedPreferences.setMockInitialValues({});
  final dir = Directory.systemTemp.createTempSync('gear_rot_$tag');
  final store = LocalGearStore();
  await store.init(overrideDirectory: dir);
  return (store: store, dir: dir);
}

Widget _app(ApiClient api, LocalGearStore store) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GearRotationsScreen(api: api, gearStore: store),
    );

Future<void> _pump(WidgetTester tester, Widget app) async {
  await tester.binding.setSurfaceSize(const Size(420, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(app);
  // fetchMyGearRotations resolves on the first frame's microtask.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('empty state renders the onboarding copy', (tester) async {
    final f = await _setup('empty');
    try {
      await _pump(tester, _app(_RotApi(), f.store));
      expect(
        find.text(
            'No rotations yet. Create one to group a set of shoes or bikes.'),
        findsOneWidget,
      );
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a seeded rotation renders its name + member count',
      (tester) async {
    final f = await _setup('seeded');
    try {
      await _pump(
        tester,
        _app(_RotApi(seed: [_rot(name: 'Race day', gearIds: ['g1', 'g2'])]),
            f.store),
      );
      expect(find.text('Race day'), findsOneWidget);
      expect(find.text('2 items'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('editing members calls setGearRotationMembers with the toggled set',
      (tester) async {
    final f = await _setup('members');
    // Two gear rows in the store; the rotation starts with g1 only.
    await f.store.createLocal(kind: 'shoe', name: 'Pegasus');
    await f.store.createLocal(kind: 'shoe', name: 'Ghost');
    final ids = f.store.rows.map((r) => r['id'] as String).toList();
    final api = _RotApi(seed: [_rot(id: 'r1', gearIds: [ids.first])]);
    try {
      await _pump(tester, _app(api, f.store));
      // Open the member sheet from the row tap. Bounded pumps (not
      // pumpAndSettle) — the modal sheet's slide + scrollbar animation
      // never settles under the fake clock.
      await tester.tap(find.text('Daily trainers'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Pegasus'), findsOneWidget);
      expect(find.text('Ghost'), findsOneWidget);
      // Add the second gear (Ghost) to the rotation.
      await tester.tap(find.text('Ghost'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(api.lastSetRotationId, 'r1');
      expect(api.lastSetMembers, isNotNull);
      expect(api.lastSetMembers!.toSet(), {ids.first, ids.last});
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('deleting a rotation confirms then calls the api', (tester) async {
    final f = await _setup('delete');
    final api = _RotApi(seed: [_rot(name: 'Trail')]);
    try {
      await _pump(tester, _app(api, f.store));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Delete').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Confirm dialog.
      expect(find.text('Delete rotation?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(api.deleteCalls, 1);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}

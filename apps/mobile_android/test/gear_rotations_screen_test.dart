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

Map<String, dynamic> _gear({
  required String id,
  required String name,
  String kind = 'shoe',
  int totalDistanceM = 0,
  int? targetDistanceM = 800000,
  String? retiredAt,
  bool isDefault = false,
}) =>
    {
      'id': id,
      'owner_id': 'viewer-1',
      'kind': kind,
      'name': name,
      'brand': null,
      'model': null,
      'purchased_at': null,
      'retired_at': retiredAt,
      'target_distance_m': targetDistanceM,
      'notes': null,
      'is_default': isDefault,
      'created_at': '2026-06-20T00:00:00.000Z',
      'updated_at': '2026-06-20T00:00:00.000Z',
      'total_distance_m': totalDistanceM,
      'run_count': 0,
    };

class _RotApi extends ApiClient {
  _RotApi({List<GearRotationWithMembers>? seed, List<Map<String, dynamic>>? gear})
      : _rows = List.of(seed ?? const []),
        _gearRows = List.of(gear ?? const []);

  final List<GearRotationWithMembers> _rows;
  final List<Map<String, dynamic>> _gearRows;
  int createCalls = 0;
  int deleteCalls = 0;
  String? lastCreateName;
  String? lastSetRotationId;
  List<String>? lastSetMembers;
  String? lastDefaultGearId;
  String? lastDefaultKind;

  @override
  Future<List<Map<String, dynamic>>> fetchMyGearWithDistance() async =>
      List.of(_gearRows);

  @override
  Future<void> setDefaultGear(String? gearId, String kind) async {
    lastDefaultGearId = gearId;
    lastDefaultKind = kind;
    for (final g in _gearRows) {
      if (g['kind'] == kind) g['is_default'] = g['id'] == gearId;
    }
  }

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
    // Two gear rows in the store; the rotation starts with g1 only. The
    // createLocal writes hit the real disk via writeJsonAtomic — they MUST run
    // inside tester.runAsync. Awaiting real dart:io I/O directly in the
    // testWidgets body deadlocks the FakeAsync zone (the fake clock never pumps
    // the real I/O event queue), wedging the whole file with no timeout escape.
    late List<String> ids;
    await tester.runAsync(() async {
      await f.store.createLocal(kind: 'shoe', name: 'Pegasus');
      await f.store.createLocal(kind: 'shoe', name: 'Ghost');
      ids = f.store.rows.map((r) => r['id'] as String).toList();
    });
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
      // Done → setGearRotationMembers → Navigator.pop dismisses the sheet, then
      // _editMembers awaits load(). Drain the dismiss animation + the fake-api
      // microtasks on the fake clock with bounded pumps.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
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
      // Pop the confirm dialog, then drain _delete's deleteGearRotation +
      // load() microtasks on the fake clock with bounded pumps.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(api.deleteCalls, 1);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('the least-worn in-service pair is offered as next up',
      (tester) async {
    final f = await _setup('nextup');
    final gear = [
      _gear(id: 'g1', name: 'Pegasus', totalDistanceM: 600000, isDefault: true),
      _gear(id: 'g2', name: 'Ghost', totalDistanceM: 100000),
    ];
    await tester.runAsync(() => f.store.replaceFromServer(gear));
    final api = _RotApi(
        seed: [_rot(gearIds: ['g1', 'g2'])], gear: gear);
    try {
      await _pump(tester, _app(api, f.store));
      expect(find.text('Next up: Ghost'), findsOneWidget);
      expect(find.text('Least worn in this rotation.'), findsOneWidget);
      expect(find.text('Make current'), findsOneWidget);
      expect(find.text('Already the current pair.'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('Make current moves the star onto the picked pair',
      (tester) async {
    final f = await _setup('makecurrent');
    final gear = [
      _gear(id: 'g1', name: 'Pegasus', totalDistanceM: 600000, isDefault: true),
      _gear(id: 'g2', name: 'Ghost', totalDistanceM: 100000),
    ];
    await tester.runAsync(() => f.store.replaceFromServer(gear));
    final api = _RotApi(
        seed: [_rot(gearIds: ['g1', 'g2'])], gear: gear);
    try {
      await _pump(tester, _app(api, f.store));
      await tester.tap(find.text('Make current'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(api.lastDefaultGearId, 'g2');
      expect(api.lastDefaultKind, 'shoe');
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a pick that already holds the star offers no move',
      (tester) async {
    final f = await _setup('iscurrent');
    final gear = [
      _gear(id: 'g1', name: 'Pegasus', totalDistanceM: 600000),
      _gear(id: 'g2', name: 'Ghost', totalDistanceM: 100000, isDefault: true),
    ];
    await tester.runAsync(() => f.store.replaceFromServer(gear));
    try {
      await _pump(
        tester,
        _app(_RotApi(seed: [_rot(gearIds: ['g1', 'g2'])], gear: gear), f.store),
      );
      expect(find.text('Next up: Ghost'), findsOneWidget);
      expect(find.text('Already the current pair.'), findsOneWidget);
      expect(find.text('Make current'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('one live pair beside a retired one is not a rotation to choose from',
      (tester) async {
    final f = await _setup('retired');
    final gear = [
      _gear(id: 'g1', name: 'Pegasus', totalDistanceM: 100000),
      _gear(
          id: 'g2',
          name: 'Ghost',
          totalDistanceM: 600000,
          retiredAt: '2026-01-01'),
    ];
    await tester.runAsync(() => f.store.replaceFromServer(gear));
    try {
      await _pump(
        tester,
        _app(_RotApi(seed: [_rot(gearIds: ['g1', 'g2'])], gear: gear), f.store),
      );
      expect(find.textContaining('Next up:'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a rotation whose every pair is worn says so', (tester) async {
    final f = await _setup('allworn');
    final gear = [
      _gear(id: 'g1', name: 'Pegasus', totalDistanceM: 1200000),
      _gear(id: 'g2', name: 'Ghost', totalDistanceM: 850000),
    ];
    await tester.runAsync(() => f.store.replaceFromServer(gear));
    try {
      await _pump(
        tester,
        _app(_RotApi(seed: [_rot(gearIds: ['g1', 'g2'])], gear: gear), f.store),
      );
      expect(find.text('Next up: Ghost'), findsOneWidget);
      expect(
          find.text('Every pair here is at or past its replacement target.'),
          findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}

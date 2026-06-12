import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/screens/gym_detail_screen.dart';

Future<({LocalGymStore store, Directory dir, String id})> _seed() async {
  final dir = Directory.systemTemp.createTempSync('gym_detail_vis');
  final store = LocalGymStore();
  await store.init(overrideDirectory: dir);
  final stored = await store.createLocal(
    title: 'Push day',
    startedAt: DateTime.now().toUtc(),
    sets: const [
      (exerciseName: 'Bench', reps: 8, weightKg: 60.0, rpe: null, durationS: null),
    ],
  );
  return (store: store, dir: dir, id: stored.id);
}

Widget _screen(LocalGymStore store, String id) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // api: null → offline; the screen reads + writes the local store only.
      home: GymDetailScreen(api: null, store: store, workoutId: id),
    );

void main() {
  testWidgets('detail shows Private chip + make-public toggle flips the store',
      (tester) async {
    late LocalGymStore store;
    late String id;
    late Directory dir;
    await tester.runAsync(() async {
      final s = await _seed();
      store = s.store;
      id = s.id;
      dir = s.dir;
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(store, id));
    await tester.pump();

    // Defaults to private — the chip + the make-public action are shown.
    expect(find.text('Private'), findsOneWidget);
    expect(find.byTooltip('Make public'), findsOneWidget);
    expect(store.byId(id)!.workout.isPublic, isFalse);

    // Toggle to public.
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Make public'));
      // Let the fire-and-forget async store write + its listener notify settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump();

    // Store flipped to public + queued for the next sync (pendingUpdate).
    final updated = store.byId(id)!;
    expect(updated.workout.isPublic, isTrue);
    expect(updated.syncState, GymSyncState.pendingCreate);
    // The chip + tooltip now reflect public.
    expect(find.text('Public'), findsOneWidget);
    expect(find.byTooltip('Make private'), findsOneWidget);
  });
}

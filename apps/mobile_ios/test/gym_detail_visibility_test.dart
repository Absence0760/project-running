import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/screens/gym_detail_screen.dart';

/// Counts updateLocal calls so the double-submit guard can be asserted.
class _CountingGymStore extends LocalGymStore {
  int updateCalls = 0;
  @override
  Future<void> updateLocal(
    String id, {
    String? title,
    int? durationS,
    String? notes,
    bool? isPublic,
    Map<String, dynamic>? metadata,
    List<GymSetInput>? sets,
  }) async {
    updateCalls++;
    return super.updateLocal(
      id,
      title: title,
      durationS: durationS,
      notes: notes,
      isPublic: isPublic,
      metadata: metadata,
      sets: sets,
    );
  }
}

class _ThrowingDeleteGymStore extends LocalGymStore {
  @override
  Future<void> deleteLocal(String id) async {
    throw StateError('disk full');
  }
}

Future<({LocalGymStore store, Directory dir, String id})> _seed() async {
  final dir = Directory.systemTemp.createTempSync('gym_detail_vis');
  final store = LocalGymStore();
  await store.init(overrideDirectory: dir);
  final stored = await store.createLocal(
    title: 'Push day',
    startedAt: DateTime.now().toUtc(),
    sets: const [
      (exerciseName: 'Bench', reps: 8, weightKg: 60.0, rpe: null, setType: null, durationS: null, exerciseId: null),
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

  testWidgets(
      'vs-last-time hint resolves the right prior session per exercise '
      '(grouped-history path)', (tester) async {
    late LocalGymStore store;
    late String currentId;
    late Directory dir;
    await tester.runAsync(() async {
      final dirTmp = Directory.systemTemp.createTempSync('gym_detail_prev');
      final s = LocalGymStore();
      await s.init(overrideDirectory: dirTmp);
      // An earlier *different* exercise — must NOT be picked as Bench's prev.
      await s.createLocal(
        title: 'Leg day',
        startedAt: DateTime.utc(2026, 6, 1, 8),
        sets: const [
          (exerciseName: 'Squat', reps: 5, weightKg: 100.0, rpe: null, setType: null, durationS: null, exerciseId: null),
        ],
      );
      // The earlier Bench session — the one the hint should compare against.
      await s.createLocal(
        title: 'Push day',
        startedAt: DateTime.utc(2026, 6, 3, 8),
        sets: const [
          (exerciseName: 'Bench', reps: 8, weightKg: 50.0, rpe: null, setType: null, durationS: null, exerciseId: null),
        ],
      );
      // The current (most recent) Bench session being viewed: 60 kg, +10 kg.
      final current = await s.createLocal(
        title: 'Push day',
        startedAt: DateTime.utc(2026, 6, 10, 8),
        sets: const [
          (exerciseName: 'Bench', reps: 8, weightKg: 60.0, rpe: null, setType: null, durationS: null, exerciseId: null),
        ],
      );
      store = s;
      currentId = current.id;
      dir = dirTmp;
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(store, currentId));
    await tester.pump();

    // The hint compares against the earlier *Bench* session (50 kg × 8),
    // not the heavier Squat — i.e. the per-exercise grouping is correct.
    expect(find.textContaining('Last time'), findsOneWidget);
    expect(find.textContaining('50'), findsWidgets);
    // And it reads as a gain (this session 60 kg > last 50 kg).
    expect(find.byIcon(Icons.trending_up), findsOneWidget);
  });

  testWidgets('a failed workout delete surfaces an error banner',
      (tester) async {
    late _ThrowingDeleteGymStore store;
    late String id;
    late Directory dir;
    await tester.runAsync(() async {
      final dirTmp = Directory.systemTemp.createTempSync('gym_detail_del_fail');
      final s = _ThrowingDeleteGymStore();
      await s.init(overrideDirectory: dirTmp);
      final stored = await s.createLocal(
        title: 'Push day',
        startedAt: DateTime.now().toUtc(),
        sets: const [
          (exerciseName: 'Bench', reps: 8, weightKg: 60.0, rpe: null, setType: null, durationS: null, exerciseId: null),
        ],
      );
      store = s;
      id = stored.id;
      dir = dirTmp;
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(store, id));
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Delete'));
    });
    await tester.pumpAndSettle();
    expect(find.text('Delete workout?'), findsOneWidget);

    final confirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Delete'),
    );
    await tester.runAsync(() async {
      await tester.tap(confirm);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump();

    // The delete threw; the detail screen stays open (no pop) and an error
    // banner shows rather than the failure being swallowed silently.
    expect(find.textContaining("Couldn't delete the workout"), findsOneWidget);
    // Drain the showTopBanner auto-dismiss timer.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('double-tapping the visibility toggle writes the store only once',
      (tester) async {
    late _CountingGymStore store;
    late String id;
    late Directory dir;
    await tester.runAsync(() async {
      final dirTmp = Directory.systemTemp.createTempSync('gym_detail_vis2');
      final s = _CountingGymStore();
      await s.init(overrideDirectory: dirTmp);
      final stored = await s.createLocal(
        title: 'Push day',
        startedAt: DateTime.now().toUtc(),
        sets: const [
          (exerciseName: 'Bench', reps: 8, weightKg: 60.0, rpe: null, setType: null, durationS: null, exerciseId: null),
        ],
      );
      store = s;
      id = stored.id;
      dir = dirTmp;
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(store, id));
    await tester.pump();

    // Two synchronous taps — the _actionBusy guard set on the first must
    // make the second a no-op before the rebuild paints the disabled button.
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Make public'));
      await tester.tap(find.byTooltip('Make public'), warnIfMissed: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump();

    expect(store.updateCalls, 1);
    expect(store.byId(id)!.workout.isPublic, isTrue);
  });
}

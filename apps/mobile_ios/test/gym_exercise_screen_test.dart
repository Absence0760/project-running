import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/screens/gym_detail_screen.dart';
import '../lib/screens/gym_exercise_screen.dart';

/// Seed a [LocalGymStore] on a fresh temp dir. Each session is one createLocal
/// call so its `started_at` orders the progression series. Returns the store +
/// dir so the caller can tear the dir down.
Future<({LocalGymStore store, Directory dir})> _seed(
  WidgetTester tester,
  List<({String title, DateTime at, List<GymSetInput> sets})> sessions,
) async {
  late LocalGymStore store;
  late Directory dir;
  await tester.runAsync(() async {
    dir = Directory.systemTemp.createTempSync('gym_exercise_');
    final s = LocalGymStore();
    await s.init(overrideDirectory: dir);
    for (final session in sessions) {
      await s.createLocal(
        title: session.title,
        startedAt: session.at,
        sets: session.sets,
      );
    }
    store = s;
  });
  return (store: store, dir: dir);
}

GymSetInput _set(String name, {int? reps, double? weightKg}) =>
    (exerciseName: name, reps: reps, weightKg: weightKg, rpe: null, setType: null, durationS: null, exerciseId: null);

Widget _screen(LocalGymStore store, String exercise) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GymExerciseScreen(api: null, store: store, exerciseName: exercise),
    );

void main() {
  // The session rows render a localised date via formatDateMed → DateFormat.
  setUpAll(() => initializeDateFormatting());

  testWidgets('empty / unknown exercise renders the no-history state',
      (tester) async {
    final seeded = await _seed(tester, [
      (
        title: 'Push day',
        at: DateTime.utc(2026, 6, 1, 8),
        sets: [_set('Bench', reps: 5, weightKg: 100)],
      ),
    ]);
    addTearDown(() => seeded.dir.deleteSync(recursive: true));

    // Ask for an exercise that was never logged → progress is null.
    await tester.pumpWidget(_screen(seeded.store, 'Deadlift'));
    await tester.pump();

    expect(find.text('No history for this exercise yet.'), findsOneWidget);
    // The AppBar still carries the requested name.
    expect(find.text('Deadlift'), findsOneWidget);
  });

  testWidgets('bodyweight-only history is treated as no qualifying history',
      (tester) async {
    // A pull-up with no logged weight never qualifies (records exclude
    // bodyweight) — same exclusion the records + PR surfaces apply.
    final seeded = await _seed(tester, [
      (
        title: 'Pull day',
        at: DateTime.utc(2026, 6, 1, 8),
        sets: [_set('Pull-up', reps: 10)],
      ),
    ]);
    addTearDown(() => seeded.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(seeded.store, 'Pull-up'));
    await tester.pump();

    expect(find.text('No history for this exercise yet.'), findsOneWidget);
  });

  testWidgets(
      'a multi-session progression shows the headline, a gain delta, and one '
      'row per session', (tester) async {
    // Three Bench sessions climbing 80 → 90 → 100 kg. Latest e1RM beats first,
    // so the "since first" delta reads as a gain.
    final seeded = await _seed(tester, [
      (
        title: 'A',
        at: DateTime.utc(2026, 6, 1, 8),
        sets: [_set('Bench', reps: 5, weightKg: 80)],
      ),
      (
        title: 'B',
        at: DateTime.utc(2026, 6, 8, 8),
        sets: [_set('Bench', reps: 5, weightKg: 90)],
      ),
      (
        title: 'C',
        at: DateTime.utc(2026, 6, 15, 8),
        sets: [_set('Bench', reps: 5, weightKg: 100)],
      ),
    ]);
    addTearDown(() => seeded.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(seeded.store, 'Bench'));
    await tester.pump();

    // Headline carries the e1RM label + the session count.
    expect(find.text('BEST EST. 1RM'), findsOneWidget);
    expect(find.text('3 sessions'), findsOneWidget);

    // Latest session beat the first → the up-trend delta chip + icon.
    expect(find.byIcon(Icons.trending_up), findsOneWidget);
    expect(find.textContaining('since first session'), findsOneWidget);

    // Each session is climbing, so every one raised the heaviest weight →
    // a "Heaviest" PR badge per row. ('Heaviest' is unique to the badge — the
    // per-session metric label + headline use the e1RM label instead.)
    expect(find.text('Heaviest'), findsNWidgets(3));
  });

  testWidgets('a plateau (no improvement) shows no up-trend and only the first PR',
      (tester) async {
    // Identical sessions → only the first sets a heaviest-weight PR, and the
    // since-first delta is flat, never an up-trend.
    final seeded = await _seed(tester, [
      (
        title: 'A',
        at: DateTime.utc(2026, 6, 1, 8),
        sets: [_set('Squat', reps: 5, weightKg: 120)],
      ),
      (
        title: 'B',
        at: DateTime.utc(2026, 6, 8, 8),
        sets: [_set('Squat', reps: 5, weightKg: 120)],
      ),
    ]);
    addTearDown(() => seeded.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(seeded.store, 'Squat'));
    await tester.pump();

    expect(find.text('2 sessions'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsNothing);
    expect(find.byIcon(Icons.trending_flat), findsOneWidget);
    // Only the earliest session raised the heaviest weight → one badge.
    expect(find.text('Heaviest'), findsOneWidget);
  });

  testWidgets('tapping a session row opens that workout detail', (tester) async {
    final seeded = await _seed(tester, [
      (
        title: 'Bench session',
        at: DateTime.utc(2026, 6, 1, 8),
        sets: [_set('Bench', reps: 5, weightKg: 100)],
      ),
    ]);
    addTearDown(() => seeded.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(seeded.store, 'Bench'));
    await tester.pump();

    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();

    // Navigated into the workout detail for the tapped session.
    expect(find.byType(GymDetailScreen), findsOneWidget);
  });
}

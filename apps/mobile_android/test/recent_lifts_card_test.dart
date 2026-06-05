import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/widgets/recent_lifts_card.dart';

StoredGymWorkout _w(String id,
        {String? title, DateTime? startedAt, List<Map<String, dynamic>> sets = const []}) =>
    StoredGymWorkout(
      row: {
        'id': id,
        'title': title,
        'started_at': (startedAt ?? DateTime.utc(2026, 1, 1)).toIso8601String(),
        'is_public': false,
      },
      sets: sets,
      syncState: GymSyncState.synced,
    );

Map<String, dynamic> _s(String name, {num? reps, num? weight}) =>
    {'exercise_name': name, 'reps': reps, 'weight_kg': weight, 'rpe': null};

Future<void> _pump(
  WidgetTester tester,
  List<StoredGymWorkout> workouts, {
  void Function(String)? onOpen,
  VoidCallback? onViewAll,
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: RecentLiftsCard(
        workouts: workouts,
        onOpenWorkout: onOpen ?? (_) {},
        onViewAll: onViewAll ?? () {},
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets('renders nothing when there are no lifts (anti-clutter)',
      (tester) async {
    await _pump(tester, const []);
    expect(find.text('Recent lifts'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('renders header, View all, and a row per workout', (tester) async {
    await _pump(tester, [
      _w('a',
          title: 'Push day',
          startedAt: DateTime.utc(2026, 2, 1),
          sets: [_s('Bench', reps: 5, weight: 100)]),
      _w('b',
          title: 'Leg day',
          startedAt: DateTime.utc(2026, 1, 28),
          sets: [_s('Squat', reps: 5, weight: 140)]),
    ]);
    expect(find.text('Recent lifts'), findsOneWidget);
    expect(find.text('View all'), findsOneWidget);
    expect(find.text('Push day'), findsOneWidget);
    expect(find.text('Leg day'), findsOneWidget);
    expect(find.text('1 exercise'), findsNWidgets(2));
  });

  testWidgets('caps the list at five most-recent workouts', (tester) async {
    final workouts = [
      for (var i = 0; i < 6; i++)
        _w('w$i',
            title: 'Session $i',
            startedAt: DateTime.utc(2026, 2, 6 - i),
            sets: [_s('Bench', reps: 5, weight: 100)]),
    ];
    await _pump(tester, workouts);
    // The five newest render; the sixth (oldest) is dropped.
    expect(find.text('Session 0'), findsOneWidget);
    expect(find.text('Session 4'), findsOneWidget);
    expect(find.text('Session 5'), findsNothing);
  });

  testWidgets('taps fire onOpenWorkout (row) and onViewAll (link)',
      (tester) async {
    String? opened;
    var viewedAll = false;
    await _pump(
      tester,
      [
        _w('a',
            title: 'Push day',
            sets: [_s('Bench', reps: 5, weight: 100)]),
      ],
      onOpen: (id) => opened = id,
      onViewAll: () => viewedAll = true,
    );
    await tester.tap(find.text('Push day'));
    expect(opened, 'a');
    await tester.tap(find.text('View all'));
    expect(viewedAll, isTrue);
  });
}

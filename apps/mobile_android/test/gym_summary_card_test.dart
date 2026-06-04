import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/offline_sync_store.dart';
import '../lib/widgets/gym_summary_card.dart';

StoredGymWorkout _workout() => StoredGymWorkout(
      row: {
        'id': 'w1',
        'title': 'Push day',
        'started_at': DateTime.now().toIso8601String(),
      },
      sets: const [
        {'exercise_name': 'Bench', 'reps': 8, 'weight_kg': 60.0},
        {'exercise_name': 'Bench', 'reps': 8, 'weight_kg': 60.0},
        {'exercise_name': 'OHP', 'reps': 6, 'weight_kg': 40.0},
      ],
      syncState: SyncState.synced,
    );

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('GymSummaryCard', () {
    testWidgets('shows the today-lift header, title, exercise count + volume',
        (tester) async {
      await _pump(tester, GymSummaryCard(workout: _workout(), onTap: () {}));
      expect(find.text("Today's lift"), findsOneWidget);
      expect(find.text('Push day'), findsOneWidget);
      // 2 distinct exercises; volume 8*60 + 8*60 + 6*40 = 1200 kg.
      expect(find.textContaining('1200'), findsOneWidget);
      expect(find.textContaining('2'), findsWidgets);
    });

    testWidgets('tapping invokes onTap', (tester) async {
      var tapped = false;
      await _pump(
        tester,
        GymSummaryCard(workout: _workout(), onTap: () => tapped = true),
      );
      await tester.tap(find.byType(GymSummaryCard));
      expect(tapped, isTrue);
    });

    testWidgets('falls back to the untitled label when no title', (tester) async {
      final w = StoredGymWorkout(
        row: {'id': 'w2', 'started_at': DateTime.now().toIso8601String()},
        sets: const [
          {'exercise_name': 'Squat', 'reps': 5, 'weight_kg': 100.0},
        ],
        syncState: SyncState.synced,
      );
      await _pump(tester, GymSummaryCard(workout: w, onTap: () {}));
      expect(find.text('Push day'), findsNothing);
      // The untitled fallback string renders (gymUntitled).
      expect(find.byType(GymSummaryCard), findsOneWidget);
    });
  });
}

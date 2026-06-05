import 'package:api_client/api_client.dart' show ActivityRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart' show DistanceUnit;
import '../lib/widgets/activity_timeline_list.dart';

ActivityRow _row(String id, String kind, DateTime at, Map<String, dynamic> summary) =>
    ActivityRow(id: id, kind: kind, startedAt: at, summary: summary);

Future<void> _pump(
  WidgetTester tester,
  List<ActivityRow> rows, {
  void Function(ActivityRow)? onRun,
  void Function(ActivityRow)? onLift,
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ActivityTimelineList(
        activities: rows,
        unit: DistanceUnit.km,
        onTapRun: onRun ?? (_) {},
        onTapLift: onLift ?? (_) {},
        onRefresh: () async {},
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets('empty list shows the timeline empty state', (tester) async {
    await _pump(tester, const []);
    expect(find.text('Nothing logged in this view yet.'), findsOneWidget);
  });

  testWidgets('renders run / lift / meal rows with per-kind summaries',
      (tester) async {
    final now = DateTime.now();
    await _pump(tester, [
      _row('r1', 'run', now, {'distance_m': 8200, 'duration_s': 2530}),
      _row('l1', 'lift', now,
          {'title': 'Push day', 'set_count': 5, 'volume_kg': 12400}),
      _row('m1', 'meal', now, {'item_name': 'Chicken bowl', 'calories': 640}),
    ]);
    // Run: distance primary (8.20 km), duration secondary (42m 10s).
    expect(find.text('8.20 km'), findsOneWidget);
    expect(find.text('42m 10s'), findsOneWidget);
    // Lift: title primary, "5 sets · 12400 kg" secondary.
    expect(find.text('Push day'), findsOneWidget);
    expect(find.textContaining('5 sets'), findsOneWidget);
    // Meal: item primary, calories secondary.
    expect(find.text('Chicken bowl'), findsOneWidget);
    expect(find.text('640 kcal'), findsOneWidget);
    // Today header.
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('run and lift rows are tappable, meal is not', (tester) async {
    final now = DateTime.now();
    String? tappedRun;
    String? tappedLift;
    await _pump(
      tester,
      [
        _row('r1', 'run', now, {'distance_m': 5000, 'duration_s': 1500}),
        _row('l1', 'lift', now, {'title': 'Legs', 'set_count': 4, 'volume_kg': 8000}),
        _row('m1', 'meal', now, {'item_name': 'Oats', 'calories': 300}),
      ],
      onRun: (r) => tappedRun = r.id,
      onLift: (r) => tappedLift = r.id,
    );
    await tester.tap(find.text('5.00 km'));
    expect(tappedRun, 'r1');
    await tester.tap(find.text('Legs'));
    expect(tappedLift, 'l1');
    // Meal row has no chevron (read-only).
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
  });

  testWidgets('lift volume renders in the user weight unit (kg default)',
      (tester) async {
    await _pump(tester, [
      _row('l1', 'lift', DateTime.now(),
          {'title': 'Bench', 'set_count': 3, 'volume_kg': 5000}),
    ]);
    expect(find.textContaining('kg'), findsOneWidget);
  });
}

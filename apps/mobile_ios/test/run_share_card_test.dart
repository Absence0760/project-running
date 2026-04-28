import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/preferences.dart';
import 'package:mobile_android/run_stats.dart';
import 'package:mobile_android/widgets/run_share_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Run _run({
  double distanceMetres = 5000,
  Duration duration = const Duration(minutes: 25),
  List<Waypoint> track = const [],
  String title = 'Morning run',
}) =>
    Run(
      id: 'r1',
      startedAt: DateTime.utc(2026, 4, 15, 8, 0),
      duration: duration,
      distanceMetres: distanceMetres,
      source: RunSource.app,
      track: track,
      metadata: {'title': title, 'activity_type': 'run'},
    );

Future<Preferences> _makePrefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

Future<void> _pump(WidgetTester tester, Run run, Preferences prefs) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 500, // 4:5 ratio
          child: RunShareCard(
            run: run,
            preferences: prefs,
            title: run.metadata?['title'] as String? ?? 'Run',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(Duration.zero);
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  group('RunShareCard', () {
    testWidgets('renders the run title and date', (tester) async {
      final prefs = await _makePrefs();
      final run = _run();
      await _pump(tester, run, prefs);
      expect(find.text('Morning run'), findsOneWidget);
      expect(find.textContaining('15 Apr 2026'), findsOneWidget);
    });

    testWidgets('renders Distance, Time, and Pace stat labels', (tester) async {
      final prefs = await _makePrefs();
      final run = _run();
      await _pump(tester, run, prefs);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
      expect(find.text('PACE'), findsOneWidget);
    });

    testWidgets('renders the run-app brand label', (tester) async {
      final prefs = await _makePrefs();
      final run = _run();
      await _pump(tester, run, prefs);
      expect(find.text('RUN'), findsOneWidget);
    });

    testWidgets('renders directions_run icon instead of a map when track has fewer than 2 points',
        (tester) async {
      final prefs = await _makePrefs();
      final run = _run(track: const []);
      await _pump(tester, run, prefs);
      expect(find.byIcon(Icons.directions_run), findsOneWidget);
    });

    testWidgets('renders formatted distance in km for km preference',
        (tester) async {
      final prefs = await _makePrefs();
      final run = _run(distanceMetres: 5000);
      await _pump(tester, run, prefs);
      // km format: "5.00"
      expect(
        find.textContaining(
          UnitFormat.distanceValue(5000, DistanceUnit.km),
        ),
        findsOneWidget,
      );
    });
  });
}

// The challenge progress bar: what a value is CALLED and what UNIT it is
// printed in, and what the bar is entitled to claim about it.
//
// Nothing measured this file. `check_constraint_unions.mjs` holds the two
// switches to `challenges_metric_ck`'s vocabulary, so a metric with no arm
// fails a PR — but that guard reads case LABELS, not what the arms return. An
// arm that exists and formats the wrong quantity is invisible to it: a `vert`
// board printing "5.00 km" for 5000 m of climbing, or an `activity_count`
// board printing "0.01 km" for 12 activities, both pass the vocabulary rail
// and both are wrong on screen. The unit split is the whole reason the two
// helpers exist, so it is what these tests pin.
//
// The widget half pins the three claims the bar must not make: a bar drawn on
// a goal-less board (a fill nobody measured), a "Complete" pill below the
// goal, and a pace verdict on a challenge with no window to pace against.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show ProgressBar;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/widgets/challenge_form_sheet.dart' show kChallengeMetrics;
import '../lib/widgets/challenge_progress_bar.dart';

late AppLocalizations l10n;

Future<void> _useUnit(bool miles) async {
  SharedPreferences.setMockInitialValues({'use_miles': miles});
  final prefs = Preferences();
  await prefs.init();
  registerActivePreferences(prefs);
}

Future<void> _pumpBar(
  WidgetTester tester, {
  required String metric,
  required num value,
  num? goal,
  DateTime? startsAt,
  DateTime? endsAt,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ChallengeProgressBar(
          metric: metric,
          value: value,
          goal: goal,
          startsAt: startsAt,
          endsAt: endsAt,
        ),
      ),
    ),
  );
  await tester.pump();
}

double? _barValue(WidgetTester tester) =>
    tester.widgetList<ProgressBar>(find.byType(ProgressBar)).single.value;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() => _useUnit(false));

  tearDownAll(resetActivePreferencesForTest);

  group('challengeMetricLabel', () {
    // The `default:` arm answers "Distance" for anything it has not heard of,
    // so a sixth metric added to `challenges_metric_ck` and to
    // `kChallengeMetrics` without an arm here would be NAMED as a distance
    // board on the list, the detail screen and the create form at once.
    test('every metric in the vocabulary gets a name of its own', () {
      final labels = {
        for (final m in kChallengeMetrics) m: challengeMetricLabel(l10n, m),
      };
      expect(labels.values.toSet(), hasLength(kChallengeMetrics.length),
          reason: 'two metrics share a label, so at least one is falling '
              'through to the distance default: $labels');
    });

    test('names each metric for what it counts', () {
      expect(challengeMetricLabel(l10n, 'distance'), 'Distance');
      expect(challengeMetricLabel(l10n, 'duration'), 'Time');
      expect(challengeMetricLabel(l10n, 'vert'), 'Elevation');
      expect(challengeMetricLabel(l10n, 'activity_count'), 'Activities');
      expect(challengeMetricLabel(l10n, 'streak_days'), 'Active days');
    });
  });

  group('challengeValueLabel', () {
    test('one value reads differently under every metric', () {
      final labels = {
        for (final m in kChallengeMetrics) m: challengeValueLabel(l10n, m, 5000),
      };
      expect(labels.values.toSet(), hasLength(kChallengeMetrics.length),
          reason: 'a metric is being printed in another metric\'s unit: '
              '$labels');
    });

    test('each metric prints in its own unit', () {
      expect(challengeValueLabel(l10n, 'distance', 5000), '5.00 km');
      expect(challengeValueLabel(l10n, 'vert', 5000), '5000 m');
      expect(challengeValueLabel(l10n, 'duration', 5000), '1h 23m');
      expect(challengeValueLabel(l10n, 'activity_count', 5000), '5000');
      expect(challengeValueLabel(l10n, 'streak_days', 5000), '5000 days');
    });

    // The regression that hides best: a count is a small number, and a small
    // number divided by 1000 still renders as a plausible-looking distance.
    test('a count is a count, never a distance', () {
      final label = challengeValueLabel(l10n, 'activity_count', 12);
      expect(label, '12');
      expect(label, isNot(contains('km')));
      expect(label, isNot(contains('mi')));
    });

    test('an elevation is not printed as a distance', () {
      final label = challengeValueLabel(l10n, 'vert', 12000);
      expect(label, '12000 m');
      expect(label, isNot(contains('km')));
    });

    group('under a miles preference', () {
      setUp(() => _useUnit(true));

      // Both unit-bearing metrics go through the pref formatters rather than
      // a hard-coded km/m, which is what an inlined `metres / 1000` would
      // silently undo for every mile-unit runner.
      test('distance reads in miles', () {
        final label = challengeValueLabel(l10n, 'distance', 5000);
        expect(label, '3.11 mi');
        expect(label, isNot(contains('km')));
      });

      test('elevation reads in feet', () {
        final label = challengeValueLabel(l10n, 'vert', 1000);
        expect(label, '3281 ft');
        expect(label, isNot(endsWith(' m')));
      });

      test('a count and a day tally are unit-free either way', () {
        expect(challengeValueLabel(l10n, 'activity_count', 12), '12');
        expect(challengeValueLabel(l10n, 'streak_days', 12), '12 days');
      });
    });

    group('duration', () {
      // The hours component is dropped below the hour and shown from it, so
      // the boundary is where a formatting slip is visible.
      test('drops the hours component below an hour', () {
        expect(challengeValueLabel(l10n, 'duration', 3599), '59m');
        expect(challengeValueLabel(l10n, 'duration', 0), '0m');
      });

      test('carries the hours component from exactly one hour', () {
        expect(challengeValueLabel(l10n, 'duration', 3600), '1h 0m');
      });

      test('a fractional second count rounds rather than truncating', () {
        expect(challengeValueLabel(l10n, 'duration', 3599.6), '1h 0m');
      });

      test('a multi-day total keeps counting in hours', () {
        expect(challengeValueLabel(l10n, 'duration', 100 * 3600 + 60), '100h 1m');
      });
    });
  });

  group('ChallengeProgressBar', () {
    testWidgets('a goal-less board draws no bar and claims no completion',
        (tester) async {
      // `progressFraction` is null without a goal, and a bar rendered at 0
      // would state a share of a target that does not exist.
      await _pumpBar(tester, metric: 'distance', value: 42000, goal: null);

      expect(find.text('42.00 km'), findsOneWidget);
      expect(find.byType(ProgressBar), findsNothing);
      expect(find.text(l10n.challengesProgressComplete), findsNothing);
    });

    testWidgets('a goal renders value-of-goal and fills the bar to the share',
        (tester) async {
      await _pumpBar(tester, metric: 'distance', value: 25000, goal: 100000);

      expect(find.text('25.00 km of 100.00 km'), findsOneWidget);
      expect(_barValue(tester), closeTo(0.25, 1e-9));
      expect(find.text(l10n.challengesProgressComplete), findsNothing);
    });

    testWidgets('reaching the goal shows the completion label', (tester) async {
      await _pumpBar(tester, metric: 'distance', value: 100000, goal: 100000);

      expect(find.text(l10n.challengesProgressComplete), findsOneWidget);
      expect(_barValue(tester), 1.0);
    });

    testWidgets('overshooting the goal clamps the fill rather than overflowing',
        (tester) async {
      await _pumpBar(tester, metric: 'distance', value: 250000, goal: 100000);

      expect(_barValue(tester), 1.0);
      expect(find.text(l10n.challengesProgressComplete), findsOneWidget);
    });

    testWidgets('a goal in the metric\'s own unit is not restated in another',
        (tester) async {
      await _pumpBar(tester, metric: 'activity_count', value: 3, goal: 10);

      expect(find.text('3 of 10'), findsOneWidget);
      expect(_barValue(tester), closeTo(0.3, 1e-9));
    });

    group('the pace hint', () {
      DateTime now() => DateTime.now();

      testWidgets('says nothing without a window to pace against',
          (tester) async {
        // `challengePace` needs both bounds; a challenge that has not been
        // given them must not be graded off a window of zero length.
        await _pumpBar(tester, metric: 'distance', value: 25000, goal: 100000);

        expect(find.text(l10n.challengesPaceBehind), findsNothing);
        expect(find.text(l10n.challengesPaceAhead), findsNothing);
        expect(find.text(l10n.challengesPaceOnTrack), findsNothing);
      });

      testWidgets('behind the line names the verdict and the daily rate owed',
          (tester) async {
        // 80 % of the window elapsed against 10 % of the goal banked; 90 km
        // left over the 2 days remaining is 45 km a day.
        await _pumpBar(
          tester,
          metric: 'distance',
          value: 10000,
          goal: 100000,
          startsAt: now().subtract(const Duration(days: 8)),
          endsAt: now().add(const Duration(days: 2)),
        );

        expect(find.text(l10n.challengesPaceBehind), findsOneWidget);
        expect(find.text(l10n.challengesPaceNeedPerDay('45.00 km')),
            findsOneWidget);
      });

      testWidgets('ahead of the line names the verdict and owes no rate',
          (tester) async {
        await _pumpBar(
          tester,
          metric: 'distance',
          value: 50000,
          goal: 100000,
          startsAt: now().subtract(const Duration(days: 2)),
          endsAt: now().add(const Duration(days: 8)),
        );

        expect(find.text(l10n.challengesPaceAhead), findsOneWidget);
        expect(find.textContaining('per day to finish'), findsNothing,
            reason: 'a runner ahead of the line is not owed a catch-up rate');
      });

      testWidgets('inside the tolerance band it reads as on track',
          (tester) async {
        await _pumpBar(
          tester,
          metric: 'distance',
          value: 20000,
          goal: 100000,
          startsAt: now().subtract(const Duration(days: 2)),
          endsAt: now().add(const Duration(days: 8)),
        );

        expect(find.text(l10n.challengesPaceOnTrack), findsOneWidget);
      });

      testWidgets('a finished goal is not then told it is behind pace',
          (tester) async {
        // The verdict row is suppressed by completion, not by the pace
        // helper: `challengePace` stops grading at the goal, and a bar that
        // asked anyway would have nothing to render. Both halves must hold or
        // a completed challenge nags about a rate it no longer needs.
        await _pumpBar(
          tester,
          metric: 'distance',
          value: 100000,
          goal: 100000,
          startsAt: now().subtract(const Duration(days: 8)),
          endsAt: now().add(const Duration(days: 2)),
        );

        expect(find.text(l10n.challengesProgressComplete), findsOneWidget);
        expect(find.text(l10n.challengesPaceBehind), findsNothing);
        expect(find.textContaining('per day to finish'), findsNothing);
      });

      testWidgets('a window that has not opened yet is not graded',
          (tester) async {
        await _pumpBar(
          tester,
          metric: 'distance',
          value: 0,
          goal: 100000,
          startsAt: now().add(const Duration(days: 2)),
          endsAt: now().add(const Duration(days: 12)),
        );

        expect(find.text(l10n.challengesPaceBehind), findsNothing,
            reason: 'nobody is behind on a challenge that has not started');
        expect(find.text(l10n.challengesPaceOnTrack), findsNothing);
      });

      testWidgets('a closed window is not graded either', (tester) async {
        await _pumpBar(
          tester,
          metric: 'distance',
          value: 10000,
          goal: 100000,
          startsAt: now().subtract(const Duration(days: 12)),
          endsAt: now().subtract(const Duration(days: 2)),
        );

        expect(find.text(l10n.challengesPaceBehind), findsNothing,
            reason: 'a finished challenge has no pace left to keep');
        expect(find.textContaining('per day to finish'), findsNothing);
      });
    });
  });
}

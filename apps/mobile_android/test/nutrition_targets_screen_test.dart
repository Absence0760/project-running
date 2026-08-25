import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/nutrition_screen.dart';
import '../lib/screens/nutrition_targets_screen.dart';
import '../lib/screens/settings_body_metrics_screen.dart';
import '../lib/settings_sync.dart';

/// 70 kg / 175 cm / 30 y / male with a 10 km run logged today, which pins
/// every term of the derivation:
///   BMR      = 10*70 + 6.25*175 - 5*30 + 5      = 1648.75 -> 1649
///   base     = round(1648.75 * 1.55 / 10) * 10  = 2560
///   exercise = round(1.036 * 70 * 10)           = 725
///   total    = 2560 + 725                       = 3285
class _MetricsApi extends ApiClient {
  _MetricsApi({this.runDistanceM = 10000});

  final double runDistanceM;
  int profileCalls = 0;

  @override
  String? get userId => 'u1';

  @override
  Future<UserProfileRow?> fetchMyProfile() async {
    profileCalls++;
    return UserProfileRow(
      shadowHidden: false,
      id: 'u1',
      heightCm: 175,
      gender: 'male',
      // January the 1st, so the age is 30 whatever day the suite runs on.
      dateOfBirth: DateTime.utc(DateTime.now().year - 30, 1, 1),
    );
  }

  @override
  Future<double?> fetchLatestBodyWeightKg() async => 70.0;

  @override
  Future<List<ActivityRow>> fetchActivities({int limit = 100}) async => [
        ActivityRow(
          id: 'r1',
          kind: ActivityRow.kindRun,
          startedAt: DateTime.now(),
          summary: <String, dynamic>{'distance_m': runDistanceM},
        ),
      ];

  @override
  Future<List<FoodLogRow>> fetchFoodLog({
    DateTime? from,
    DateTime? to,
    int limit = 500,
  }) async =>
      const [];
}

/// Every read fails, so the screen must offer a retry rather than render a
/// derivation off nothing.
class _FailingApi extends ApiClient {
  int profileCalls = 0;

  @override
  String? get userId => 'u1';

  @override
  Future<UserProfileRow?> fetchMyProfile() async {
    profileCalls++;
    throw Exception('offline');
  }
}

/// Records what the two levers write. `updateUniversal` is the same path the
/// consent-gated body-metrics editor uses for these two keys, so the screens
/// cannot disagree about where they land.
class _RecordingSync extends SettingsSyncService {
  _RecordingSync(Preferences prefs) : super(preferences: prefs);

  final List<Map<String, dynamic>> writes = [];

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    writes.add(changes);
  }
}

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// The derivation, the levers and the metrics card do not fit one 800x600 test
/// viewport, and a `ListView` does not build what it has not scrolled to.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 200);
  await tester.pump();
}

Future<void> _scrollToTop(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, 900));
  await tester.pumpAndSettle();
}

Future<({LocalFoodStore store, Directory dir})> _foodStore(String tag) async {
  final dir = Directory.systemTemp.createTempSync('nutrition_targets_$tag');
  final store = LocalFoodStore();
  await store.init(overrideDirectory: dir);
  return (store: store, dir: dir);
}

void main() {
  setUpAll(() => initializeDateFormatting());
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(resetActivePreferencesForTest);

  group('NutritionTargetsScreen', () {
    testWidgets('shows every term of the derivation and the macro split',
        (tester) async {
      await tester.pumpWidget(_app(NutritionTargetsScreen(
        api: _MetricsApi(),
        settingsSync: null,
      )));
      await _settle(tester);

      expect(find.text('Resting metabolism'), findsOneWidget);
      expect(find.text('1649 kcal'), findsOneWidget);
      expect(find.text('× 1.55'), findsOneWidget);
      expect(find.text('0 kcal'), findsOneWidget);
      expect(find.text('Base goal'), findsOneWidget);
      expect(find.text('2560 kcal'), findsOneWidget);
      expect(find.text("Today's workouts"), findsOneWidget);
      expect(find.text('+725 kcal'), findsOneWidget);
      expect(find.text('3285 kcal'), findsOneWidget);

      // Macros: 1.8 g/kg protein, 30 % of calories as fat, carbs the rest.
      expect(find.text('126 g'), findsOneWidget);
      expect(find.text('110 g'), findsOneWidget);
      expect(find.text('448 g'), findsOneWidget);
    });

    testWidgets('the exercise row is absent when nothing was logged today',
        (tester) async {
      await tester.pumpWidget(_app(NutritionTargetsScreen(
        api: _MetricsApi(runDistanceM: 0),
        settingsSync: null,
      )));
      await _settle(tester);

      expect(find.text("Today's workouts"), findsNothing);
      // Total and base coincide with no add-on, so both cells read the base.
      expect(find.text('2560 kcal'), findsNWidgets(2));
    });

    testWidgets('changing the weight goal persists it and re-derives the goal',
        (tester) async {
      final sync = _RecordingSync(await _prefs());
      await tester.pumpWidget(_app(NutritionTargetsScreen(
        api: _MetricsApi(),
        settingsSync: sync,
      )));
      await _settle(tester);
      expect(find.text('Maintain weight'), findsOneWidget);

      // "Goal" also names the derivation's goal-delta row, so scope the tap
      // to the lever.
      await _scrollTo(tester, find.widgetWithText(ListTile, 'Goal'));
      await tester.tap(find.widgetWithText(ListTile, 'Goal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lose weight'));
      await tester.pumpAndSettle();
      await _scrollToTop(tester);

      expect(sync.writes, [
        <String, dynamic>{'nutrition_goal': 'lose'}
      ]);
      // -500 kcal off the base: round(2555.5625 - 500) to the nearest 10.
      expect(find.text('-500 kcal'), findsOneWidget);
      expect(find.text('2060 kcal'), findsOneWidget);
      expect(find.text('2785 kcal'), findsOneWidget);
    });

    testWidgets('changing the activity level persists it and re-derives',
        (tester) async {
      final sync = _RecordingSync(await _prefs());
      await tester.pumpWidget(_app(NutritionTargetsScreen(
        api: _MetricsApi(),
        settingsSync: sync,
      )));
      await _settle(tester);

      await _scrollTo(tester, find.widgetWithText(ListTile, 'Activity level'));
      await tester.tap(find.widgetWithText(ListTile, 'Activity level'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mostly sitting (desk job)'));
      await tester.pumpAndSettle();
      await _scrollToTop(tester);

      expect(sync.writes, [
        <String, dynamic>{'nutrition_activity_level': 'sedentary'}
      ]);
      expect(find.text('× 1.2'), findsOneWidget);
      // 1648.75 * 1.2 = 1978.5 -> 1980 base, + 725 exercise.
      expect(find.text('1980 kcal'), findsOneWidget);
      expect(find.text('2705 kcal'), findsOneWidget);
    });

    testWidgets('body metrics are read-only here — no Art 9 input surface',
        (tester) async {
      final prefs = await _prefs();
      registerActivePreferences(prefs);
      await tester.pumpWidget(_app(NutritionTargetsScreen(
        api: _MetricsApi(),
        settingsSync: null,
      )));
      await _settle(tester);
      await _scrollTo(tester, find.text('Edit in Settings'));

      expect(find.text('175 cm'), findsOneWidget);
      expect(find.text('70.0 kg'), findsOneWidget);
      expect(find.text('30 years'), findsOneWidget);
      expect(find.text('Male'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Edit in Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsBodyMetricsScreen), findsOneWidget);
    });

    testWidgets('with no metrics it explains what is missing, not a zero goal',
        (tester) async {
      final prefs = await _prefs();
      registerActivePreferences(prefs);
      await tester.pumpWidget(_app(const NutritionTargetsScreen(
        api: null,
        settingsSync: null,
      )));
      await _settle(tester);

      expect(find.text('No targets yet'), findsOneWidget);
      expect(find.text('Resting metabolism'), findsNothing);
      // The two levers stay editable with no metrics on file.
      await _scrollTo(tester, find.widgetWithText(ListTile, 'Goal'));
      expect(find.widgetWithText(ListTile, 'Activity level'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Goal'), findsOneWidget);
      await _scrollToTop(tester);

      await tester.tap(find.text('Add body metrics'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsBodyMetricsScreen), findsOneWidget);
    });

    testWidgets('a failed read offers a retry instead of a derivation',
        (tester) async {
      final api = _FailingApi();
      await tester.pumpWidget(_app(NutritionTargetsScreen(
        api: api,
        settingsSync: null,
      )));
      await _settle(tester);

      expect(find.text("Couldn't load your targets."), findsOneWidget);
      expect(find.text('Resting metabolism'), findsNothing);
      expect(api.profileCalls, 1);

      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(api.profileCalls, 2);
    });
  });

  group('the Nutrition rings card reaches Targets', () {
    testWidgets('with targets on file — not only from the empty state',
        (tester) async {
      // The regression this pins: the only route off the rings card used to be
      // the untargeted state's "Add body metrics" CTA, so the runner whose
      // targets existed had no way to the number the rings measure against.
      final f = await _foodStore('reachable_');
      try {
        await tester.pumpWidget(_app(NutritionScreen(
          api: _MetricsApi(),
          store: f.store,
        )));
        await _settle(tester);
        expect(find.text('Add body metrics'), findsNothing);

        await tester.tap(find.text('Targets'));
        await tester.pumpAndSettle();
        expect(find.byType(NutritionTargetsScreen), findsOneWidget);
      } finally {
        f.dir.deleteSync(recursive: true);
      }
    });

    testWidgets('and with no targets on file — the entry is ungated',
        (tester) async {
      final f = await _foodStore('ungated_');
      try {
        await tester.pumpWidget(_app(NutritionScreen(
          api: null,
          store: f.store,
        )));
        await _settle(tester);
        expect(find.text('Targets'), findsOneWidget);
      } finally {
        f.dir.deleteSync(recursive: true);
      }
    });
  });

  group('targets peer guards', () {
    final peer = File('lib/screens/nutrition_targets_screen.dart')
        .readAsStringSync();
    final day = File('lib/screens/nutrition_screen.dart').readAsStringSync();

    test('the rings card links the peer with no data gate around it', () {
      final block = day.substring(day.indexOf('onPressed: _openTargets'));
      expect(block.contains('nutritionTargetsLink'), isTrue);
      // A gate here would hide the peer from exactly the runner with no
      // targets yet — the one who needs it.
      final entry = day.substring(
        day.indexOf('Align(', day.indexOf('nutritionAddBodyMetrics')),
        day.indexOf('onPressed: _openTargets'),
      );
      expect(entry.contains('if ('), isFalse);
    });

    test('the peer is not a second Art 9 entry point', () {
      for (final banned in [
        'grantHealthDataConsent',
        'withdrawHealthDataConsent',
        'setMyHeightCm',
        'setMyDateOfBirth',
        'recordBodyWeightKg',
        'clearBodyWeightHistory',
        'TextField',
      ]) {
        expect(peer.contains(banned), isFalse,
            reason: '$banned duplicates the consent-gated surface');
      }
    });

    test('the peer reuses the engine rather than re-deriving it', () {
      expect(peer.contains("import '../nutrition_targets.dart';"), isTrue);
      for (final named in [
        'computeNutritionTargets',
        'mifflinStJeorBmr',
        'activityLevels',
        'goalKcalDelta',
        'proteinGPerKg',
        'fatKcalFraction',
        'minCalorieTarget',
      ]) {
        expect(peer.contains(named), isTrue, reason: '$named not reused');
      }
      // A copy of any of these would drift silently from the TS twin.
      for (final literal in ['1.8', '0.3', '1200', '-500']) {
        expect(peer.contains(literal), isFalse,
            reason: 'literal $literal re-derives what the engine exports');
      }
    });
  });
}

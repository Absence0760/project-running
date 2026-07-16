import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/settings_sync.dart';
import '../lib/widgets/intensity_card.dart';

Run _r({
  required DateTime startedAt,
  required int durationS,
  num? avgBpm,
}) =>
    Run(
      id: 'r-${startedAt.millisecondsSinceEpoch}',
      startedAt: startedAt,
      duration: Duration(seconds: durationS),
      distanceMetres: 5000,
      source: RunSource.app,
      metadata: avgBpm == null ? null : {'avg_bpm': avgBpm},
    );

/// Seeds a universal-bag value for [effective]; everything else falls through
/// to the caller's fallback. Never touches Supabase.
class _FakeSettingsService extends SettingsService {
  _FakeSettingsService(this._values)
      : super(deviceId: 'test-device', platform: 'android');

  final Map<String, dynamic> _values;

  @override
  T? effective<T>(String key, {T? fallback}) =>
      _values.containsKey(key) ? _values[key] as T? : fallback;
}

class _FakeSettingsSync extends SettingsSyncService {
  _FakeSettingsSync(Preferences prefs, this._service)
      : super(preferences: prefs);

  final SettingsService? _service;

  @override
  bool get synced => true;

  @override
  SettingsService? get service => _service;
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Run> runs,
  required List<int>? hrZones,
  required DateTime now,
  SettingsSyncService? settingsSync,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: IntensityCard(
            runs: runs,
            hrZones: hrZones,
            now: now,
            settingsSync: settingsSync,
          ),
        ),
      ),
    ),
  );
}

void main() {
  const zones = <int>[114, 133, 152, 171, 190];
  final now = DateTime(2026, 5, 1, 12);

  group('IntensityCard', () {
    testWidgets('renders nothing when hrZones is null', (tester) async {
      // The configure-HR-zones empty state is the Settings tile, not
      // the dashboard. Card must be invisible until the user has set
      // zones — otherwise we'd nag every day.
      await _pump(
        tester,
        runs: [_r(startedAt: now.subtract(const Duration(days: 1)), durationS: 1200, avgBpm: 140)],
        hrZones: null,
        now: now,
      );
      expect(find.text('TRAINING INTENSITY'), findsNothing);
    });

    testWidgets('renders nothing when no runs in window carry avg_bpm',
        (tester) async {
      await _pump(
        tester,
        runs: [
          _r(startedAt: now.subtract(const Duration(days: 1)), durationS: 1200),
        ],
        hrZones: zones,
        now: now,
      );
      expect(find.text('TRAINING INTENSITY'), findsNothing,
          reason: 'card must hide when the window has zero HR-tracked runs');
    });

    testWidgets('renders the header + window label when populated',
        (tester) async {
      await _pump(
        tester,
        runs: [
          _r(startedAt: now.subtract(const Duration(days: 1)), durationS: 1200, avgBpm: 145),
        ],
        hrZones: zones,
        now: now,
      );
      expect(find.text('TRAINING INTENSITY'), findsOneWidget);
      expect(find.text('last 30 days'), findsOneWidget);
    });

    testWidgets('renders five zone legend rows with percentages',
        (tester) async {
      // 100 / 200 / 300 / 400 / 500 → 6.7 / 13.3 / 20 / 26.7 / 33.3 %.
      // Rounded: 7 / 13 / 20 / 27 / 33.
      await _pump(
        tester,
        runs: [
          _r(startedAt: now.subtract(const Duration(days: 1)), durationS: 100, avgBpm: 100),
          _r(startedAt: now.subtract(const Duration(days: 2)), durationS: 200, avgBpm: 120),
          _r(startedAt: now.subtract(const Duration(days: 3)), durationS: 300, avgBpm: 140),
          _r(startedAt: now.subtract(const Duration(days: 4)), durationS: 400, avgBpm: 160),
          _r(startedAt: now.subtract(const Duration(days: 5)), durationS: 500, avgBpm: 180),
        ],
        hrZones: zones,
        now: now,
      );
      // Pin labels Z1..Z5.
      expect(find.text('Z1'), findsOneWidget);
      expect(find.text('Z5'), findsOneWidget);
      // Percentages — pin Z3 (20%) which is the cleanest math.
      expect(find.text('20%'), findsOneWidget);
    });

    testWidgets('helper text reports HR-tracked-run count (singular vs plural)',
        (tester) async {
      // Single run → "1 HR-tracked run".
      await _pump(
        tester,
        runs: [
          _r(startedAt: now.subtract(const Duration(days: 1)), durationS: 600, avgBpm: 140),
        ],
        hrZones: zones,
        now: now,
      );
      expect(find.text('Based on 1 HR-tracked run'), findsOneWidget);

      // Three runs → "3 HR-tracked runs".
      await _pump(
        tester,
        runs: [
          _r(startedAt: now.subtract(const Duration(days: 1)), durationS: 600, avgBpm: 120),
          _r(startedAt: now.subtract(const Duration(days: 2)), durationS: 600, avgBpm: 140),
          _r(startedAt: now.subtract(const Duration(days: 3)), durationS: 600, avgBpm: 160),
        ],
        hrZones: zones,
        now: now,
      );
      expect(find.text('Based on 3 HR-tracked runs'), findsOneWidget);
    });

    testWidgets('uses "<1%" for very small zone slivers', (tester) async {
      // A 5000 s easy run + a 1 s tiny zone-5 ping → zone 5 ~0.02 %.
      // Should not render "0%" (that's misleading); must render "<1%".
      await _pump(
        tester,
        runs: [
          _r(startedAt: now.subtract(const Duration(days: 1)), durationS: 5000, avgBpm: 100),
          _r(startedAt: now.subtract(const Duration(days: 2)), durationS: 1, avgBpm: 185),
        ],
        hrZones: zones,
        now: now,
      );
      expect(find.text('<1%'), findsOneWidget);
    });
  });

  group('IntensityCard age-estimated caveat (#268)', () {
    Preferences? prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = Preferences();
      await prefs!.init();
    });

    final hrRuns = [
      _r(startedAt: DateTime(2026, 4, 30, 12), durationS: 1200, avgBpm: 145),
    ];

    testWidgets(
        'derives fallback zones + shows the caveat when neither hr_zones nor max_hr is set',
        (tester) async {
      // No explicit hrZones passed, but settingsSync is wired with an empty
      // bag → the card derives age-estimated cutoffs, renders, and discloses.
      await _pump(
        tester,
        runs: hrRuns,
        hrZones: null,
        now: DateTime(2026, 5, 1, 12),
        settingsSync: _FakeSettingsSync(prefs!, _FakeSettingsService({})),
      );
      expect(find.text('TRAINING INTENSITY'), findsOneWidget,
          reason: 'derived zones should render the breakdown');
      expect(find.textContaining('age-estimated max HR'), findsOneWidget);
    });

    testWidgets('hides the caveat when a max_hr_bpm override is set',
        (tester) async {
      await _pump(
        tester,
        runs: hrRuns,
        hrZones: null,
        now: DateTime(2026, 5, 1, 12),
        settingsSync:
            _FakeSettingsSync(prefs!, _FakeSettingsService({'max_hr_bpm': 185})),
      );
      expect(find.text('TRAINING INTENSITY'), findsOneWidget);
      expect(find.textContaining('age-estimated max HR'), findsNothing);
    });

    testWidgets('hides the caveat when explicit hr_zones are set',
        (tester) async {
      await _pump(
        tester,
        runs: hrRuns,
        hrZones: null,
        now: DateTime(2026, 5, 1, 12),
        settingsSync: _FakeSettingsSync(
          prefs!,
          _FakeSettingsService({
            'hr_zones': {'z1': 110, 'z2': 130, 'z3': 150, 'z4': 170, 'z5': 190},
          }),
        ),
      );
      expect(find.text('TRAINING INTENSITY'), findsOneWidget);
      expect(find.textContaining('age-estimated max HR'), findsNothing);
    });

    testWidgets('no caveat when settingsSync is not wired (explicit zones only)',
        (tester) async {
      await _pump(
        tester,
        runs: hrRuns,
        hrZones: const [114, 133, 152, 171, 190],
        now: DateTime(2026, 5, 1, 12),
      );
      expect(find.text('TRAINING INTENSITY'), findsOneWidget);
      expect(find.textContaining('age-estimated max HR'), findsNothing);
    });
  });
}

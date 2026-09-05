// The mobile half of opt-in "runners nearby" discovery (issue #466,
// decisions §270): the Settings opt-in + the coarse-area setter behind it.
//
// The load-bearing property is that all of it is ABSENT while the default-off
// `ENABLE_NEARBY_RUNNERS` deploy gate holds — not merely disabled, and with no
// `my_discoverable_area` read either. Person-location is Art 9-adjacent and the
// flip is the owner + CISO/counsel sign-off.

import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/nearby_flag.dart';
import '../lib/preferences.dart';
import '../lib/screens/nearby_area_screen.dart';
import '../lib/screens/settings_preferences_screen.dart';

bool _supabaseReady = false;
Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  dotenv.loadFromString(isOptional: true);
  _supabaseReady = true;
}

void _setGate(bool on) {
  if (on) {
    dotenv.env[kNearbyRunnersEnvKey] = 'true';
  } else {
    dotenv.env.remove(kNearbyRunnersEnvKey);
  }
}

class _FakeApi extends ApiClient {
  _FakeApi({this.label, this.readThrows = false});

  String? label;
  bool readThrows;
  bool saveThrows = false;
  bool clearThrows = false;
  int readCalls = 0;
  int clearCalls = 0;
  final List<(double, double, String?)> saved = [];

  @override
  String? get userId => 'me';

  @override
  Future<String?> fetchMyDiscoverableArea() async {
    readCalls++;
    if (readThrows) throw Exception('read down');
    return label;
  }

  @override
  Future<String?> setDiscoverableArea(
      double lng, double lat, String? areaLabel) async {
    if (saveThrows) throw Exception('save down');
    saved.add((lng, lat, areaLabel));
    label = areaLabel;
    return areaLabel;
  }

  @override
  Future<void> clearDiscoverableArea() async {
    clearCalls++;
    if (clearThrows) throw Exception('clear down');
    label = null;
  }
}

/// A Nominatim answer — the no-MapTiler-key path the test env takes.
String _nominatim(List<(String, double, double)> places) => jsonEncode([
      for (final p in places)
        {
          'display_name': p.$1,
          'lat': p.$2.toString(),
          'lon': p.$3.toString(),
        },
    ]);

Future<String> Function(Uri) _fetcher(String body) => (Uri _) async => body;

Widget _wrapArea(NearbyAreaScreen screen) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: screen,
    );

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

/// Tall enough that the whole lazily-built preferences list is laid out, so a
/// row's absence is absence rather than "below the fold".
const _wholePage = Size(400, 8000);

Future<void> _pumpPrefs(
  WidgetTester tester,
  Preferences prefs, {
  ApiClient? api,
}) async {
  tester.view.physicalSize = _wholePage * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(
        apiClient: api,
        preferences: prefs,
        settingsSync: null,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(initializeDateFormatting);
  setUpAll(_ensureSupabase);
  tearDown(() => _setGate(false));

  group('Settings — the opt-in is gated', () {
    testWidgets('with the gate off neither row exists and nothing is read',
        (tester) async {
      _setGate(false);
      final api = _FakeApi(label: 'Richmond, VA');
      await _pumpPrefs(tester, await _prefs(), api: api);

      expect(find.text('Show me to runners nearby'), findsNothing);
      expect(find.text('Your area'), findsNothing);
      // The label read is itself a person-location read; it must not happen.
      expect(api.readCalls, 0);
      // The row this one sits beside is still there, so absence is the gate
      // and not a broken privacy section.
      expect(find.text('Show me in name search'), findsOneWidget);
    });

    testWidgets('with the gate on both rows appear and the label is shown',
        (tester) async {
      _setGate(true);
      final api = _FakeApi(label: 'Richmond, VA');
      await _pumpPrefs(tester, await _prefs(), api: api);

      expect(find.text('Show me to runners nearby'), findsOneWidget);
      expect(find.text('Your area'), findsOneWidget);
      expect(find.text('Current area: Richmond, VA'), findsOneWidget);
      expect(api.readCalls, 1);
    });

    testWidgets('with no ApiClient the area row is absent, the toggle is not',
        (tester) async {
      _setGate(true);
      await _pumpPrefs(tester, await _prefs());

      // The definer RPCs are unreachable without a client, so the row that
      // exists only to call them must not be offered.
      expect(find.text('Show me to runners nearby'), findsOneWidget);
      expect(find.text('Your area'), findsNothing);
    });
  });

  group('NearbyAreaScreen', () {
    testWidgets('shows the stored label', (tester) async {
      await tester.pumpWidget(_wrapArea(NearbyAreaScreen(
        api: _FakeApi(label: 'Richmond, VA'),
        geocodingFetcher: _fetcher('[]'),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Current area: Richmond, VA'), findsOneWidget);
      expect(find.text('Forget my area'), findsOneWidget);
    });

    testWidgets('with no area set, no destructive affordance is offered',
        (tester) async {
      await tester.pumpWidget(_wrapArea(NearbyAreaScreen(
        api: _FakeApi(),
        geocodingFetcher: _fetcher('[]'),
      )));
      await tester.pumpAndSettle();
      expect(find.text('No area set'), findsOneWidget);
      expect(find.text('Forget my area'), findsNothing);
    });

    testWidgets('a failed label read offers a retry, not a wrong claim',
        (tester) async {
      final api = _FakeApi(readThrows: true);
      await tester.pumpWidget(_wrapArea(NearbyAreaScreen(
        api: api,
        geocodingFetcher: _fetcher('[]'),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Could not load your area.'), findsOneWidget);
      expect(find.text('No area set'), findsNothing);

      api.readThrows = false;
      api.label = 'Bristol';
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Current area: Bristol'), findsOneWidget);
    });

    testWidgets('picking a searched place stores its centroid', (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(_wrapArea(NearbyAreaScreen(
        api: api,
        geocodingFetcher: _fetcher(_nominatim([
          ('Richmond, Virginia', 37.54, -77.44),
          ('Richmond, London', 51.46, -0.30),
        ])),
      )));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'richmond');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Both candidates are offered: the runner confirms WHICH Richmond, which
      // is the point of a picker over a geocode-the-top-hit.
      expect(find.text('Richmond, Virginia'), findsOneWidget);
      expect(find.text('Richmond, London'), findsOneWidget);

      await tester.tap(find.text('Richmond, London'));
      await tester.pump();

      expect(api.saved.length, 1);
      expect(api.saved.single.$1, closeTo(-0.30, 1e-9));
      expect(api.saved.single.$2, closeTo(51.46, 1e-9));
      expect(api.saved.single.$3, 'Richmond, London');
      expect(find.text('Current area: Richmond, London'), findsOneWidget);
    });

    testWidgets('an unavailable provider is not reported as no such place',
        (tester) async {
      await tester.pumpWidget(_wrapArea(NearbyAreaScreen(
        api: _FakeApi(),
        // A malformed body is what a down / rate-limited provider looks like.
        geocodingFetcher: _fetcher('not json'),
      )));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'richmond');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(
          find.text('Place search is unavailable right now.'), findsOneWidget);
      expect(find.text('No places matched that search.'), findsNothing);
    });

    testWidgets('a genuinely empty result says no places matched',
        (tester) async {
      await tester.pumpWidget(_wrapArea(NearbyAreaScreen(
        api: _FakeApi(),
        geocodingFetcher: _fetcher('[]'),
      )));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzqqxx');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('No places matched that search.'), findsOneWidget);
      expect(find.text('Place search is unavailable right now.'), findsNothing);
    });

    testWidgets('forgetting the area is confirmed first, and cancel is inert',
        (tester) async {
      final api = _FakeApi(label: 'Richmond, VA');
      await tester.pumpWidget(_wrapArea(NearbyAreaScreen(
        api: api,
        geocodingFetcher: _fetcher('[]'),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forget my area'));
      await tester.pumpAndSettle();
      // The confirm's action repeats the label, so scope the cancel tap to the
      // dialog rather than matching two identical strings.
      final dialog = find.byType(AlertDialog);
      expect(find.text('Forget your area?'), findsOneWidget);
      await tester.tap(find.descendant(of: dialog, matching: find.text('Cancel')));
      await tester.pumpAndSettle();
      expect(api.clearCalls, 0);
      expect(find.text('Current area: Richmond, VA'), findsOneWidget);

      await tester.tap(find.text('Forget my area'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Forget my area')));
      await tester.pumpAndSettle();

      expect(api.clearCalls, 1);
      expect(find.text('No area set'), findsOneWidget);
    });

    testWidgets('a failed clear keeps the area rather than lying about it',
        (tester) async {
      final api = _FakeApi(label: 'Richmond, VA');
      api.clearThrows = true;
      await tester.pumpWidget(_wrapArea(NearbyAreaScreen(
        api: api,
        geocodingFetcher: _fetcher('[]'),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forget my area'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Forget my area')));
      await tester.pumpAndSettle();

      expect(api.clearCalls, 1);
      expect(find.text('Current area: Richmond, VA'), findsOneWidget);
    });
  });
}

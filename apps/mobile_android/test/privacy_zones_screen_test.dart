import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/privacy_zones_screen.dart';
import '../lib/settings_sync.dart';

Position _fakePosition({double lat = 37.53, double lng = -77.45}) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

Future<({SettingsSyncService sync})> _makeSync() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return (sync: SettingsSyncService(preferences: prefs));
}

Future<void> _pump(
  WidgetTester tester, {
  required SettingsSyncService sync,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PrivacyZonesScreen(settingsSync: sync),
    ),
  );
  // Drain pending timers from flutter_map_cache + Dio so the
  // post-test "Timer is still pending" guard doesn\'t fire. The
  // May 2026 audit wired the screen onto the shared
  // CachedTileProvider; that provider schedules background timers
  // (cache eviction / Dio interceptor) that the bare single-pump
  // pattern doesn\'t flush.
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('PrivacyZonesScreen — initial render', () {
    testWidgets('renders the Privacy zones app-bar title', (tester) async {
      final s = await _makeSync();
      await _pump(tester, sync: s.sync);
      await tester.pump();
      expect(find.text('Privacy zones'), findsOneWidget);
    });

    testWidgets('renders the Save action in the app bar', (tester) async {
      // Reason: edits to the zone list are non-destructive until Save
      // is tapped — the action must be present so users can commit.
      final s = await _makeSync();
      await _pump(tester, sync: s.sync);
      await tester.pump();
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('renders a place-search field + a Locate-me FAB', (tester) async {
      // Both were missing — the picker had no way to navigate to the
      // user's area, so on a self-hosted-tiles setup it opened on a
      // far-away default and looked like a blank map.
      final s = await _makeSync();
      await _pump(tester, sync: s.sync);
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Search places…'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.my_location), findsOneWidget);
    });

    testWidgets('typing surfaces place results (Nominatim fallback)',
        (tester) async {
      final s = await _makeSync();
      Future<String> stub(Uri _) async => jsonEncode([
            {
              'display_name': 'Richmond, Virginia',
              'lat': '37.5407',
              'lon': '-77.4360',
            },
          ]);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PrivacyZonesScreen(settingsSync: s.sync, geocodingFetcher: stub),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search places…'),
        'Richmond',
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Richmond, Virginia'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('Locate FAB invokes the locate seam without crashing',
        (tester) async {
      final s = await _makeSync();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PrivacyZonesScreen(
            settingsSync: s.sync,
            locateFn: () async {
              calls++;
              return _fakePosition();
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      expect(calls, greaterThanOrEqualTo(1));
      await tester.pump(const Duration(seconds: 1));
    });
  });
}

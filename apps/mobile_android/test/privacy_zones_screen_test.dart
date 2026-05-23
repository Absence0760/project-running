import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/preferences.dart';
import '../lib/screens/privacy_zones_screen.dart';
import '../lib/settings_sync.dart';

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
    MaterialApp(home: PrivacyZonesScreen(settingsSync: sync)),
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
  });
}

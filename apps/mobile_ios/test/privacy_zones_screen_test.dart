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
}) {
  return tester.pumpWidget(
    MaterialApp(home: PrivacyZonesScreen(settingsSync: sync)),
  );
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

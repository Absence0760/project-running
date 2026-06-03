import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

/// `synced` true so the tiles are enabled; `service` null so the one-shot
/// locale backfill no-ops (it's gated on a real settings service) — letting
/// us assert the explicit language-pick write in isolation.
class _FakeSettingsSync extends SettingsSyncService {
  _FakeSettingsSync(Preferences prefs) : super(preferences: prefs);

  final List<Map<String, dynamic>> universalWrites = [];

  @override
  bool get synced => true;

  @override
  SettingsService? get service => null;

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    universalWrites.add(changes);
    notifyListeners();
  }
}

void main() {
  setUp(() async {
    await initializeDateFormatting();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('picking a language writes locale to the universal bag',
      (tester) async {
    final prefs = Preferences();
    await prefs.init();
    final sync = _FakeSettingsSync(prefs);

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(preferences: prefs, settingsSync: sync),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Language'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(ListTile, 'Language'));
    await tester.pumpAndSettle();

    // Pick German (endonym) from the radio dialog.
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();

    // Deep-equals (a Map literal matcher compares recursively; the backfill
    // no-ops here because `service` is null, so this is the only write).
    expect(sync.universalWrites, [
      {'locale': 'de'},
    ]);
  });
}

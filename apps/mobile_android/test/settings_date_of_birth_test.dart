import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

/// Reports `synced` so the bag-backed Date-of-birth tile is enabled;
/// `service` returns null so the subtitle falls through to "Not set".
class _FakeSettingsSync extends SettingsSyncService {
  _FakeSettingsSync(Preferences prefs) : super(preferences: prefs);

  @override
  bool get synced => true;

  @override
  SettingsService? get service => null;

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    notifyListeners();
  }
}

void main() {
  setUp(() async {
    await initializeDateFormatting();
  });

  testWidgets('Date of birth picker opens in year-selection mode',
      (tester) async {
    // Reason (#222): a birth year sits decades back, so the picker must
    // open on the year grid — the day-grid default forces paging month
    // by month (or spotting the tap-the-header affordance) to reach it.
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    final sync = _FakeSettingsSync(prefs);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPreferencesScreen(preferences: prefs, settingsSync: sync),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.scrollUntilVisible(
      find.text(l10n.prefsDateOfBirth),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text(l10n.prefsDateOfBirth));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.prefsDateOfBirth));
    await tester.pumpAndSettle();

    expect(find.byType(YearPicker), findsOneWidget);
  });
}

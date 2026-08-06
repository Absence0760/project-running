// Issue #666 I7 / I11 / I12: three surfaces were filed under Settings →
// Account, a screen whose subject is sign-in, backup and deletion.
//
//   - Guided runs is coach-driven training content. Web reaches it from a
//     rail on `/coach`; mobile now carries a labelled Coach peer.
//   - Privacy zones is a sharing preference. Web puts the picker in
//     `/settings/preferences`; mobile now matches.
//   - "View profile" was the third differently-named link to the viewer's own
//     ProfileScreen ("Your profile" on the You tile directly above the
//     Settings body, "My profile" on the dashboard toolbar). The duplicate is
//     deleted and the remaining two say the same thing.
//
// These pin the destinations at their new homes and pin the account screen
// clear of them — a re-parent that only adds is how a surface ends up with
// three names for one screen.

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/privacy_zones_screen.dart';
import '../lib/screens/settings_account_screen.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

class _FakeSettingsSync extends SettingsSyncService {
  _FakeSettingsSync(Preferences prefs) : super(preferences: prefs);

  @override
  bool get synced => true;

  @override
  SettingsService? get service => null;
}

class _SignedInApi extends ApiClient {
  @override
  String? get userId => 'viewer-1';
  @override
  String? get userEmail => 'runner@test.com';
}

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

Future<void> _pumpPreferences(WidgetTester tester, Preferences prefs) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SettingsPreferencesScreen(
      preferences: prefs,
      settingsSync: _FakeSettingsSync(prefs),
    ),
  ));
  await tester.pump();
}

Future<void> _pumpAccount(WidgetTester tester, Preferences prefs) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SettingsAccountScreen(
      apiClient: _SignedInApi(),
      preferences: prefs,
      settingsSync: _FakeSettingsSync(prefs),
    ),
  ));
  await tester.pump();
}

Future<void> _scrollTo(WidgetTester tester, Finder target) {
  return tester.scrollUntilVisible(
    target,
    250,
    scrollable: find.byType(Scrollable).first,
  );
}

void main() {
  group('privacy zones moved to Preferences (#666 I11)', () {
    testWidgets('the Preferences privacy section offers it and it opens',
        (tester) async {
      final prefs = await _prefs();
      await _pumpPreferences(tester, prefs);

      // Assert the population: the privacy section itself is on screen, so a
      // pass cannot come from an empty list that scrolled past nothing.
      await _scrollTo(tester, find.text('PRIVACY & SHARING'));
      expect(find.text('PRIVACY & SHARING'), findsOneWidget);

      await _scrollTo(tester, find.text('Privacy zones'));
      await tester.tap(find.text('Privacy zones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PrivacyZonesScreen), findsOneWidget);
    });

    testWidgets('the account screen no longer carries it', (tester) async {
      final prefs = await _prefs();
      await _pumpAccount(tester, prefs);

      // Population first: the account screen genuinely rendered its own body.
      expect(find.text('Delete account'), findsOneWidget);
      expect(find.text('Privacy zones'), findsNothing);
      expect(find.text('Guided runs'), findsNothing);
      expect(find.text('View profile'), findsNothing);
    });
  });
}

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

/// Serves a seeded universal bag through `effective` so the screen's
/// `_bagValue` reflects the stored opt-in state without a live Supabase.
class _FakeSettingsService extends SettingsService {
  _FakeSettingsService(this._bag)
      : super(deviceId: 'test-device', platform: 'android');

  final Map<String, dynamic> _bag;

  @override
  T? effective<T>(String key, {T? fallback}) =>
      (_bag[key] as T?) ?? fallback;
}

/// Records universal-bag writes and reports `synced` so the bag-backed
/// tiles are interactive. The optional [service] lets a seeded-state test
/// drive `_bagValue`.
class _FakeSettingsSync extends SettingsSyncService {
  _FakeSettingsSync(Preferences prefs, {SettingsService? service})
      : _service = service,
        super(preferences: prefs);

  final SettingsService? _service;
  final List<Map<String, dynamic>> universalWrites = [];

  @override
  bool get synced => true;

  @override
  SettingsService? get service => _service;

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    universalWrites.add(changes);
    notifyListeners();
  }
}

Future<({Preferences prefs, _FakeSettingsSync sync})> _setUp({
  SettingsService? service,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return (prefs: prefs, sync: _FakeSettingsSync(prefs, service: service));
}

Future<void> _pump(
  WidgetTester tester, {
  required Preferences prefs,
  required SettingsSyncService sync,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(preferences: prefs, settingsSync: sync),
    ),
  );
}

const _title = 'Tips & encouragement email';

void main() {
  setUp(() async {
    await initializeDateFormatting();
  });

  testWidgets('lifecycle-drip toggle defaults off when the key is absent',
      (tester) async {
    final s = await _setUp();
    await _pump(tester, prefs: s.prefs, sync: s.sync);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text(_title),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    final tile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, _title),
    );
    expect(tile.value, isFalse);
  });

  testWidgets('opting in writes email_lifecycle_drip=on to the bag',
      (tester) async {
    final s = await _setUp();
    await _pump(tester, prefs: s.prefs, sync: s.sync);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text(_title),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(SwitchListTile, _title));
    await tester.pumpAndSettle();

    expect(s.sync.universalWrites, [
      {'email_lifecycle_drip': 'on'},
    ]);
  });

  testWidgets('opting out writes email_lifecycle_drip=off (suppression-safe)',
      (tester) async {
    final service = _FakeSettingsService({'email_lifecycle_drip': 'on'});
    final s = await _setUp(service: service);
    await _pump(tester, prefs: s.prefs, sync: s.sync);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text(_title),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    // Seeded 'on' renders the switch checked.
    final before = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, _title),
    );
    expect(before.value, isTrue);

    // A seeded `service` triggers the on-mount locale mirror; assert the
    // toggle write is present rather than that it's the sole write.
    s.sync.universalWrites.clear();
    await tester.tap(find.widgetWithText(SwitchListTile, _title));
    await tester.pumpAndSettle();

    expect(s.sync.universalWrites, [
      {'email_lifecycle_drip': 'off'},
    ]);
  });
}

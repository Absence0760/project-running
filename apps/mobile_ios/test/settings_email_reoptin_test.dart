import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

class _FakeApi extends ApiClient {
  int clearCalls = 0;
  bool failClear = false;

  @override
  Future<int> clearMyUnsubscribeSuppression() async {
    clearCalls++;
    if (failClear) throw StateError('rpc unavailable');
    return 1;
  }
}

/// Serves the seeded bag so a toggle can start in the 'on' state — the only
/// way to exercise the opting-OUT branch, which must never clear a block.
class _FakeSettings extends SettingsService {
  _FakeSettings(this._values)
      : super(deviceId: 'test-device', platform: 'test');

  final Map<String, dynamic> _values;

  @override
  T? effective<T>(String key, {T? fallback}) =>
      _values.containsKey(key) ? _values[key] as T? : fallback;
}

class _FakeSettingsSync extends SettingsSyncService {
  _FakeSettingsSync(Preferences prefs, this._service)
      : super(preferences: prefs);

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

Future<({Preferences prefs, _FakeSettingsSync sync, _FakeApi api})> _setUp({
  Map<String, dynamic> bag = const {},
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return (
    prefs: prefs,
    sync: _FakeSettingsSync(prefs, bag.isEmpty ? null : _FakeSettings(bag)),
    api: _FakeApi(),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required Preferences prefs,
  required SettingsSyncService sync,
  required ApiClient api,
}) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(
        apiClient: api,
        preferences: prefs,
        settingsSync: sync,
      ),
    ),
  );
}

Future<void> _tapToggle(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.widgetWithText(SwitchListTile, label));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(SwitchListTile, label));
}

void main() {
  setUp(() async {
    await initializeDateFormatting();
  });

  testWidgets('opting into the weekly digest lifts the unsubscribe block',
      (tester) async {
    final s = await _setUp();
    await _pump(tester, prefs: s.prefs, sync: s.sync, api: s.api);
    await tester.pumpAndSettle();

    await _tapToggle(tester, 'Weekly digest email');
    await tester.pumpAndSettle();

    expect(s.sync.universalWrites, [
      {'email_weekly_digest': 'on'},
    ]);
    expect(s.api.clearCalls, 1);
  });

  testWidgets('opting into the lifecycle drip lifts the unsubscribe block',
      (tester) async {
    final s = await _setUp();
    await _pump(tester, prefs: s.prefs, sync: s.sync, api: s.api);
    await tester.pumpAndSettle();

    await _tapToggle(tester, 'Tips & encouragement email');
    await tester.pumpAndSettle();

    expect(s.sync.universalWrites, [
      {'email_lifecycle_drip': 'on'},
    ]);
    expect(s.api.clearCalls, 1);
  });

  testWidgets('opting out never clears a suppression', (tester) async {
    final s = await _setUp(bag: {'email_weekly_digest': 'on'});
    await _pump(tester, prefs: s.prefs, sync: s.sync, api: s.api);
    await tester.pumpAndSettle();

    await _tapToggle(tester, 'Weekly digest email');
    await tester.pumpAndSettle();

    // A seeded bag also triggers the screen's one-shot locale backfill on
    // first build, so assert on the toggle's own write rather than the list.
    expect(s.sync.universalWrites.last, {'email_weekly_digest': 'off'});
    expect(s.api.clearCalls, 0);
  });

  testWidgets('a failed clear is surfaced, not swallowed', (tester) async {
    final s = await _setUp();
    s.api.failClear = true;
    await _pump(tester, prefs: s.prefs, sync: s.sync, api: s.api);
    await tester.pumpAndSettle();

    await _tapToggle(tester, 'Weekly digest email');
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('Emails may still be blocked'),
      findsOneWidget,
    );
  });
}

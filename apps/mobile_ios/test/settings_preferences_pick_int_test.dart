// The numeric-preference dialog on the Preferences screen used to pop `null`
// when the typed figure fell outside the caller's range — the same value
// Cancel pops — so a runner who typed 300 into max HR got exactly what a
// runner who changed their mind got: the dialog closed, nothing was written,
// and nothing was said. Every numeric preference on that screen shares the
// helper, so these pin the refusal for all of them (decisions § 1410).

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/hr_zones.dart' show kRestingHrBpmMax, kRestingHrBpmMin;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

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

  final List<Map<String, dynamic>> pushed = [];

  @override
  bool get synced => true;

  @override
  SettingsService? get service => _service;

  @override
  Future<void> updateUniversal(Map<String, dynamic> values) async {
    pushed.add(values);
  }
}

Future<(Preferences, _FakeSettingsSync)> _harness() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = Preferences();
  await prefs.init();
  final sync = _FakeSettingsSync(
    prefs,
    _FakeSettingsService(<String, dynamic>{'resting_hr_bpm': 55}),
  );
  return (prefs, sync);
}

Future<void> _openRestingHrDialog(WidgetTester tester) async {
  final (prefs, sync) = await _harness();
  tester.view.physicalSize = const Size(400, 8000) * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(preferences: prefs, settingsSync: sync),
    ),
  );
  await tester.pumpAndSettle();

  final row = find.widgetWithText(ListTile, 'Resting heart rate');
  await tester.scrollUntilVisible(row, 300, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

void main() {
  setUp(initializeDateFormatting);

  testWidgets('an out-of-range entry keeps the dialog open and names the range',
      (tester) async {
    await _openRestingHrDialog(tester);

    await tester.enterText(find.byType(TextField), '300');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // The refusal is the point: the dialog is still there to act on, and the
    // message states both ends of the range rather than only that something
    // was wrong.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text('Enter a value between $kRestingHrBpmMin and $kRestingHrBpmMax.'),
      findsOneWidget,
    );
  });

  testWidgets('unparseable text is refused the same way, not swallowed',
      (tester) async {
    await _openRestingHrDialog(tester);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text('Enter a value between $kRestingHrBpmMin and $kRestingHrBpmMax.'),
      findsOneWidget,
    );
  });

  testWidgets('Cancel is the outcome a refusal is no longer confused with',
      (tester) async {
    await _openRestingHrDialog(tester);

    await tester.enterText(find.byType(TextField), '300');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('correcting the entry clears the message and the save lands',
      (tester) async {
    await _openRestingHrDialog(tester);

    await tester.enterText(find.byType(TextField), '300');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a value between $kRestingHrBpmMin and $kRestingHrBpmMax.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '58');
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a value between $kRestingHrBpmMin and $kRestingHrBpmMax.'),
      findsNothing,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}

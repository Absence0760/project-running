// Issue #666 U8, mobile half: the `undo_window_s` universal preference is
// what makes a timed undo bar meet WCAG 2.2.1 (Timing Adjustable), so mobile
// needs the EDITOR as well as the read — a consumer without an adjust route
// would leave a phone user racing a countdown they cannot turn off.
//
// The row writes the bag AND the local mirror: the undo host reads its window
// at defer time from a module-level value hydrated off Preferences, so a pick
// that only reached the cloud bag would not change the next deletion, and
// would not survive a cold start offline.

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';
import '../lib/undo_queue.dart';

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

Future<({Preferences prefs, _FakeSettingsSync sync})> _setUp(
    Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = Preferences();
  await prefs.init();
  return (prefs: prefs, sync: _FakeSettingsSync(prefs));
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

Future<void> _openUndoWindow(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Undo window'),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('Undo window'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    await initializeDateFormatting();
  });

  testWidgets('the row shows the 8 s default on a fresh install',
      (tester) async {
    final f = await _setUp({});
    await _pump(tester, prefs: f.prefs, sync: f.sync);
    await tester.scrollUntilVisible(
      find.text('Undo window'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('8 seconds'), findsOneWidget);
  });

  testWidgets('picking "Until I dismiss it" writes the bag AND the mirror',
      (tester) async {
    final f = await _setUp({});
    await _pump(tester, prefs: f.prefs, sync: f.sync);
    await _openUndoWindow(tester);
    await tester.tap(find.text('Until I dismiss it').last);
    await tester.pumpAndSettle();

    expect(f.sync.universalWrites, [
      {'undo_window_s': 0}
    ]);
    expect(f.prefs.undoWindowS, 0);
    expect(find.text('Until I dismiss it'), findsOneWidget);
  });

  testWidgets('picking 30 s round-trips through the local mirror',
      (tester) async {
    final f = await _setUp({});
    await _pump(tester, prefs: f.prefs, sync: f.sync);
    await _openUndoWindow(tester);
    await tester.tap(find.text('30 seconds').last);
    await tester.pumpAndSettle();
    expect(f.prefs.undoWindowS, 30);

    final reloaded = Preferences();
    await reloaded.init();
    expect(reloaded.undoWindowS, 30, reason: 'survives a cold start offline');
  });

  testWidgets('a corrupt stored value reads back as 8 s, never as no-limit',
      (tester) async {
    final f = await _setUp({'undo_window_s': 7});
    expect(f.prefs.undoWindowS, kDefaultUndoWindowS);
    await _pump(tester, prefs: f.prefs, sync: f.sync);
    await tester.scrollUntilVisible(
      find.text('Undo window'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('8 seconds'), findsOneWidget);
    expect(find.text('Until I dismiss it'), findsNothing);
  });

  test('the bag overlay normalises a corrupt value rather than trusting it',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    final sync = _FakeSettingsSync(prefs);

    sync.debugApplyUniversal(<String, dynamic>{'undo_window_s': 30});
    expect(prefs.undoWindowS, 30);

    sync.debugApplyUniversal(<String, dynamic>{'undo_window_s': 'forever'});
    expect(prefs.undoWindowS, kDefaultUndoWindowS);

    sync.debugApplyUniversal(<String, dynamic>{'undo_window_s': 0});
    expect(prefs.undoWindowS, 0);

    // An ABSENT key must not walk a deliberate choice back to the default.
    sync.debugApplyUniversal(<String, dynamic>{});
    expect(prefs.undoWindowS, 0);
  });
}

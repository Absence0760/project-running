// The Build and Import FABs are one-shot entry points with a transition long
// enough to tap twice. Neither carried an in-flight guard, so a double-tap on
// Build stacked two route builders — build and save in the top one, it pops,
// and you land on a second empty builder as though the save was discarded.

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/routes_screen.dart';
import 'pump_until.dart';

class _FakeApi extends ApiClient {}

/// Holds the system picker open until the test releases it, so the in-flight
/// window can be inspected the way a real picker's would be.
class _HeldFilePicker {
  static const _channel =
      MethodChannel('miguelruivo.flutter.plugins.filepicker');

  final completer = Completer<List<Object?>?>();
  int calls = 0;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) {
      calls++;
      return completer.future;
    });
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
}

Future<Preferences> _makePrefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Future<void> _pump(WidgetTester tester, Preferences prefs) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RoutesScreen(
        apiClient: _FakeApi(),
        routeStore: LocalRouteStore(),
        preferences: prefs,
      ),
    ),
  );
}

Finder _fab(String label) =>
    find.widgetWithText(FloatingActionButton, label);

VoidCallback? _onPressed(WidgetTester tester, String label) =>
    tester.widget<FloatingActionButton>(_fab(label)).onPressed;

void main() {
  late _HeldFilePicker picker;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    picker = _HeldFilePicker()..install();
  });

  tearDown(() => picker.remove());

  testWidgets('a double-tap on Import opens exactly one picker',
      (tester) async {
    final prefs = await _makePrefs();
    await _pump(tester, prefs);
    await tester.pump();

    await tester.tap(_fab('Import'));
    await tester.pump();
    await tester.tap(_fab('Import'), warnIfMissed: false);
    await tester.pump();

    expect(picker.calls, 1);

    picker.completer.complete(null);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  });

  testWidgets('both FABs are disabled while one of them has a surface open',
      (tester) async {
    final prefs = await _makePrefs();
    await _pump(tester, prefs);
    await tester.pump();

    expect(_onPressed(tester, 'Build'), isNotNull);
    expect(_onPressed(tester, 'Import'), isNotNull);

    await tester.tap(_fab('Import'));
    await tester.pump();

    expect(_onPressed(tester, 'Build'), isNull,
        reason: 'the builder must not stack on top of an open picker');
    expect(_onPressed(tester, 'Import'), isNull);

    picker.completer.complete(null);
    await pumpUntil(tester, () => _onPressed(tester, 'Import') != null,
        describe: 'the released picker to re-arm both FABs');
    await tester.pumpAndSettle();

    expect(_onPressed(tester, 'Build'), isNotNull);
    expect(_onPressed(tester, 'Import'), isNotNull);
  });
}

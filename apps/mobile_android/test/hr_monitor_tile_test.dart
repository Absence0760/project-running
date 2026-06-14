import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/ble_heart_rate.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/settings_integrations_screen.dart';

/// Fake strap: reports a paired name and records whether forget() ran, so the
/// tile's confirm-before-unpair flow can be driven without a real BLE adapter.
class _FakeHeartRate extends BleHeartRate {
  _FakeHeartRate({String? name}) : _name = name;
  String? _name;
  int forgetCalls = 0;

  @override
  Future<String?> pairedName() async => _name;

  @override
  Future<void> forget() async {
    forgetCalls++;
    _name = null;
  }
}

Widget _host(BleHeartRate hr) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: HeartRateMonitorTile(heartRate: hr)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('forget confirms first; Cancel keeps the strap paired',
      (tester) async {
    final hr = _FakeHeartRate(name: 'Polar H10');
    await tester.pumpWidget(_host(hr));
    await tester.pumpAndSettle();

    expect(find.text('Paired: Polar H10'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // Confirm dialog — unpair is NOT immediate.
    expect(
      find.text(
          "Forget this heart rate monitor? You'll need to pair it again to use it during a run."),
      findsOneWidget,
    );

    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Cancel'),
    ));
    await tester.pumpAndSettle();

    expect(hr.forgetCalls, 0);
    expect(find.text('Paired: Polar H10'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('confirming forget unpairs the strap', (tester) async {
    final hr = _FakeHeartRate(name: 'Polar H10');
    await tester.pumpWidget(_host(hr));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Forget'),
    ));
    await tester.pumpAndSettle();

    expect(hr.forgetCalls, 1);
    expect(find.text('No strap paired — tap to scan'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });
}

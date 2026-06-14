import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/settings_integrations_screen.dart';

Widget _host() => const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: TreadmillTile()),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the not-paired subtitle when no treadmill is stored',
      (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
    });
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('Treadmill'), findsOneWidget);
    expect(find.text('No treadmill paired — tap to scan'), findsOneWidget);
    // Not-paired tile shows the chevron affordance, not the forget button.
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('shows the paired name + forget affordance when stored',
      (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({
        'treadmill_device_id': 'AA:BB:CC:DD:EE:FF',
        'treadmill_device_name': 'NordicTrack T9',
      });
    });
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('Paired: NordicTrack T9'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('forget confirms first; Cancel keeps the treadmill paired',
      (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({
        'treadmill_device_id': 'AA:BB:CC:DD:EE:FF',
        'treadmill_device_name': 'NordicTrack T9',
      });
    });
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // A confirm dialog appears — the unpair is NOT immediate.
    expect(
      find.text(
          "Forget this treadmill? You'll need to pair it again to use it during a run."),
      findsOneWidget,
    );

    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Cancel'),
    ));
    await tester.pumpAndSettle();

    // Still paired — Cancel left the device alone.
    expect(find.text('Paired: NordicTrack T9'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('confirming forget unpairs the treadmill', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({
        'treadmill_device_id': 'AA:BB:CC:DD:EE:FF',
        'treadmill_device_name': 'NordicTrack T9',
      });
    });
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // Confirming runs forget() — real SharedPreferences I/O, so anchor the
    // tap that triggers it inside runAsync.
    await tester.runAsync(() async {
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Forget'),
      ));
    });
    await tester.pumpAndSettle();

    expect(find.text('No treadmill paired — tap to scan'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });
}

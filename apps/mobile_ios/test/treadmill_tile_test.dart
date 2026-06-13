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
}

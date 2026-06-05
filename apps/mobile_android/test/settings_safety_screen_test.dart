import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/settings_safety_screen.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // api null: no Supabase round-trips — exercises the offline/empty UI
      // (the screen short-circuits the load when api/userId is null).
      home: const SettingsSafetyScreen(api: null),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('SettingsSafetyScreen', () {
    testWidgets('renders the add form, intro and empty state', (tester) async {
      await _pump(tester);
      expect(find.text('Safety contacts'), findsWidgets);
      expect(find.text('Contact email'), findsOneWidget);
      expect(find.text('Add contact'), findsOneWidget);
      expect(find.text('No safety contacts yet.'), findsOneWidget);
      // No incoming-requests section without pending requests.
      expect(find.text('Requests for you'), findsNothing);
    });

    testWidgets('invalid email shows the inline validation banner',
        (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), 'not-an-email');
      await tester.tap(find.text('Add contact'));
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      // Drain the top-banner auto-dismiss timer so no Timer outlives the test.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a valid-looking email passes the inline check',
        (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), 'partner@example.com');
      await tester.tap(find.text('Add contact'));
      await tester.pump();
      // With api == null the add is a no-op, but it must NOT trip the
      // invalid-email guard — that is the only client-side branch.
      expect(find.text('Enter a valid email address.'), findsNothing);
    });
  });
}

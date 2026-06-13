import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
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

/// Surfaces one incoming request and gates the confirm RPC so the in-flight
/// window stays open across a second tap.
class _SafetyApi extends ApiClient {
  int confirmCalls = 0;
  final Completer<void> confirmGate = Completer<void>();

  @override
  String? get userId => 'me';

  @override
  Future<List<SafetyContact>> fetchMySafetyContacts() async => const [];

  @override
  Future<List<PendingSafetyRequest>> fetchPendingSafetyRequests() async => [
        PendingSafetyRequest(
          id: 'req-1',
          ownerName: 'Jordan',
          createdAt: DateTime.utc(2026, 5, 1),
        ),
      ];

  @override
  Future<bool> confirmSafetyRequest(String id) async {
    confirmCalls++;
    await confirmGate.future;
    return true;
  }
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

    testWidgets('double-tapping Confirm on an incoming request fires once',
        (tester) async {
      final api = _SafetyApi();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();

      final confirm = find.widgetWithText(FilledButton, 'Confirm');
      expect(confirm, findsOneWidget);

      await tester.tap(confirm);
      await tester.pump();
      // Second tap while the first confirm is gated in flight — disabled now.
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pump();

      expect(api.confirmCalls, 1);

      api.confirmGate.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
    });
  });
}

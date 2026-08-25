import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/expected_return_dialog.dart';

/// A fixed "now" so the wall-clock labels the ladder renders are assertable.
final _now = DateTime(2026, 6, 1, 9, 0);

Future<void> _pumpHost(
  WidgetTester tester, {
  DateTime? armed,
  required void Function(ExpectedReturnChoice?) onResolved,
  DateTime? now,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async => onResolved(await showExpectedReturnDialog(
                context,
                armed: armed,
                now: () => now ?? _now,
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the ladder shows each offset with the clock time it lands on',
      (tester) async {
    await _pumpHost(tester, onResolved: (_) {});
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('In 30 min'), findsOneWidget);
    expect(find.text('In 1 hour'), findsOneWidget);
    expect(find.text('In 2 hours'), findsOneWidget);
    expect(find.text('In 4 hours'), findsOneWidget);
    expect(find.text('In 8 hours'), findsOneWidget);
    // 09:00 + 2h. The runner is choosing a deadline, so the deadline is what
    // the row states — not only the offset they picked it by.
    expect(find.text('Back by 11:00 AM'), findsOneWidget);
  });

  testWidgets('a deadline past midnight carries its date', (tester) async {
    await _pumpHost(
      tester,
      now: DateTime(2026, 6, 1, 22, 0),
      onResolved: (_) {},
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 22:00 + 4h is tomorrow; a bare "2:00 AM" reads as this morning.
    expect(find.textContaining('Back by Tue, Jun 2 2:00 AM'), findsOneWidget);
    // 22:00 + 30 min is still tonight, so it stays a bare clock time.
    expect(find.text('Back by 10:30 PM'), findsOneWidget);
  });

  testWidgets('picking an offset resolves the absolute instant',
      (tester) async {
    ExpectedReturnChoice? choice;
    await _pumpHost(tester, onResolved: (c) => choice = c);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In 2 hours'));
    await tester.pumpAndSettle();

    expect(choice, isNotNull);
    expect(choice!.isClear, isFalse);
    expect(choice!.at, DateTime(2026, 6, 1, 11, 0));
  });

  testWidgets('no armed alarm offers no Clear', (tester) async {
    await _pumpHost(tester, onResolved: (_) {});
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Clear the alert'), findsNothing);
    expect(find.textContaining('Alert set for'), findsNothing);
  });

  testWidgets('an armed alarm is stated and can be cleared', (tester) async {
    ExpectedReturnChoice? choice;
    await _pumpHost(
      tester,
      armed: DateTime(2026, 6, 1, 12, 30),
      onResolved: (c) => choice = c,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Alert set for 12:30 PM.'), findsOneWidget);

    await tester.tap(find.text('Clear the alert'));
    await tester.pumpAndSettle();
    expect(choice, isNotNull);
    expect(choice!.isClear, isTrue,
        reason: 'a deliberate disarm must be distinguishable from a dismiss');
  });

  testWidgets('dismissing resolves null, which is not a disarm',
      (tester) async {
    ExpectedReturnChoice? choice;
    var called = false;
    await _pumpHost(
      tester,
      armed: DateTime(2026, 6, 1, 12, 30),
      onResolved: (c) {
        choice = c;
        called = true;
      },
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(called, isTrue);
    expect(choice, isNull);
  });

  testWidgets('the dialog discloses that the deadline outlives the phone',
      (tester) async {
    await _pumpHost(tester, onResolved: (_) {});
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('kept on the server'), findsOneWidget);
    expect(find.textContaining('finishes with no signal'), findsOneWidget);
  });
}

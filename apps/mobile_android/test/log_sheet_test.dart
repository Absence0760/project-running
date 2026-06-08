import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/log_sheet.dart';

void main() {
  group('orderedLogActions', () {
    test('null recent → base order', () {
      expect(orderedLogActions(null), [
        LogAction.run,
        LogAction.lift,
        LogAction.food,
      ]);
    });

    test('recent floats to the top, rest keep their order', () {
      expect(orderedLogActions(LogAction.lift), [
        LogAction.lift,
        LogAction.run,
        LogAction.food,
      ]);
      expect(orderedLogActions(LogAction.food), [
        LogAction.food,
        LogAction.run,
        LogAction.lift,
      ]);
    });

    test('no duplicates regardless of recent', () {
      for (final r in LogAction.values) {
        final ordered = orderedLogActions(r);
        expect(ordered.toSet().length, LogAction.values.length);
        expect(ordered.first, r);
      }
    });
  });

  group('logActionFromWire / wire round-trip', () {
    test('round-trips every action', () {
      for (final a in LogAction.values) {
        expect(logActionFromWire(a.wire), a);
      }
    });

    test('food is a single capture wire', () {
      expect(LogAction.food.wire, 'food');
    });

    test('unknown / null → null', () {
      expect(logActionFromWire(null), isNull);
      expect(logActionFromWire(''), isNull);
      expect(logActionFromWire('bogus'), isNull);
    });
  });

  group('showLogSheet', () {
    testWidgets('renders the three capture options and pops the picked one',
        (tester) async {
      LogAction? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showLogSheet(context: context);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Log run'), findsOneWidget);
      expect(find.text('Log lift'), findsOneWidget);
      expect(find.text('Log food'), findsOneWidget);

      await tester.tap(find.text('Log lift'));
      await tester.pumpAndSettle();
      expect(result, LogAction.lift);
    });

    testWidgets('recent capture type floats to the top of the sheet',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () =>
                      showLogSheet(context: context, recent: LogAction.food),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The food tile renders above the run tile.
      final foodTop = tester.getTopLeft(find.text('Log food')).dy;
      final runTop = tester.getTopLeft(find.text('Log run')).dy;
      expect(foodTop, lessThan(runTop));
    });
  });
}

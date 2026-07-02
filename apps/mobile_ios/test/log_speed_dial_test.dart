import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/log_sheet.dart';
import '../lib/widgets/log_speed_dial.dart';

Widget _harness(void Function(BuildContext) onOpen) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => onOpen(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('showLogSpeedDial', () {
    testWidgets('fans the three capture options and resolves the picked one',
        (tester) async {
      LogAction? result;
      await tester.pumpWidget(_harness((context) async {
        result = await showLogSpeedDial(context: context);
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Log run'), findsOneWidget);
      expect(find.text('Log lift'), findsOneWidget);
      expect(find.text('Log food'), findsOneWidget);

      await tester.tap(find.text('Log lift'));
      await tester.pumpAndSettle();
      expect(result, LogAction.lift);
      // The overlay is torn down once a pick is made.
      expect(find.text('Log lift'), findsNothing);
    });

    testWidgets('tapping the scrim dismisses and resolves null', (tester) async {
      var resolved = false;
      LogAction? result;
      await tester.pumpWidget(_harness((context) async {
        result = await showLogSpeedDial(context: context);
        resolved = true;
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Log run'), findsOneWidget);

      // Tap the top-left corner — the dismiss scrim, well clear of the fan.
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(resolved, isTrue);
      expect(result, isNull);
      expect(find.text('Log run'), findsNothing);
    });

    testWidgets('recent capture type sits nearest the FAB (lowest in the fan)',
        (tester) async {
      await tester.pumpWidget(_harness((context) {
        showLogSpeedDial(context: context, recent: LogAction.food);
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The fan opens upward, so the recent action (food) is the bottom-most
      // item — greater dy than run.
      final foodTop = tester.getTopLeft(find.text('Log food')).dy;
      final runTop = tester.getTopLeft(find.text('Log run')).dy;
      expect(foodTop, greaterThan(runTop));
    });
  });
}

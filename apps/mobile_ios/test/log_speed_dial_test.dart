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
    testWidgets('fans the three icon-only actions and resolves the picked one',
        (tester) async {
      LogAction? result;
      await tester.pumpWidget(_harness((context) async {
        result = await showLogSpeedDial(context: context);
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Icon-only buttons — label lives on the Tooltip / Semantics, not as
      // visible text.
      expect(find.byTooltip('Log run'), findsOneWidget);
      expect(find.byTooltip('Log lift'), findsOneWidget);
      expect(find.byTooltip('Log food'), findsOneWidget);
      expect(find.text('Log run'), findsNothing);

      await tester.tap(find.byTooltip('Log lift'));
      await tester.pumpAndSettle();
      expect(result, LogAction.lift);
      // The overlay is torn down once a pick is made.
      expect(find.byTooltip('Log lift'), findsNothing);
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
      expect(find.byTooltip('Log run'), findsOneWidget);

      // Tap the top-left corner — the dismiss scrim, well clear of the fan.
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(resolved, isTrue);
      expect(result, isNull);
      expect(find.byTooltip('Log run'), findsNothing);
    });

    testWidgets('the recent action takes the top-centre slot (highest in the arc)',
        (tester) async {
      await tester.pumpWidget(_harness((context) {
        showLogSpeedDial(context: context, recent: LogAction.food);
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The arc puts the recent action (food) at the top-centre, so it sits
      // higher on screen (smaller dy) than the down-and-to-the-side run icon.
      // Both icons are unique in this harness.
      final foodTop = tester.getTopLeft(find.byIcon(Icons.restaurant)).dy;
      final runTop = tester.getTopLeft(find.byIcon(Icons.directions_run)).dy;
      expect(foodTop, lessThan(runTop));
    });
  });
}

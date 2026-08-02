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
    testWidgets('fans the three labelled actions and resolves the picked one',
        (tester) async {
      LogAction? result;
      await tester.pumpWidget(_harness((context) async {
        result = await showLogSpeedDial(context: context);
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Log run'), findsOneWidget);
      expect(find.byTooltip('Log lift'), findsOneWidget);
      expect(find.byTooltip('Log food'), findsOneWidget);

      await tester.tap(find.byTooltip('Log lift'));
      await tester.pumpAndSettle();
      expect(result, LogAction.lift);
      // The overlay is torn down once a pick is made.
      expect(find.byTooltip('Log lift'), findsNothing);
    });

    testWidgets('each fan item renders its label as visible text',
        (tester) async {
      await tester.pumpWidget(_harness((context) {
        showLogSpeedDial(context: context);
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The whole point of #664: the fan is discoverable without a
      // long-press, so the localized label is on screen beside the glyph.
      for (final label in ['Log run', 'Log lift', 'Log food']) {
        expect(find.text(label), findsOneWidget);
      }
      // Each label sits under its own icon, not floating elsewhere.
      expect(
        tester.getTopLeft(find.text('Log run')).dy,
        greaterThan(tester.getTopLeft(find.byIcon(Icons.directions_run)).dy),
      );
    });

    testWidgets('the label does not shrink the icon below the 48dp floor',
        (tester) async {
      await tester.pumpWidget(_harness((context) {
        showLogSpeedDial(context: context);
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      for (final icon in [
        Icons.directions_run,
        Icons.fitness_center,
        Icons.restaurant,
      ]) {
        final size = tester.getSize(
          find.ancestor(of: find.byIcon(icon), matching: find.byType(InkWell)),
        );
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('the arc keeps the top item\'s label clear of the side icons',
        (tester) async {
      await tester.pumpWidget(_harness((context) {
        showLogSpeedDial(context: context, recent: LogAction.food);
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The top-centre label hangs level with the two lower icons, so the
      // arc radius has to buy horizontal clearance or they collide.
      final topLabel = tester.getRect(find.text('Log food'));
      for (final icon in [Icons.directions_run, Icons.fitness_center]) {
        final side = tester.getRect(find.byIcon(icon));
        expect(topLabel.overlaps(side), isFalse);
      }
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

  group('showLogSpeedDial — anchored fan (NavigationRail Log button)', () {
    const anchor = Offset(56, 300);

    testWidgets(
        'fans right of the anchor: recent directly right, the others above and below',
        (tester) async {
      await tester.pumpWidget(_harness((context) {
        showLogSpeedDial(
            context: context, recent: LogAction.food, anchor: anchor);
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final food = tester.getCenter(find.byIcon(Icons.restaurant));
      final run = tester.getCenter(find.byIcon(Icons.directions_run));
      final lift = tester.getCenter(find.byIcon(Icons.fitness_center));

      // The rail sits at the left edge, so the whole arc opens rightward —
      // every item's centre lands right of the anchor.
      for (final c in [food, run, lift]) {
        expect(c.dx, greaterThan(anchor.dx));
      }
      // The recent action rides the directly-right slot at the anchor's own
      // height; the remaining two split above and below it.
      expect(food.dy, closeTo(anchor.dy, 1));
      final others = [run.dy, lift.dy]..sort();
      expect(others.first, lessThan(anchor.dy));
      expect(others.last, greaterThan(anchor.dy));
    });

    testWidgets('anchored pick resolves and tears the overlay down',
        (tester) async {
      LogAction? result;
      await tester.pumpWidget(_harness((context) async {
        result = await showLogSpeedDial(context: context, anchor: anchor);
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Log run'));
      await tester.pumpAndSettle();
      expect(result, LogAction.run);
      expect(find.byTooltip('Log run'), findsNothing);
    });
  });
}

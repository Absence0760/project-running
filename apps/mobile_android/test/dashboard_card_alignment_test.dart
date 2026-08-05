import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/dashboard_screen.dart';
import '../lib/widgets/training_load_chart.dart';

/// Issue #666 C1. The dashboard used to stack its cards at three different
/// left edges — 16 for a card that zeroed its margin, 20 for one taking
/// Material's `EdgeInsets.all(4)` default, and 32 for the two that named
/// `fromLTRB(16, 8, 16, 8)` on top of the list's own 16 px padding. The card
/// theme now carries no horizontal margin at all, so a card's left edge is
/// its parent's padding edge and nothing else.

Run _run(String id, DateTime startedAt) => Run(
      id: id,
      startedAt: startedAt,
      duration: const Duration(minutes: 25),
      distanceMetres: 5000,
      source: RunSource.app,
    );

void main() {
  testWidgets('every full-width dashboard card shares one left and right edge',
      (tester) async {
    await tester.runAsync(() async {
      // Tall surface so the whole card stack builds — the offending margins
      // lived on cards well below a phone-height fold.
      tester.view.physicalSize = const Size(400, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();

      final dir = Directory.systemTemp.createTempSync('dashboard_card_align_');
      try {
        final now = DateTime.now().toUtc();
        final seed = LocalRunStore();
        await seed.init(overrideDirectory: dir);
        for (var i = 0; i < 6; i++) {
          await seed.save(_run('r$i', now.subtract(Duration(days: i * 3))));
        }

        final runStore = LocalRunStore();
        await runStore.init(overrideDirectory: dir);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DashboardScreen(
              runStore: runStore,
              routeStore: LocalRouteStore(),
              gymStore: LocalGymStore(),
              foodStore: LocalFoodStore(),
              preferences: prefs,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        // One of the cards that used to name a horizontal margin of its own.
        expect(find.byType(TrainingLoadChart), findsOneWidget);

        // Measure the painted surface, not the Card element: the Card's own
        // render object spans its margin box, so a card that insets itself
        // still reports full-width bounds.
        final rects = tester
            .widgetList<Card>(find.byType(Card))
            .map((c) => tester.getRect(find
                .descendant(of: find.byWidget(c), matching: find.byType(Material))
                .first))
            .toList();
        expect(rects.length, greaterThan(6),
            reason: 'the card stack must actually have mounted');

        final widest = rects.map((r) => r.width).reduce((a, b) => a > b ? a : b);
        // The period strip is three cards abreast inside one row, each about
        // a third of the content width; everything else is a stacked card and
        // must line up. The threshold sits well below full width so a card
        // that re-grows a horizontal margin fails the assertion instead of
        // dropping quietly out of the set.
        final fullWidth = rects.where((r) => r.width > widest * 0.6).toList();
        expect(fullWidth.length, greaterThan(4));

        final lefts = fullWidth.map((r) => r.left).toSet();
        final rights = fullWidth.map((r) => r.right).toSet();
        expect(lefts, hasLength(1), reason: 'left edges: $lefts');
        expect(rights, hasLength(1), reason: 'right edges: $rights');

        // The ListView supplies the whole 16 px gutter.
        expect(lefts.single, 16.0);
        expect(rights.single, 384.0);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}

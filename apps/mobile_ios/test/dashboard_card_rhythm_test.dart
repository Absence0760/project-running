// Issue #666 C7: the dashboard changed grammar halfway down. Above, a card was
// headed by an external `_SectionHeader` and separated by a 24 dp
// `_kSectionGap`; below, five analytics cards ran back-to-back with two of them
// carrying their own titleMedium heading and a self-inserted trailing
// `SizedBox(height: 24)`. Measured on a 400 dp surface the analytics seams came
// out at 64 / 32 / 8 dp against 32 above — the audit's "8 / 12 / 16 / 16 against
// 28" did not reproduce, and the real defect was three values, not one.
//
// Every card now names itself with `ChartCardHeader`, so the stack separates by
// the card grammar alone. Per §500 this pins the *relation* — one gap repeated,
// equal to the card theme's own margin — not any absolute figure.

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

Run _run(String id, DateTime startedAt) => Run(
      id: id,
      startedAt: startedAt,
      duration: const Duration(minutes: 25),
      distanceMetres: 5000,
      source: RunSource.app,
    );

void main() {
  testWidgets('the dashboard card stack repeats one gap, the card margin',
      (tester) async {
    await tester.runAsync(() async {
      // Tall enough that the whole stack builds — the analytics run sits well
      // below a phone-height fold.
      tester.view.physicalSize = const Size(400, 8000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();

      final dir = Directory.systemTemp.createTempSync('dashboard_rhythm_');
      try {
        final now = DateTime.now().toUtc();
        final seed = LocalRunStore();
        await seed.init(overrideDirectory: dir);
        for (var i = 0; i < 40; i++) {
          await seed.save(_run('r$i', now.subtract(Duration(days: i))));
        }
        final runStore = LocalRunStore();
        await runStore.init(overrideDirectory: dir);

        await tester.pumpWidget(MaterialApp(
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
        ));
        // pumpAndSettle would spin the streak card's counters.
        await tester.pump();
        await tester.pump();

        // The painted surface of every full-width card, top-to-bottom. Measured
        // on the inner Material, since a Card's own render object spans its
        // margin box.
        final rects = tester
            .widgetList<Card>(find.byType(Card))
            .map((c) => tester.getRect(find
                .descendant(of: find.byWidget(c), matching: find.byType(Material))
                .first))
            .where((r) => r.width > 200)
            .toList()
          ..sort((a, b) => a.top.compareTo(b.top));

        // The self-heading run: the "This Week" strip through the training-load
        // chart. Everything above it is a group block (goals, the three-abreast
        // period strip) and keeps its section gap.
        final headed = rects.where((r) => r.top > 300).toList();
        expect(headed.length, greaterThanOrEqualTo(6),
            reason: 'the card stack must actually have mounted');

        final gaps = <double>[
          for (var i = 1; i < headed.length; i++)
            headed[i].top - headed[i - 1].bottom,
        ];
        expect(gaps.toSet(), hasLength(1),
            reason: 'the stack changes rhythm partway down: $gaps');

        // And the one gap is the card theme's own vertical margin, doubled —
        // derived from the theme rather than asserted as a number, so raising
        // the margin moves the expectation with it.
        final margin =
            (AppTheme.light.cardTheme.margin! as EdgeInsets).vertical;
        expect(gaps.first, margin);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  testWidgets('every card in the stack carries its own header', (tester) async {
    await tester.runAsync(() async {
      tester.view.physicalSize = const Size(400, 8000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();

      final dir = Directory.systemTemp.createTempSync('dashboard_rhythm_h_');
      try {
        final now = DateTime.now().toUtc();
        final seed = LocalRunStore();
        await seed.init(overrideDirectory: dir);
        for (var i = 0; i < 40; i++) {
          await seed.save(_run('r$i', now.subtract(Duration(days: i))));
        }
        final runStore = LocalRunStore();
        await runStore.init(overrideDirectory: dir);

        await tester.pumpWidget(MaterialApp(
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
        ));
        await tester.pump();
        await tester.pump();

        // The two headings that used to sit outside their card.
        for (final title in ['Streak', 'Personal Bests', 'Fitness']) {
          expect(
            find.ancestor(
                of: find.text(title), matching: find.byType(ChartCardHeader)),
            findsOneWidget,
            reason: '"$title" is not inside its card\'s shared header',
          );
        }
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}

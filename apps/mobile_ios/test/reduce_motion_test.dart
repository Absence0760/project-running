// Issue #666 S15 — the reduce-motion half of the motion system.
//
// The finding's headline: `MediaQuery.disableAnimations` was ignored by the
// `repeat()`-ing live-map pulse that runs for the whole of a recording. The
// framework does not cover it — its 5 % duration scale lives in
// `AnimationController._animateToInternal` and NOT in `repeat()`, whose own
// source comment gives the reason ("the common pattern of an eternally
// repeating animation might cause an endless loop"). So a repeating pulse ran
// at its full 1500 ms period for hours regardless of the OS setting.
//
// The load-bearing assertion in every widget case below is `pumpAndSettle`
// versus `transientCallbackCount`: a live `repeat()` holds a frame callback
// forever, so a settled tree is proof the loop actually STOPPED rather than
// merely running faster. Each case asserts BOTH directions, so it cannot pass
// over a widget that never animated in the first place (§534).

import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/collapsible_panel.dart';
import '../lib/widgets/live_run_map.dart';

Waypoint _w(double lat, double lng) => Waypoint(lat: lat, lng: lng);

final _track = <Waypoint>[
  _w(51.5074, -0.1278),
  _w(51.5080, -0.1270),
  _w(51.5090, -0.1260),
];

Widget _app(Widget child, {required bool reduce}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  setUp(() {
    dotenv.loadFromString(envString: '', isOptional: true);
    dotenv.env.clear();
  });

  group('LiveRunMap position pulse', () {
    testWidgets('runs a repeating ticker when motion is allowed', (tester) async {
      await tester.pumpWidget(_app(
        SizedBox(
          height: 300,
          child: LiveRunMap(track: _track, currentPosition: _track.last),
        ),
        reduce: false,
      ));
      await tester.pump(AppMotion.pulse ~/ 3);
      expect(tester.binding.transientCallbackCount, greaterThan(0),
          reason: 'the pulse must actually be animating on this branch, '
              'or the reduced branch below proves nothing');
    });

    testWidgets('stops the ticker entirely under reduce-motion', (tester) async {
      await tester.pumpWidget(_app(
        SizedBox(
          height: 300,
          child: LiveRunMap(track: _track, currentPosition: _track.last),
        ),
        reduce: true,
      ));
      // Never returns while a repeat() is live. This is the whole fix.
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('turning reduce-motion on mid-recording stops the pulse',
        (tester) async {
      Widget map(bool reduce) => _app(
            SizedBox(
              height: 300,
              child: LiveRunMap(track: _track, currentPosition: _track.last),
            ),
            reduce: reduce,
          );
      await tester.pumpWidget(map(false));
      await tester.pump(AppMotion.pulse ~/ 3);
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      // The runner reaches for the OS switch 40 km in; the loop must die
      // without the map being rebuilt from scratch.
      await tester.pumpWidget(map(true));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('CollapsiblePanel cross-fade', () {
    final _handle = find
        .descendant(
          of: find.byType(CollapsiblePanel),
          matching: find.byType(GestureDetector),
        )
        .first;

    Widget panel(bool reduce) => _app(
          const Align(
            alignment: Alignment.bottomCenter,
            child: CollapsiblePanel(
              expandedChild: SizedBox(height: 200, child: Text('expanded')),
              collapsedChild: SizedBox(height: 40, child: Text('collapsed')),
            ),
          ),
          reduce: reduce,
        );

    double panelHeight(WidgetTester tester) =>
        tester.getSize(find.byType(CollapsiblePanel)).height;

    testWidgets('animates its height when motion is allowed', (tester) async {
      await tester.pumpWidget(panel(false));
      await tester.pumpAndSettle();
      final before = panelHeight(tester);
      expect(find.byType(AnimatedCrossFade), findsOneWidget);

      await tester.tap(_handle);
      await tester.pump();
      await tester.pump(AppMotion.brief ~/ 2);
      final mid = panelHeight(tester);
      expect(mid, isNot(before),
          reason: 'mid-flight the panel must be between its two heights');
      expect(tester.binding.transientCallbackCount, greaterThan(0),
          reason: 'the size tween must be ticking on this branch');
      await tester.pumpAndSettle();
      expect(panelHeight(tester), isNot(mid));
    });

    testWidgets('swaps instantly under reduce-motion', (tester) async {
      await tester.pumpWidget(panel(true));
      await tester.pumpAndSettle();
      final before = panelHeight(tester);
      // The animating widget is not merely fed a zero duration — it is not in
      // the tree at all. `RenderAnimatedSize` asserts on a zero duration.
      expect(find.byType(AnimatedCrossFade), findsNothing);

      await tester.tap(_handle);
      await tester.pump();
      // A single frame is the whole transition: the final height, reached
      // immediately, with nothing left ticking.
      expect(tester.binding.transientCallbackCount, 0);
      expect(panelHeight(tester), isNot(before),
          reason: 'the swap must still have happened');
      await tester.pumpAndSettle();
    });
  });

  group('source guards', () {
    // §534: each guard proves it measured a non-empty set before asserting.
    final roots = <String>[
      'lib',
      '../../packages/ui_kit/lib',
      '../../packages/run_recorder/lib',
    ];

    List<File> dartFiles() {
      final out = <File>[];
      for (final root in roots) {
        final dir = Directory(root);
        if (!dir.existsSync()) continue;
        for (final e in dir.listSync(recursive: true)) {
          if (e is File && e.path.endsWith('.dart')) out.add(e);
        }
      }
      return out;
    }

    test('every repeating animation is driven through syncMotionLoop', () {
      final files = dartFiles();
      expect(files.length, greaterThan(100),
          reason: 'the sweep found almost nothing — the roots are wrong');

      final repeatSites = <String>[];
      final seamSites = <String>[];
      for (final f in files) {
        final src = f.readAsStringSync();
        if (RegExp(r'\.repeat\(').hasMatch(src)) repeatSites.add(f.path);
        if (src.contains('syncMotionLoop(')) seamSites.add(f.path);
      }

      // The only `.repeat(` in the tree is the one inside the seam itself.
      expect(repeatSites.map((p) => p.split('/').last).toSet(), {'motion.dart'},
          reason: 'a repeating controller outside motion.dart cannot honour '
              'reduce-motion — Flutter does not scale repeat(). Drive it '
              'through syncMotionLoop instead.\nfound: $repeatSites');

      // And the seam has real adopters, so the rule above is not vacuous.
      expect(seamSites.length, greaterThanOrEqualTo(5),
          reason: 'syncMotionLoop has too few call sites for the guard above '
              'to mean anything: $seamSites');
    });

    test('every curve comes off the AppMotion set, and every rung is used', () {
      const rungs = [
        'curveStandard',
        'curveEmphasised',
        'curveOvershoot',
        'curveLinear',
      ];
      final files = dartFiles();
      final bare = <String>[];
      final uses = {for (final r in rungs) r: 0};
      for (final f in files) {
        final src = f.readAsStringSync();
        if (f.path.endsWith('motion.dart')) continue;
        if (RegExp(r'\bCurves\.').hasMatch(src)) bare.add(f.path);
        for (final r in rungs) {
          uses[r] = uses[r]! + RegExp('AppMotion\\.$r\\b').allMatches(src).length;
        }
      }
      expect(bare, isEmpty,
          reason: 'a hand-picked curve is how the set grew to four with no '
              'names. Add a rung to AppMotion instead.\nfound: $bare');
      // Derived rather than a total: a rung with no adopter is dead weight,
      // and a non-empty adopter set per rung is what proves the sweep read
      // real source (§500 / §534).
      for (final r in rungs) {
        expect(uses[r], greaterThan(0),
            reason: 'AppMotion.$r has no adopter — either wire it up or drop '
                'the rung.\ncounts: $uses');
      }
    });

    test('the tile-free share rasterisers do not sleep', () {
      // §538 shipped MapTileReadiness for the two cards that draw tiles and
      // left this one open. A sleep in a card with no asynchronous paint is a
      // delay charged to the user for nothing.
      const tileFree = <String>[
        'lib/screens/period_summary_screen.dart',
        'lib/widgets/finisher_certificate_card.dart',
      ];
      for (final path in tileFree) {
        final f = File(path);
        expect(f.existsSync(), isTrue, reason: '$path moved');
        final src = f.readAsStringSync();
        expect(src.contains('capturePngBytes('), isTrue,
            reason: '$path is no longer a rasteriser — retarget this guard');
        expect(RegExp(r'Future\.delayed').hasMatch(src), isFalse,
            reason: '$path draws no map tiles, so there is nothing for a '
                'sleep to wait on; await endOfFrame instead');
      }
    });
  });
}

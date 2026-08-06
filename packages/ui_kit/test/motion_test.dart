// Issue #666 S15 — the motion tier and the reduce-motion seam.
//
// Per §500 these tests pin the DERIVATION, not an absolute: each rung is
// asserted to be the modal value of the population that was shipping when the
// tier was introduced, so a future edit that moves a rung off the mode fails
// here rather than silently becoming a ninth hand-picked number.
//
// The `syncMotionLoop` cases carry the whole point of the finding: a repeating
// controller must STOP under reduce-motion, not run faster. `pumpAndSettle`
// is the assertion that proves it — it hangs forever on a live `repeat()`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// The one-shot element transitions that were shipping when the tier landed:
/// the onboarding page indicator, the Log speed-dial fan, the run stats
/// cross-fade, and the countdown-digit switcher.
const _briefPopulation = [200, 200, 260, 350];

/// The animated scrolls / page changes: the coach scroll-to-bottom, the
/// route-detail reveal-map scroll, the onboarding page advance.
const _standardPopulation = [180, 300, 300];

/// Every repeating loop that was shipping: the coach typing dots, the three
/// [ActivityLoader] gait cadences, the skeleton shimmer, the route-builder
/// waypoint pin, the live-map current-position ring. 1500 is the only value
/// that occurs twice, which is what makes it the rung — the four
/// indeterminate-progress cadences stay off-tier for the reason recorded on
/// [AppMotion], not because they were excluded from the derivation.
const _pulsePopulation = [600, 720, 900, 1050, 1100, 1500, 1500];

int _mode(List<int> values) {
  final counts = <int, int>{};
  for (final v in values) {
    counts[v] = (counts[v] ?? 0) + 1;
  }
  var best = values.first;
  for (final e in counts.entries) {
    if (e.value > (counts[best] ?? 0)) best = e.key;
  }
  return best;
}

Widget _host(Widget child, {required bool reduce}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );

void main() {
  group('AppMotion tier is derived, not picked', () {
    test('every rung is the modal value of its role', () {
      expect(AppMotion.brief.inMilliseconds, _mode(_briefPopulation));
      expect(AppMotion.standard.inMilliseconds, _mode(_standardPopulation));
      expect(AppMotion.pulse.inMilliseconds, _mode(_pulsePopulation));
    });

    test('each population really has a mode — the derivation is not vacuous', () {
      for (final p in [_briefPopulation, _standardPopulation, _pulsePopulation]) {
        expect(p.length, greaterThan(1), reason: 'a one-value population has no mode');
        final m = _mode(p);
        expect(p.where((v) => v == m).length, greaterThan(1),
            reason: 'the mode of $p appears once — that is a pick, not a mode');
      }
    });

    test('the rungs are strictly ordered', () {
      expect(AppMotion.brief, lessThan(AppMotion.standard));
      expect(AppMotion.standard, lessThan(AppMotion.pulse));
    });

    test('the curve set is the four that ship, all distinct', () {
      final curves = <Curve>{
        AppMotion.curveStandard,
        AppMotion.curveEmphasised,
        AppMotion.curveOvershoot,
        AppMotion.curveLinear,
      };
      expect(curves, hasLength(4));
      // The linear rung must genuinely not ease — a data tween that eases
      // makes a steady-pace runner's dot accelerate and brake every fix.
      expect(AppMotion.curveLinear.transform(0.25), closeTo(0.25, 1e-9));
      expect(AppMotion.curveLinear.transform(0.75), closeTo(0.75, 1e-9));
      expect(AppMotion.curveStandard.transform(0.25),
          greaterThan(0.25),
          reason: 'easeOut must front-load');
      // Overshoot is the one curve that leaves the unit interval.
      expect(AppMotion.curveOvershoot.transform(0.7), greaterThan(1.0));
    });
  });

  group('reduceMotion / motionDuration', () {
    testWidgets('reads the platform flag, and a missing MediaQuery is no preference',
        (tester) async {
      late bool onFlag;
      late bool offFlag;
      await tester.pumpWidget(_host(
        Builder(builder: (c) {
          onFlag = reduceMotion(c);
          return const SizedBox();
        }),
        reduce: true,
      ));
      await tester.pumpWidget(_host(
        Builder(builder: (c) {
          offFlag = reduceMotion(c);
          return const SizedBox();
        }),
        reduce: false,
      ));
      expect(onFlag, isTrue);
      expect(offFlag, isFalse);

      late bool bare;
      await tester.pumpWidget(Builder(builder: (c) {
        bare = reduceMotion(c);
        return const SizedBox();
      }));
      expect(bare, isFalse);
    });

    testWidgets('collapses to zero only under the flag', (tester) async {
      late Duration on;
      late Duration off;
      await tester.pumpWidget(_host(
        Builder(builder: (c) {
          on = motionDuration(c, AppMotion.brief);
          return const SizedBox();
        }),
        reduce: true,
      ));
      await tester.pumpWidget(_host(
        Builder(builder: (c) {
          off = motionDuration(c, AppMotion.brief);
          return const SizedBox();
        }),
        reduce: false,
      ));
      expect(on, Duration.zero);
      expect(off, AppMotion.brief);
    });
  });

  group('syncMotionLoop stops the loop rather than speeding it up', () {
    testWidgets('the unreduced loop really animates — the population is non-empty',
        (tester) async {
      await tester.pumpWidget(_host(
        const _Looper(restValue: 0.25),
        reduce: false,
      ));
      await tester.pump(AppMotion.pulse ~/ 4);
      final state = tester.state<_LooperState>(find.byType(_Looper));
      expect(state.controller.isAnimating, isTrue);
      expect(tester.binding.transientCallbackCount, greaterThan(0),
          reason: 'a repeating controller must hold a frame callback');
      expect(state.controller.value, greaterThan(0.0));
    });

    testWidgets('under reduce-motion the ticker stops and parks at restValue',
        (tester) async {
      await tester.pumpWidget(_host(
        const _Looper(restValue: 0.25),
        reduce: true,
      ));
      final state = tester.state<_LooperState>(find.byType(_Looper));
      expect(state.controller.isAnimating, isFalse);
      expect(state.controller.value, 0.25);
      // The load-bearing assertion: with no repeating ticker, the tree settles.
      // This call never returns on the unreduced branch above.
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('flipping the flag off restarts the loop', (tester) async {
      await tester.pumpWidget(_host(const _Looper(), reduce: true));
      final state = tester.state<_LooperState>(find.byType(_Looper));
      expect(state.controller.isAnimating, isFalse);

      await tester.pumpWidget(_host(const _Looper(), reduce: false));
      await tester.pump(const Duration(milliseconds: 16));
      expect(state.controller.isAnimating, isTrue);

      await tester.pumpWidget(_host(const _Looper(), reduce: true));
      expect(state.controller.isAnimating, isFalse);
    });
  });

  group('motionScrollTo jumps instead of animating', () {
    Widget scrollHost(ScrollController c, {required bool reduce}) => _host(
          MediaQuery(
            data: const MediaQueryData(size: Size(400, 300)),
            child: SizedBox(
              height: 300,
              child: ListView.builder(
                controller: c,
                itemCount: 40,
                itemBuilder: (_, i) => SizedBox(height: 60, child: Text('$i')),
              ),
            ),
          ),
          reduce: reduce,
        );

    testWidgets('reduce-motion lands on the offset within a single frame',
        (tester) async {
      final c = ScrollController(initialScrollOffset: 600);
      addTearDown(c.dispose);
      late BuildContext ctx;
      await tester.pumpWidget(_host(
        Builder(builder: (bc) {
          ctx = bc;
          return scrollHost(c, reduce: true);
        }),
        reduce: true,
      ));
      await motionScrollTo(ctx, c, 0);
      expect(c.offset, 0);
      await tester.pumpAndSettle();
    });

    testWidgets('without the flag it animates over the standard rung',
        (tester) async {
      final c = ScrollController(initialScrollOffset: 600);
      addTearDown(c.dispose);
      late BuildContext ctx;
      await tester.pumpWidget(_host(
        Builder(builder: (bc) {
          ctx = bc;
          return scrollHost(c, reduce: false);
        }),
        reduce: false,
      ));
      final done = motionScrollTo(ctx, c, 0);
      await tester.pump(AppMotion.standard ~/ 2);
      expect(c.offset, greaterThan(0),
          reason: 'mid-flight the scroll must not have arrived yet');
      await tester.pumpAndSettle();
      await done;
      expect(c.offset, 0);
    });

    testWidgets('a controller with no clients is a no-op, not a throw',
        (tester) async {
      final c = ScrollController();
      addTearDown(c.dispose);
      late BuildContext ctx;
      await tester.pumpWidget(_host(
        Builder(builder: (bc) {
          ctx = bc;
          return const SizedBox();
        }),
        reduce: true,
      ));
      ctx = tester.element(find.byType(SizedBox));
      await motionScrollTo(ctx, c, 120);
      expect(c.hasClients, isFalse);
    });
  });
}

class _Looper extends StatefulWidget {
  const _Looper({this.restValue = 0});

  final double restValue;

  @override
  State<_Looper> createState() => _LooperState();
}

class _LooperState extends State<_Looper>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller =
      AnimationController(vsync: this, duration: AppMotion.pulse);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, controller, restValue: widget.restValue);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

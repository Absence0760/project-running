import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import '../lib/adaptive_width.dart';
import '../lib/widgets/collapsing_tab_host.dart';

const double _kHeroHeight = 300;

void _noop() {}

Widget _listTab(String prefix) => ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: 40,
      itemBuilder: (_, i) => SizedBox(height: 60, child: Text('$prefix $i')),
    );

Future<void> _pumpHost(
  WidgetTester tester, {
  required List<Widget> tabs,
  Size size = const Size(360, 640),
  double textScale = 1.0,
  double heroHeight = _kHeroHeight,
  TabController? controller,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final tabs0 = controller ??
      TabController(length: tabs.length, vsync: const TestVSync());
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Host')),
        body: CollapsingTabHost(
          controller: tabs0,
          labels: [for (var i = 0; i < tabs.length; i++) 'T$i'],
          header: [SizedBox(height: heroHeight, child: const Text('HERO'))],
          tabs: tabs,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CollapsingTabHost (issue #666 C12, decisions § 545)', () {
    testWidgets('a drag on a list tab scrolls the hero away and leaves the '
        'strip pinned', (tester) async {
      await _pumpHost(tester, tabs: [_listTab('a'), _listTab('b')]);

      // Population: the hero and the strip are both really on screen before
      // the drag, so the assertions below are not over an empty tree.
      expect(find.text('HERO'), findsOneWidget);
      expect(find.byType(AppTabBar), findsOneWidget);
      final heroBefore = tester.getTopLeft(find.text('HERO')).dy;
      final stripBefore = tester.getTopLeft(find.byType(AppTabBar)).dy;
      expect(stripBefore, greaterThan(heroBefore));

      await tester.drag(find.text('a 0'), const Offset(0, -200));
      await tester.pumpAndSettle();

      // The derivation: the drag went to the outer header, so the hero and the
      // strip travelled together by the same amount. Asserting the equality
      // rather than an absolute dp keeps it independent of both the test font
      // (decisions § 500) and the gesture arena's touch slop.
      final travelled = heroBefore - tester.getTopLeft(find.text('HERO')).dy;
      expect(travelled, greaterThan(0));
      expect(
        stripBefore - tester.getTopLeft(find.byType(AppTabBar)).dy,
        travelled,
      );

      // Past the hero's own height the band is gone and the strip has stopped
      // at the top of the scroll view — pinned, not scrolled off.
      await tester.drag(find.text('a 2'), const Offset(0, -_kHeroHeight));
      await tester.pumpAndSettle();
      expect(find.text('HERO'), findsNothing);
      expect(find.byType(AppTabBar), findsOneWidget);
      expect(tester.getTopLeft(find.byType(AppTabBar)).dy, heroBefore);
    });

    testWidgets('an empty tab collapses the hero and scrolls its own content '
        'when the content does not fit', (tester) async {
      // The header collapse itself survives a non-scrollable body — the outer
      // `NestedScrollView` covers the body's area and takes the drag (which is
      // the half § 537 had wrong). What a non-scrollable body cannot do is
      // scroll its OWN content: `TabBarView` hands it a bounded box, so an
      // empty state that does not fit at a large text scale overflows. ui_kit's
      // `EmptyState` is a fill-and-centre scrollable under bounded height,
      // which is why the four bare-`Center` tabs take one.
      await _pumpHost(
        tester,
        tabs: const [
          EmptyState(
            icon: Icons.inbox,
            title: 'Nothing here yet',
            body: 'When a member posts a run, a photo or a note it shows up on '
                'this tab, newest first, and everyone in the club can see it.',
            ctaLabel: 'Write the first post',
            onCta: _noop,
          ),
        ],
        size: const Size(320, 568),
        textScale: 2.0,
        heroHeight: 80,
      );

      // Population: the state really rendered, and it really is taller than the
      // box it was given — an assertion about scrolling over content that fits
      // would prove nothing.
      expect(find.text('Nothing here yet'), findsOneWidget);
      final body = tester.getRect(find.byType(TabBarView));
      final scroller = tester.widget<Scrollable>(
        find.descendant(
          of: find.byType(EmptyState),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scroller.physics, isA<AlwaysScrollableScrollPhysics>());
      expect(
        tester.getRect(find.byType(FilledButton)).bottom,
        greaterThan(body.bottom),
        reason: 'the empty state fits, so nothing here needs to scroll',
      );
      expect(tester.takeException(), isNull);

      expect(find.text('HERO'), findsOneWidget);
      final ctaBefore = tester.getRect(find.byType(FilledButton)).top;
      await tester.drag(find.text('Nothing here yet'), const Offset(0, -300));
      await tester.pumpAndSettle();

      // The 80 dp hero is gone — the drag reached the outer header — and the
      // remaining travel went to the body's own scrollable.
      expect(find.text('HERO'), findsNothing);
      expect(
        ctaBefore - tester.getRect(find.byType(FilledButton)).top,
        greaterThan(0),
        reason: 'the tab body could not scroll to its own CTA',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the body inset the absorber requires is AppTabBar.height',
        (tester) async {
      await _pumpHost(tester, tabs: [_listTab('a')]);

      final absorber = tester.widget<SliverOverlapAbsorber>(
        find.byType(SliverOverlapAbsorber),
      );
      // The pinned strip's whole extent is absorbed from the body, which is
      // why the body owes exactly that much back as a top inset. If this
      // stopped matching, the first row would sit under the strip (too little)
      // or a band of dead space would open (too much).
      expect(absorber.handle.layoutExtent, AppTabBar.height);
      expect(
        tester.getTopLeft(find.text('a 0')).dy -
            tester.getTopLeft(find.byType(AppTabBar)).dy,
        AppTabBar.height,
      );
    });

    testWidgets('at an expanded width the strip is clamped to the same column '
        'as the body it labels', (tester) async {
      await _pumpHost(
        tester,
        tabs: [_listTab('a')],
        size: const Size(1200, 900),
      );

      final strip = tester.getRect(find.byType(AppTabBar));
      final body = tester.getRect(find.byType(TabBarView));
      expect(strip.width, lessThanOrEqualTo(kContentMaxWidth));
      expect(strip.left, body.left);
      expect(strip.width, body.width);
      // Population: the clamp actually bit — a 1200 dp viewport is wider than
      // the cap, so an unclamped strip would have measured 1200.
      expect(strip.width, lessThan(1200));
    });

    testWidgets('a compact width takes no clamp', (tester) async {
      await _pumpHost(tester, tabs: [_listTab('a')]);
      expect(tester.getSize(find.byType(AppTabBar)).width, 360);
    });

    testWidgets('a hero taller than a 320 dp viewport at 2.0x does not '
        'overflow, and the strip stays reachable', (tester) async {
      await _pumpHost(
        tester,
        tabs: const [EmptyState(icon: Icons.inbox, title: 'Nothing here yet')],
        size: const Size(320, 568),
        textScale: 2.0,
        heroHeight: 900,
      );

      // Population: the over-tall hero really is what is on screen — the strip
      // and body are past the viewport, which is the state being tested.
      expect(find.text('HERO'), findsOneWidget);
      expect(find.byType(AppTabBar), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.fling(find.text('HERO'), const Offset(0, -900), 4000);
      await tester.pumpAndSettle();

      expect(find.byType(AppTabBar), findsOneWidget);
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

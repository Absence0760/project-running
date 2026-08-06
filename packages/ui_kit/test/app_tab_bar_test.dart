// Issue #666 C6: two sibling hubs wore opposite tab strips because each screen
// picked `isScrollable` by hand — one filled at 46 dp flush with x=0, the other
// scrolled at 72 dp indented 52 dp, so switching destinations moved the strip
// both ways at once.
//
// Per §500 these assert the DERIVATION, never that some string fits some width:
// flutter_test's font is fixed-advance, so an absolute pixel figure means
// nothing. What is pinned is the relation — labels that fit fill, labels that
// don't scroll, the first tab is flush either way, and the strip is one height.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Future<void> _pump(
  WidgetTester tester,
  List<String> labels, {
  double width = 360,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: DefaultTabController(
        length: labels.length,
        child: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              toolbarHeight: 0,
              bottom: AppTabBar(
                controller: DefaultTabController.of(context),
                labels: labels,
              ),
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  ));
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpAndSettle();
}

TabBar _bar(WidgetTester tester) => tester.widget<TabBar>(find.byType(TabBar));

double _firstTabLeft(WidgetTester tester, String label) =>
    tester.getRect(find.text(label)).left;

void main() {
  group('AppTabBar derives isScrollable', () {
    testWidgets('labels that fit share the width', (tester) async {
      await _pump(tester, const ['All', 'Runs', 'Gym', 'Food']);
      expect(_bar(tester).isScrollable, isFalse);
      expect(_bar(tester).tabAlignment, TabAlignment.fill);
    });

    testWidgets('labels that do not fit scroll', (tester) async {
      await _pump(tester, const [
        'Feed',
        'People',
        'Clubs',
        'Discover',
        'Challenges',
        'Leaderboards',
        'Notifications',
      ]);
      expect(_bar(tester).isScrollable, isTrue);
    });

    testWidgets('the same labels flip with the width they are given',
        (tester) async {
      const labels = ['Feed', 'People', 'Clubs', 'Discover', 'Challenges'];
      await _pump(tester, labels, width: 240);
      final narrow = _bar(tester).isScrollable;
      await _pump(tester, labels, width: 1200);
      final wide = _bar(tester).isScrollable;
      expect(narrow, isTrue);
      expect(wide, isFalse,
          reason: 'the flag is a function of the width, not of the tab count');
    });

    testWidgets('a strip that fits at 1.0x scrolls once the OS scales type up',
        (tester) async {
      const labels = ['Feed', 'People', 'Clubs', 'Discover', 'Challenges'];
      await _pump(tester, labels, width: 700);
      expect(_bar(tester).isScrollable, isFalse);
      await _pump(tester, labels, width: 700, textScale: 2.0);
      expect(_bar(tester).isScrollable, isTrue,
          reason: 'the derivation reads the current text scale, so a strip '
              'that fits at 1.0x does not crush its labels at 2.0x');
    });
  });

  group('AppTabBar is one strip everywhere', () {
    testWidgets('a scrollable strip starts flush, not at startOffset',
        (tester) async {
      await _pump(tester, const [
        'Feed',
        'People',
        'Clubs',
        'Discover',
        'Challenges',
        'Leaderboards',
        'Notifications',
      ]);
      expect(_bar(tester).isScrollable, isTrue);
      expect(_bar(tester).tabAlignment, TabAlignment.start);
      // Material's startOffset default indents the first tab by 52 dp. Flush
      // means the label sits within its own tab padding of the left edge.
      expect(_firstTabLeft(tester, 'Feed'),
          lessThanOrEqualTo(kTabLabelPadding.left));
    });

    testWidgets('a filled and a scrollable strip are the same height',
        (tester) async {
      await _pump(tester, const ['All', 'Runs', 'Gym', 'Food']);
      final filled = tester.getRect(find.byType(TabBar)).height;
      await _pump(tester, const [
        'Feed',
        'People',
        'Clubs',
        'Discover',
        'Challenges',
        'Leaderboards',
        'Notifications',
      ]);
      final scrolled = tester.getRect(find.byType(TabBar)).height;
      expect(scrolled, filled,
          reason: 'switching destinations must not move the strip vertically');
      expect(filled, AppTabBar.height);
    });

    testWidgets('reports the height the AppBar reserves for it',
        (tester) async {
      await _pump(tester, const ['All', 'Runs', 'Gym', 'Food']);
      final reserved = tester
          .widget<AppTabBar>(find.byType(AppTabBar))
          .preferredSize
          .height;
      expect(tester.getRect(find.byType(TabBar)).height, closeTo(reserved, 0.01));
    });

    testWidgets('the first tab sits at the same x either way', (tester) async {
      await _pump(tester, const ['Feed', 'Runs', 'Gym', 'Food']);
      final filledLeft = _firstTabLeft(tester, 'Feed');
      await _pump(tester, const [
        'Feed',
        'People',
        'Clubs',
        'Discover',
        'Challenges',
        'Leaderboards',
        'Notifications',
      ]);
      final scrolledLeft = _firstTabLeft(tester, 'Feed');
      expect(scrolledLeft, lessThan(filledLeft),
          reason: 'a filled tab centres its label in its share of the width, '
              'so flush-start puts the scrollable one further left — never '
              'the 52 dp further right the startOffset default gave it');
    });
  });
}

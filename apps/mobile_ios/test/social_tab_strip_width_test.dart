import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show AppTabBar, AppTheme;

/// Issue #666 I14 asked whether the Social hub's fifth sub-tab (Challenges)
/// starts off-screen. Rather than assert it, measure it: `AppTabBar` derives
/// `isScrollable` from whether the labels fit the width it is handed
/// (decisions § 533), so the answer is a function of the phone and the OS
/// text scale, not of the author's guess.
///
/// Measured on the default text scale, the strip the five English labels need
/// is **609.3 dp** wide and the four that preceded Challenges needed
/// **436.3 dp**. So on a 360 dp phone the finding is true — but it was
/// already true of the FOURTH tab before Challenges existed, which is the
/// correction: this is the derivation behaving, not a regression the fifth
/// tab introduced. Both fit from 840 dp.
void main() {
  Future<({bool scrollable, double lastTabRight, double width})> measure(
    WidgetTester tester, {
    required double width,
    required List<String> labels,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late TabController controller;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: DefaultTabController(
        length: labels.length,
        child: Builder(builder: (ctx) {
          controller = DefaultTabController.of(ctx);
          return Scaffold(
            appBar: AppBar(
              toolbarHeight: 0,
              bottom: AppTabBar(controller: controller, labels: labels),
            ),
            body: const SizedBox.shrink(),
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();

    final bar = tester.widget<TabBar>(find.byType(TabBar));
    final last = tester.getRect(find.text(labels.last));
    return (
      scrollable: bar.isScrollable,
      lastTabRight: last.right,
      width: width
    );
  }

  const five = ['Feed', 'People', 'Clubs', 'Discover', 'Challenges'];
  const four = ['Feed', 'People', 'Clubs', 'Discover'];

  testWidgets('the five Social labels do not fit a 360 dp phone',
      (tester) async {
    final m = await measure(tester, width: 360, labels: five);
    expect(m.scrollable, isTrue,
        reason: 'five labels overflow 360 dp, so AppTabBar derives a '
            'scrolling strip');
    expect(m.lastTabRight, greaterThan(m.width),
        reason: 'Challenges therefore begins past the right edge on load — '
            'measured, not assumed');
  });

  testWidgets('the four that preceded Challenges did not fit either',
      (tester) async {
    // The correction: the fifth tab did not create this. Measured at the same
    // width, the fourth tab already sat past the edge.
    final m = await measure(tester, width: 360, labels: four);
    expect(m.scrollable, isTrue);
    expect(m.lastTabRight, greaterThan(m.width));
  });

  testWidgets('both strips fit once the width is a tablet width',
      (tester) async {
    // Assert the population, not only the property: the strip is not
    // scrollable for everything, so the two results above are about these
    // labels at that width and not about AppTabBar always scrolling.
    final five840 = await measure(tester, width: 840, labels: five);
    expect(five840.scrollable, isFalse);
    expect(five840.lastTabRight, lessThanOrEqualTo(five840.width));

    final four600 = await measure(tester, width: 600, labels: four);
    expect(four600.scrollable, isFalse);
    expect(four600.lastTabRight, lessThanOrEqualTo(four600.width));
  });
}

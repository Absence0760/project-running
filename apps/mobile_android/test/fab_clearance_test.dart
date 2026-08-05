import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/fab_clearance.dart';

const _navBar = EdgeInsets.only(bottom: 48);

/// The gap a scroll view must leave so its last row clears the FAB: from the
/// bottom of the body to the top of the button.
double _gapNeeded(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('body'))).bottom -
    tester.getRect(find.byType(FloatingActionButton)).top;

Widget _body() => const SizedBox.expand(
    child: ColoredBox(key: ValueKey('body'), color: Color(0xFF000000)));

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MediaQuery(
    data: const MediaQueryData(
        size: Size(360, 800), padding: _navBar, viewPadding: _navBar),
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

FloatingActionButton _fab() =>
    FloatingActionButton.extended(onPressed: _noop, label: const Text('Go'));

void _noop() {}

void main() {
  group('fabScrollClearance (issue #666 C5)', () {
    testWidgets('covers the FAB on a phone with a 3-button nav bar',
        (tester) async {
      late double clearance;
      await _pump(
        tester,
        Scaffold(
          floatingActionButton: _fab(),
          body: Builder(builder: (c) {
            clearance = fabScrollClearance(c);
            return _body();
          }),
        ),
      );

      // Scaffold floats the button 16dp above the content bottom and lifts it
      // clear of the nav bar, so 48 + 16 + 56 of the list is occluded.
      expect(_gapNeeded(tester), 120);
      expect(clearance, greaterThanOrEqualTo(120));
    });

    testWidgets('does not double-count an inset a SafeArea already took',
        (tester) async {
      late double clearance;
      await _pump(
        tester,
        Scaffold(
          floatingActionButton: _fab(),
          body: SafeArea(
            top: false,
            child: Builder(builder: (c) {
              clearance = fabScrollClearance(c);
              return _body();
            }),
          ),
        ),
      );

      expect(_gapNeeded(tester), 72);
      expect(clearance, greaterThanOrEqualTo(72));
      expect(clearance, lessThan(120),
          reason: 'a SafeArea already consumed the nav bar');
    });

    testWidgets('does not double-count an inset a bottom nav bar covers',
        (tester) async {
      late double clearance;
      await _pump(
        tester,
        Scaffold(
          bottomNavigationBar: const SizedBox(height: 80),
          body: Scaffold(
            floatingActionButton: _fab(),
            body: Builder(builder: (c) {
              clearance = fabScrollClearance(c);
              return _body();
            }),
          ),
        ),
      );

      expect(_gapNeeded(tester), 72);
      expect(clearance, greaterThanOrEqualTo(72));
      expect(clearance, lessThan(120));
    });

    testWidgets('clears a column of two stacked FABs', (tester) async {
      late double clearance;
      await _pump(
        tester,
        Scaffold(
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.extended(
                  heroTag: 'a', onPressed: _noop, label: const Text('A')),
              const SizedBox(height: kFabStackGap),
              FloatingActionButton.extended(
                  heroTag: 'b', onPressed: _noop, label: const Text('B')),
            ],
          ),
          body: Builder(builder: (c) {
            clearance = fabScrollClearance(c, fabCount: 2);
            return _body();
          }),
        ),
      );

      final top = tester
          .getRect(find.byType(FloatingActionButton).first)
          .top;
      final gap = tester.getRect(find.byKey(const ValueKey('body'))).bottom - top;
      expect(gap, 120 + kFabHeight + kFabStackGap);
      expect(clearance, greaterThanOrEqualTo(gap));
    });
  });
}

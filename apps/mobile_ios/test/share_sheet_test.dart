import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/share_sheet.dart';

Rect _viewRect(WidgetTester tester) =>
    Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

void main() {
  group('shareOriginFor', () {
    testWidgets('resolves the invoking widget own global bounds', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 30, top: 40),
              child: SizedBox(
                width: 120,
                height: 50,
                child: Builder(builder: (ctx) {
                  captured = ctx;
                  return const SizedBox.expand();
                }),
              ),
            ),
          ),
        ),
      );

      expect(shareOriginFor(captured), const Rect.fromLTWH(30, 40, 120, 50));
    });

    testWidgets('a zero-size box falls back to an anchor inside the view',
        (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 0,
              height: 0,
              child: Builder(builder: (ctx) {
                captured = ctx;
                return const SizedBox.expand();
              }),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(SizedBox).first), Size.zero);

      final origin = shareOriginFor(captured);
      final view = _viewRect(tester);
      expect(origin.isEmpty, isFalse);
      expect(view.contains(origin.center), isTrue);
      expect(origin.left, greaterThanOrEqualTo(view.left));
      expect(origin.top, greaterThanOrEqualTo(view.top));
      expect(origin.right, lessThanOrEqualTo(view.right));
      expect(origin.bottom, lessThanOrEqualTo(view.bottom));
    });

    testWidgets('an unmounted context falls back to an anchor inside the view',
        (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(builder: (ctx) {
            captured = ctx;
            return const SizedBox(width: 10, height: 10);
          }),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(captured.mounted, isFalse);

      final origin = shareOriginFor(captured);
      expect(origin.isEmpty, isFalse);
      expect(_viewRect(tester).contains(origin.center), isTrue);
    });

    testWidgets('a box hanging past the view is clipped into it',
        (tester) async {
      late BuildContext captured;
      final view = _viewRect(tester);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: view.width * 4,
            maxHeight: view.height * 4,
            child: SizedBox(
              width: view.width * 4,
              height: view.height * 4,
              child: Builder(builder: (ctx) {
                captured = ctx;
                return const SizedBox.expand();
              }),
            ),
          ),
        ),
      );

      final origin = shareOriginFor(captured);
      expect(origin.isEmpty, isFalse);
      expect(view.contains(origin.topLeft), isTrue);
      expect(origin.right, lessThanOrEqualTo(view.right));
      expect(origin.bottom, lessThanOrEqualTo(view.bottom));
    });

    testWidgets('a box entirely off-view falls back rather than returning it',
        (tester) async {
      late BuildContext captured;
      final view = _viewRect(tester);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Transform.translate(
            offset: Offset(view.width * 3, view.height * 3),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Builder(builder: (ctx) {
                  captured = ctx;
                  return const SizedBox.expand();
                }),
              ),
            ),
          ),
        ),
      );

      final origin = shareOriginFor(captured);
      expect(origin.isEmpty, isFalse);
      expect(view.contains(origin.center), isTrue);
    });

    testWidgets('the fallback rect is itself non-empty', (tester) async {
      expect(shareOriginFallbackRect.isEmpty, isFalse);
    });
  });
}

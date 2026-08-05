import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Bottom-sheet contract guard (issue #666 C10). 31 `showModalBottomSheet`
/// call sites shared no presentation at all before this: 7 drew a drag
/// handle, 1 set a shape, and none of them agreed on a background. The
/// theme now owns all four, so a call site only spells out what it
/// genuinely differs on.
void main() {
  for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
    group('$name bottomSheetTheme', () {
      final sheet = theme.bottomSheetTheme;

      test('modal and persistent sheets share the surface fill', () {
        expect(sheet.modalBackgroundColor, theme.colorScheme.surface);
        expect(sheet.backgroundColor, theme.colorScheme.surface);
        expect(sheet.surfaceTintColor, Colors.transparent);
      });

      test('every sheet gets a drag handle in the line token', () {
        expect(sheet.showDragHandle, isTrue);
        expect(sheet.dragHandleColor, theme.dividerColor);
      });

      test('top corners are rounded and content is clipped to them', () {
        final shape = sheet.shape! as RoundedRectangleBorder;
        final radius = shape.borderRadius.resolve(TextDirection.ltr);
        expect(radius.topLeft.x, 20);
        expect(radius.topRight.x, 20);
        expect(radius.bottomLeft.x, 0);
        expect(sheet.clipBehavior, Clip.antiAlias);
      });
    });
  }

  testWidgets('a themed modal sheet renders the handle and the surface fill',
      (tester) async {
    final theme = AppTheme.light;
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: ctx,
              builder: (_) => const SizedBox(height: 120, child: Text('body')),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('body'), findsOneWidget);
    final material = tester.widget<Material>(find
        .descendant(of: find.byType(BottomSheet), matching: find.byType(Material))
        .first);
    expect(material.color, theme.colorScheme.surface);
    expect(material.clipBehavior, Clip.antiAlias);
    expect(find.bySemanticsLabel('Dismiss'), findsOneWidget);
  });
}

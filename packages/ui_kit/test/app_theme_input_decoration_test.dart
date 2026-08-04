import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Input-decoration guard (issue #666 S12). The form-sheet family used to
/// render three different field languages — stock underline, radius-4
/// outline, and a dense radius-4 outline — inside one navigation layer. The
/// theme now names the outlined one, at the same radius 12 the button
/// families took in round 3, and per-site `border:` declarations were
/// deleted so a field cannot opt back out by accident.
double _radiusOf(InputBorder? border) =>
    (border! as OutlineInputBorder)
        .borderRadius
        .resolve(TextDirection.ltr)
        .topLeft
        .x;

void main() {
  for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
    test('$name names the outlined language at radius 12', () {
      expect(theme.inputDecorationTheme.border, isA<OutlineInputBorder>());
      expect(_radiusOf(theme.inputDecorationTheme.border), 12);
    });

    testWidgets('$name: a bare field inherits the outline and keeps errorText',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Column(
            children: [
              TextField(decoration: InputDecoration(labelText: 'plain')),
              TextField(
                decoration:
                    InputDecoration(labelText: 'bad', errorText: 'required'),
              ),
            ],
          ),
        ),
      ));

      final decorators =
          tester.widgetList<InputDecorator>(find.byType(InputDecorator)).toList();
      expect(decorators.length, 2);
      for (final d in decorators) {
        expect(_radiusOf(d.decoration.border), 12,
            reason: 'the field must inherit the themed outline, not the '
                'stock underline or a per-site radius-4 outline');
      }
      expect(decorators.last.decoration.errorText, 'required');
      expect(find.text('required'), findsOneWidget);
    });
  }
}

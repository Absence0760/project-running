import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/password_field.dart';

Future<void> _pump(WidgetTester tester, TextEditingController ctl) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PasswordField(controller: ctl, labelText: 'Password'),
      ),
    ),
  );
}

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

void main() {
  group('PasswordField', () {
    testWidgets('starts obscured with a Show password toggle', (tester) async {
      await _pump(tester, TextEditingController());
      expect(_field(tester).obscureText, isTrue);
      expect(find.byTooltip('Show password'), findsOneWidget);
      expect(find.byIcon(Icons.visibility), findsOneWidget);
    });

    testWidgets('tapping the toggle reveals the text and flips the label',
        (tester) async {
      final ctl = TextEditingController(text: 'hunter2secret');
      await _pump(tester, ctl);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(_field(tester).obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    });

    testWidgets('tapping again re-obscures the field', (tester) async {
      await _pump(tester, TextEditingController());
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(_field(tester).obscureText, isTrue);
      expect(find.byTooltip('Show password'), findsOneWidget);
    });

    testWidgets(
        'forwards autofill hints, keyboard action, focus node and onSubmitted',
        (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      String? submitted;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PasswordField(
              controller: TextEditingController(),
              labelText: 'Password',
              focusNode: focus,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onSubmitted: (v) => submitted = v,
            ),
          ),
        ),
      );
      final field = _field(tester);
      expect(field.focusNode, same(focus));
      expect(field.autofillHints, contains(AutofillHints.newPassword));
      expect(field.textInputAction, TextInputAction.done);
      await tester.enterText(find.byType(TextField), 'hunter2secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submitted, 'hunter2secret');
    });
  });
}

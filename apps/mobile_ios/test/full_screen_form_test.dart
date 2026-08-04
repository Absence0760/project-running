import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/full_screen_form.dart';

Future<void> _open(
  WidgetTester tester, {
  required Widget body,
  String title = 'Form',
  bool Function()? isDirty,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showFullScreenForm<String>(
              ctx,
              title: title,
              builder: (_) => body,
              isDirty: isDirty,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // fullscreenDialog MaterialPageRoute: avoid pumpAndSettle (the route
  // slide-in + any cursor never settle under the fake clock).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('showFullScreenForm', () {
    testWidgets('pushes a fullscreen-dialog route with an AppBar title and the body',
        (tester) async {
      await _open(tester,
          title: 'Add gear', body: const Text('body-marker'));
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Add gear'), findsOneWidget);
      expect(find.text('body-marker'), findsOneWidget);
      // fullscreenDialog injects a Close affordance, not a Back arrow.
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
    });

    testWidgets('resolves to the value the form pops', (tester) async {
      String? result;
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  result = await showFullScreenForm<String>(
                    ctx,
                    title: 'Form',
                    builder: (inner) => TextButton(
                      onPressed: () => Navigator.pop(inner, 'saved'),
                      child: const Text('do-save'),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('do-save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(result, 'saved');
    });
  });

  group('showFullScreenForm — discard guard', () {
    testWidgets('dirty form: system back shows the confirm; Cancel keeps the form and its state',
        (tester) async {
      final ctl = TextEditingController();
      addTearDown(ctl.dispose);
      await _open(
        tester,
        body: TextField(controller: ctl),
        isDirty: () => ctl.text.isNotEmpty,
      );
      await tester.enterText(find.byType(TextField), 'typed');
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.text('You have unsaved changes. Leave without saving?'),
          findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(ctl.text, 'typed');
    });

    testWidgets('dirty form: confirming Discard pops the form', (tester) async {
      final ctl = TextEditingController();
      addTearDown(ctl.dispose);
      await _open(
        tester,
        body: TextField(controller: ctl),
        isDirty: () => ctl.text.isNotEmpty,
      );
      await tester.enterText(find.byType(TextField), 'typed');
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.widgetWithText(TextButton, 'Discard'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(TextField), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('clean form: system back pops without a confirm', (tester) async {
      final ctl = TextEditingController();
      addTearDown(ctl.dispose);
      await _open(
        tester,
        body: TextField(controller: ctl),
        isDirty: () => ctl.text.isNotEmpty,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('dirty form: the AppBar close button routes through the confirm',
        (tester) async {
      final ctl = TextEditingController();
      addTearDown(ctl.dispose);
      await _open(
        tester,
        body: TextField(controller: ctl),
        isDirty: () => ctl.text.isNotEmpty,
      );
      await tester.enterText(find.byType(TextField), 'typed');
      await tester.pump();

      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('no isDirty probe keeps the legacy immediate pop', (tester) async {
      await _open(tester, body: const Text('body-marker'));
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('body-marker'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  });

  group('FullScreenFormBody', () {
    testWidgets('renders children in a scroll view', (tester) async {
      await _open(
        tester,
        body: const FullScreenFormBody(
          children: [Text('a'), Text('b')],
        ),
      );
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  group('FormSectionLabel', () {
    testWidgets('uppercases the label text', (tester) async {
      await _open(tester, body: const FormSectionLabel('targets'));
      expect(find.text('TARGETS'), findsOneWidget);
    });
  });
}

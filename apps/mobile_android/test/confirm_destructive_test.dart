import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/confirm_destructive.dart';
import '../lib/widgets/confirm_discard.dart';

Future<bool?> _open(
  WidgetTester tester,
  Future<bool> Function(BuildContext) run,
) async {
  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => result = await run(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

Finder _dialogButton(String label) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, label),
    );

void main() {
  testWidgets('cancel comes first and the confirm carries error emphasis',
      (tester) async {
    await _open(
      tester,
      (ctx) => confirmDestructive(ctx,
          title: 'Delete route?', body: 'Gone for good.', confirmLabel: 'Delete'),
    );

    final actions = tester
        .widgetList<TextButton>(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextButton),
          ),
        )
        .toList();
    expect(actions, hasLength(2));
    expect((actions.first.child! as Text).data, 'Cancel');
    expect((actions.last.child! as Text).data, 'Delete');

    final scheme = Theme.of(tester.element(find.byType(AlertDialog))).colorScheme;
    final style = tester.widget<TextButton>(_dialogButton('Delete')).style;
    expect(style?.foregroundColor?.resolve({}), scheme.error);
    expect(tester.widget<TextButton>(_dialogButton('Cancel')).style?.foregroundColor,
        isNull);
  });

  testWidgets('confirming resolves true, cancelling resolves false',
      (tester) async {
    bool? got;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async => got = await confirmDestructive(ctx,
                  title: 'Remove device?', confirmLabel: 'Remove'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButton('Cancel'));
    await tester.pumpAndSettle();
    expect(got, isFalse);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButton('Remove'));
    await tester.pumpAndSettle();
    expect(got, isTrue);
  });

  testWidgets('barrier dismiss resolves false, never null', (tester) async {
    bool? got;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async => got = await confirmDestructive(ctx,
                  title: 'Delete photo?', confirmLabel: 'Delete'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(got, isFalse);
  });

  testWidgets('body is omitted entirely when null', (tester) async {
    await _open(
      tester,
      (ctx) => confirmDestructive(ctx, title: 'Clear route?', confirmLabel: 'Clear'),
    );
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).content,
      isNull,
    );
  });

  testWidgets('cancel falls back to the shared label and can be overridden',
      (tester) async {
    await _open(
      tester,
      (ctx) => confirmDestructive(ctx, title: 'Leave club?', confirmLabel: 'Leave'),
    );
    expect(_dialogButton('Cancel'), findsOneWidget);
    await tester.tap(_dialogButton('Cancel'));
    await tester.pumpAndSettle();

    await _open(
      tester,
      (ctx) => confirmDestructive(ctx,
          title: 'Leave club?', confirmLabel: 'Leave', cancelLabel: 'Stay'),
    );
    expect(_dialogButton('Stay'), findsOneWidget);
    expect(_dialogButton('Cancel'), findsNothing);
  });

  testWidgets('confirmDiscard renders through the shared destructive dialog',
      (tester) async {
    await _open(tester, (ctx) => confirmDiscard(ctx));
    expect(find.byType(AlertDialog), findsOneWidget);
    final scheme = Theme.of(tester.element(find.byType(AlertDialog))).colorScheme;
    expect(
      tester.widget<TextButton>(_dialogButton('Discard')).style?.foregroundColor
          ?.resolve({}),
      scheme.error,
    );
    expect(find.text('Discard changes?'), findsOneWidget);
  });
}

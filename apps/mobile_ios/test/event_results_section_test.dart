import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/event_detail_screen.dart';
import '../lib/social_service.dart';

EventResultView _result({
  required String? userId,
  String finisherStatus = 'finished',
  bool organiserApproved = false,
}) =>
    EventResultView(
      userId: userId,
      displayName: 'Me',
      runId: null,
      durationS: 1500,
      distanceM: 5000,
      rank: 1,
      finisherStatus: finisherStatus,
      organiserApproved: organiserApproved,
      ageGradePct: null,
      note: null,
      createdAt: DateTime(2026, 1, 1),
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<EventResultView> results,
  required String? myUserId,
  required bool submitting,
  required VoidCallback onRemove,
  required VoidCallback onSubmit,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: EventResultsSection(
          results: results,
          myUserId: myUserId,
          submitting: submitting,
          onSubmit: onSubmit,
          onRemove: onRemove,
          eventTitle: 'Riverside 10K',
          clubName: 'Richmond Run Club',
          certificateDate: DateTime(2026, 6, 12),
        ),
      ),
    ),
  );
}

void main() {
  group('EventResultsSection — remove my result', () {
    testWidgets('shows Remove mine when the viewer has a result', (tester) async {
      await _pump(
        tester,
        results: [_result(userId: 'u1')],
        myUserId: 'u1',
        submitting: false,
        onRemove: () {},
        onSubmit: () {},
      );
      expect(find.text('Remove mine'), findsOneWidget);
      expect(find.text('Submit my time'), findsNothing);
    });

    testWidgets('shows Submit my time when the viewer has no result',
        (tester) async {
      await _pump(
        tester,
        results: [_result(userId: 'someone-else')],
        myUserId: 'u1',
        submitting: false,
        onRemove: () {},
        onSubmit: () {},
      );
      expect(find.text('Submit my time'), findsOneWidget);
      expect(find.text('Remove mine'), findsNothing);
    });

    testWidgets('Remove mine asks to confirm; Cancel does not fire onRemove',
        (tester) async {
      var removed = false;
      await _pump(
        tester,
        results: [_result(userId: 'u1')],
        myUserId: 'u1',
        submitting: false,
        onRemove: () => removed = true,
        onSubmit: () {},
      );

      await tester.tap(find.text('Remove mine'));
      await tester.pumpAndSettle();
      expect(find.text('Remove your result?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(removed, isFalse);
    });

    testWidgets('Remove mine → confirm fires onRemove', (tester) async {
      var removed = false;
      await _pump(
        tester,
        results: [_result(userId: 'u1')],
        myUserId: 'u1',
        submitting: false,
        onRemove: () => removed = true,
        onSubmit: () {},
      );

      await tester.tap(find.text('Remove mine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove result'));
      await tester.pumpAndSettle();
      expect(removed, isTrue);
    });

    testWidgets('Remove mine is disabled while a removal is in flight',
        (tester) async {
      var removed = false;
      await _pump(
        tester,
        results: [_result(userId: 'u1')],
        myUserId: 'u1',
        submitting: true,
        onRemove: () => removed = true,
        onSubmit: () {},
      );

      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Remove mine'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.text('Remove mine'));
      await tester.pumpAndSettle();
      expect(find.text('Remove your result?'), findsNothing);
      expect(removed, isFalse);
    });
  });

  group('EventResultsSection — finisher certificate', () {
    Finder certButton() =>
        find.byIcon(Icons.workspace_premium_outlined);

    testWidgets('shows the certificate action for an approved finisher',
        (tester) async {
      await _pump(
        tester,
        results: [
          _result(
            userId: 'u1',
            finisherStatus: 'finished',
            organiserApproved: true,
          )
        ],
        myUserId: 'u1',
        submitting: false,
        onRemove: () {},
        onSubmit: () {},
      );
      expect(certButton(), findsOneWidget);
    });

    testWidgets('hides the certificate action until the result is approved',
        (tester) async {
      await _pump(
        tester,
        results: [
          _result(
            userId: 'someone-else',
            finisherStatus: 'finished',
            organiserApproved: false,
          )
        ],
        myUserId: 'u1',
        submitting: false,
        onRemove: () {},
        onSubmit: () {},
      );
      expect(certButton(), findsNothing);
    });

    testWidgets('hides the certificate action for a DNF', (tester) async {
      await _pump(
        tester,
        results: [
          _result(
            userId: 'someone-else',
            finisherStatus: 'dnf',
            organiserApproved: true,
          )
        ],
        myUserId: 'u1',
        submitting: false,
        onRemove: () {},
        onSubmit: () {},
      );
      expect(certButton(), findsNothing);
    });
  });
}

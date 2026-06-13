// Widget tests for the report sheet — mobile parity with the web
// submitReport flow. Each test plants a fake ApiClient and walks
// the user-facing flow: open sheet, pick reason, add notes,
// submit, surface the response or error inline.

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/report_sheet.dart';

class _FakeApiClient extends ApiClient {
  String? capturedTargetKind;
  String? capturedTargetId;
  String? capturedReason;
  String? capturedNotes;
  Object? errorToThrow;
  String returnId = 'rep-123';

  @override
  Future<String> submitReport({
    required String targetKind,
    required String targetId,
    required String reason,
    String? notes,
  }) async {
    capturedTargetKind = targetKind;
    capturedTargetId = targetId;
    capturedReason = reason;
    capturedNotes = notes;
    if (errorToThrow != null) throw errorToThrow!;
    return returnId;
  }
}

Future<void> _openSheet(
  WidgetTester tester,
  _FakeApiClient api, {
  String kind = 'user',
  String id = 'target-1',
}) async {
  // 1200 px tall surface fits the bottom-sheet plus a comfortable
  // host scaffold underneath. The default 600 px viewport puts the
  // Submit button below the modal's reserved height.
  await tester.binding.setSurfaceSize(const Size(400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // Mount a host page that opens the sheet on first frame. The
  // sheet itself is the test target.
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showReportSheet(
                context,
                api: api,
                targetKind: kind,
                targetId: id,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('ReportSheet', () {
    testWidgets('renders title + 5 reason radios + Submit button',
        (tester) async {
      await _openSheet(tester, _FakeApiClient());
      expect(find.text('Report user'), findsOneWidget);
      // Five reasons — pin the count + each label so a regression
      // that dropped one would fail loud (the migration's CHECK
      // constraint rejects values outside the documented set).
      expect(find.byType(RadioListTile<String>), findsNWidgets(5));
      expect(find.text('Spam'), findsOneWidget);
      expect(find.text('Harassment or abuse'), findsOneWidget);
      expect(find.text('Inappropriate content'), findsOneWidget);
      expect(find.text('Impersonation'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Submit report'), findsOneWidget);
    });

    testWidgets('title reflects the targetKind', (tester) async {
      await _openSheet(tester, _FakeApiClient(), kind: 'club');
      expect(find.text('Report club'), findsOneWidget);
    });

    testWidgets('club_post + run targets render their own titles (E2)',
        (tester) async {
      await _openSheet(tester, _FakeApiClient(), kind: 'club_post');
      expect(find.text('Report post'), findsOneWidget);
    });

    testWidgets('run target renders its own title (E2)', (tester) async {
      await _openSheet(tester, _FakeApiClient(), kind: 'run');
      expect(find.text('Report run'), findsOneWidget);
    });

    testWidgets('Submit forwards a run targetKind to the RPC (E2)',
        (tester) async {
      final api = _FakeApiClient();
      await _openSheet(tester, api, kind: 'run', id: 'run-9');
      await tester.tap(find.widgetWithText(FilledButton, 'Submit report'));
      await tester.pump();
      await tester.pump();
      expect(api.capturedTargetKind, 'run');
      expect(api.capturedTargetId, 'run-9');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Submit calls api with the picked reason + notes',
        (tester) async {
      // Headline contract: the reason radio's current value AND any
      // notes typed get forwarded to the RPC.
      final api = _FakeApiClient();
      await _openSheet(tester, api, kind: 'route', id: 'route-42');
      // Switch to "harassment".
      await tester.tap(find.text('Harassment or abuse'));
      await tester.pump();
      // Type notes.
      await tester.enterText(
        find.widgetWithText(TextField, 'Notes (optional)'),
        'this user impersonates a coach',
      );
      // Submit.
      await tester.tap(find.widgetWithText(FilledButton, 'Submit report'));
      // Plain pump — success path closes the sheet + shows a banner
      // (~3s timer). Use plain pump rather than pumpAndSettle.
      await tester.pump();
      await tester.pump();
      expect(api.capturedTargetKind, 'route');
      expect(api.capturedTargetId, 'route-42');
      expect(api.capturedReason, 'harassment');
      expect(api.capturedNotes, 'this user impersonates a coach');
      // Drain the success banner's auto-dismiss timer.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('empty notes get passed as null (not "")', (tester) async {
      // The RPC writes notes column with the value — null vs ""
      // matters for the moderator dashboard's "had context" filter.
      final api = _FakeApiClient();
      await _openSheet(tester, api);
      await tester.tap(find.widgetWithText(FilledButton, 'Submit report'));
      await tester.pump();
      await tester.pump();
      expect(api.capturedNotes, isNull);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
        'duplicate-report (Postgrest 23505) surfaces friendly message',
        (tester) async {
      // The unique(reporter_id, target_kind, target_id) constraint
      // raises 23505 on a second pending report. UI must explain
      // this rather than show the raw SQL error.
      final api = _FakeApiClient()
        ..errorToThrow = const PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
        );
      await _openSheet(tester, api);
      await tester.tap(find.widgetWithText(FilledButton, 'Submit report'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('already have a pending report'),
        findsOneWidget,
      );
      // Sheet stays open (didn't pop on error).
      expect(find.text('Report user'), findsOneWidget);
    });

    testWidgets('Cancel closes the sheet without an API call',
        (tester) async {
      final api = _FakeApiClient();
      await _openSheet(tester, api);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
      // Sheet is gone.
      expect(find.text('Report user'), findsNothing);
      // No API call.
      expect(api.capturedReason, isNull);
    });

    testWidgets('default reason is "spam" when user submits without picking',
        (tester) async {
      // Defensive: the first radio is selected by default so a user
      // who just types notes + hits Submit still files a typed
      // report. A regression that left _reason unset would either
      // crash on null or NPE the RPC call.
      final api = _FakeApiClient();
      await _openSheet(tester, api);
      await tester.tap(find.widgetWithText(FilledButton, 'Submit report'));
      await tester.pump();
      await tester.pump();
      expect(api.capturedReason, 'spam');
      await tester.pump(const Duration(seconds: 5));
    });
  });
}

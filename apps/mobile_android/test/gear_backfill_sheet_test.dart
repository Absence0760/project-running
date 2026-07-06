import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/preferences.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/gear_backfill_sheet.dart';

/// Fake [ApiClient] that records every addGearToRuns call. Lets the
/// widget test assert exactly which runs the sheet posted without
/// standing up Supabase.
class _FakeBackfillApi extends ApiClient {
  final List<({String gearId, List<String> runIds})> calls = [];
  Object? errorToThrow;

  @override
  Future<int> addGearToRuns(String gearId, List<String> runIds) async {
    calls.add((gearId: gearId, runIds: List<String>.from(runIds)));
    if (errorToThrow != null) throw errorToThrow!;
    return runIds.length;
  }
}

cm.Run _run({
  required String id,
  required DateTime startedAt,
  String activityType = 'run',
}) {
  return cm.Run(
    id: id,
    startedAt: startedAt,
    duration: const Duration(minutes: 30),
    distanceMetres: 5000.0,
    track: const [],
    source: cm.RunSource.app,
    metadata: <String, dynamic>{'activity_type': activityType},
  );
}

Future<Preferences> _makePrefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

void main() {
  group('gear_backfill_sheet', () {
    testWidgets('renders one row per candidate with everything selected',
        (tester) async {
      final api = _FakeBackfillApi();
      final prefs = await _makePrefs();
      final candidates = [
        _run(id: 'r1', startedAt: DateTime.utc(2026, 1, 5)),
        _run(id: 'r2', startedAt: DateTime.utc(2026, 1, 3)),
        _run(id: 'r3', startedAt: DateTime.utc(2026, 1, 1)),
      ];

      late BuildContext capturedCtx;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(builder: (ctx) {
            capturedCtx = ctx;
            return const SizedBox.shrink();
          }),
        ),
      ));

      unawaited(showGearBackfillSheet(
        context: capturedCtx,
        api: api,
        preferences: prefs,
        gearId: 'gear-1',
        gearName: 'Vaporfly',
        gearKind: 'shoe',
        candidates: candidates,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Header reflects the gear name + plural count copy.
      expect(find.textContaining('Attach past runs to Vaporfly?'),
          findsOneWidget);
      expect(find.textContaining('3'), findsAtLeastNWidgets(1));
      // Three rows.
      expect(find.byType(CheckboxListTile), findsNWidgets(3));
      // Attach button shows the full selection by default.
      expect(find.widgetWithText(FilledButton, 'Attach 3'), findsOneWidget);
    });

    testWidgets('Skip pops without calling addGearToRuns', (tester) async {
      final api = _FakeBackfillApi();
      final prefs = await _makePrefs();
      final candidates = [_run(id: 'r1', startedAt: DateTime.utc(2026, 1, 5))];

      late BuildContext capturedCtx;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(builder: (ctx) {
            capturedCtx = ctx;
            return const SizedBox.shrink();
          }),
        ),
      ));
      unawaited(showGearBackfillSheet(
        context: capturedCtx,
        api: api,
        preferences: prefs,
        gearId: 'gear-1',
        gearName: 'Vaporfly',
        gearKind: 'shoe',
        candidates: candidates,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.widgetWithText(TextButton, 'Skip'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.calls, isEmpty,
          reason: 'Skip must not fire any server call.');
    });

    testWidgets('Attach posts exactly the selected ids to addGearToRuns',
        (tester) async {
      final api = _FakeBackfillApi();
      final prefs = await _makePrefs();
      final candidates = [
        _run(id: 'r1', startedAt: DateTime.utc(2026, 1, 5)),
        _run(id: 'r2', startedAt: DateTime.utc(2026, 1, 3)),
        _run(id: 'r3', startedAt: DateTime.utc(2026, 1, 1)),
      ];

      late BuildContext capturedCtx;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(builder: (ctx) {
            capturedCtx = ctx;
            return const SizedBox.shrink();
          }),
        ),
      ));
      unawaited(showGearBackfillSheet(
        context: capturedCtx,
        api: api,
        preferences: prefs,
        gearId: 'gear-1',
        gearName: 'Vaporfly',
        gearKind: 'shoe',
        candidates: candidates,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Deselect the middle row.
      final boxes = find.byType(CheckboxListTile);
      await tester.tap(boxes.at(1));
      await tester.pump();
      expect(find.widgetWithText(FilledButton, 'Attach 2'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Attach 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(api.calls, hasLength(1));
      expect(api.calls.single.gearId, 'gear-1');
      expect(api.calls.single.runIds, ['r1', 'r3'],
          reason: 'only the still-selected ids should be posted, '
              'in the original candidate order.');
    });

    testWidgets('Select-all toggle deselects then reselects everything',
        (tester) async {
      final api = _FakeBackfillApi();
      final prefs = await _makePrefs();
      final candidates = [
        _run(id: 'r1', startedAt: DateTime.utc(2026, 1, 5)),
        _run(id: 'r2', startedAt: DateTime.utc(2026, 1, 3)),
      ];

      late BuildContext capturedCtx;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(builder: (ctx) {
            capturedCtx = ctx;
            return const SizedBox.shrink();
          }),
        ),
      ));
      unawaited(showGearBackfillSheet(
        context: capturedCtx,
        api: api,
        preferences: prefs,
        gearId: 'gear-1',
        gearName: 'Vaporfly',
        gearKind: 'shoe',
        candidates: candidates,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Initially all selected → toggle reads "Select none".
      expect(find.text('Select none'), findsOneWidget);
      await tester.tap(find.text('Select none'));
      await tester.pump();

      // Empty selection → button copy flips to "Skip", toggle to "Select all".
      expect(find.widgetWithText(FilledButton, 'Skip'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);

      await tester.tap(find.text('Select all'));
      await tester.pump();

      expect(find.widgetWithText(FilledButton, 'Attach 2'), findsOneWidget);

      // The toggle is a bare text GestureDetector — it must expose merged
      // button semantics so TalkBack announces it as actionable.
      final semantics = tester.getSemantics(find.text('Select none'));
      expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
    });
  });
}

// Tiny shim — `unawaited` lives on dart:async but importing for one
// usage is heavier than a 1-liner.
void unawaited(Future<dynamic> future) {}

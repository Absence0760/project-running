import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/goals.dart';
import '../lib/preferences.dart';
import '../lib/settings_sync.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/goal_editor_sheet.dart';

Future<Preferences> _makePrefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

/// Counts upsert calls and can gate / fail them, to drive the
/// double-submit guard and the save-failure path.
class _CountingPrefs extends Preferences {
  int upsertCalls = 0;
  bool throwOnUpsert = false;
  Completer<void>? gate;

  @override
  Future<void> upsertGoal(RunGoal goal) async {
    upsertCalls++;
    if (gate != null) await gate!.future;
    if (throwOnUpsert) throw Exception('disk full');
    await super.upsertGoal(goal);
  }
}

Future<_CountingPrefs> _makeCountingPrefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = _CountingPrefs();
  await prefs.init();
  return prefs;
}

/// Settings sync whose roam push always throws — exercises the L4
/// best-effort contract (a failed roam must not strand the sheet).
class _ThrowingSync extends SettingsSyncService {
  _ThrowingSync(Preferences prefs) : super(preferences: prefs);
  @override
  Future<void> pushWeeklyDistanceGoal() async => throw Exception('roam down');
}

Future<void> _pumpWithSync(
  WidgetTester tester,
  Preferences prefs,
  SettingsSyncService? sync, {
  void Function(String?)? onResult,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              final r = await showGoalEditorSheet(
                ctx,
                preferences: prefs,
                settingsSync: sync,
              );
              onResult?.call(r);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpSheet(
  WidgetTester tester,
  Preferences prefs, {
  RunGoal? existing,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showGoalEditorSheet(
              ctx,
              preferences: prefs,
              existing: existing,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  // Was `pumpAndSettle()`. That hangs against the full-screen
  // MaterialPageRoute (cursor + page-route animation never settle in
  // the test framework's fake clock). Two timed pumps cover the
  // 300 ms route slide-in.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('GoalEditorSheet', () {
    testWidgets('shows "New goal" title when no existing goal supplied',
        (tester) async {
      final prefs = await _makePrefs();
      await _pumpSheet(tester, prefs);
      expect(find.text('New goal'), findsOneWidget);
    });

    testWidgets(
        'shows "Edit goal" title and pre-populates distance from existing goal',
        (tester) async {
      final prefs = await _makePrefs();
      final goal = RunGoal(
        id: 'g1',
        period: GoalPeriod.week,
        distanceMetres: 40000,
      );
      await _pumpSheet(tester, prefs, existing: goal);
      expect(find.text('Edit goal'), findsOneWidget);
      // 40 km distance pre-populated in the distance field.
      expect(find.text('40.0'), findsOneWidget);
    });

    testWidgets('shows validation error when no target is set on save',
        (tester) async {
      final prefs = await _makePrefs();
      await _pumpSheet(tester, prefs);
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pump(); await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Set at least one target'), findsOneWidget);
    });

    testWidgets('shows validation error when distance is zero or negative',
        (tester) async {
      final prefs = await _makePrefs();
      await _pumpSheet(tester, prefs);
      // The distance TextField has hint text '-'. Use the suffix 'km' to
      // distinguish it from the other target fields.
      final distanceField = find.ancestor(
        of: find.textContaining('km'),
        matching: find.byType(TextField),
      );
      await tester.enterText(distanceField.first, '0');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pump(); await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Distance: enter a positive number'), findsOneWidget);
    });

    testWidgets('Cancel button dismisses the sheet without saving',
        (tester) async {
      final prefs = await _makePrefs();
      await _pumpSheet(tester, prefs);
      expect(find.text('New goal'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      // Pop animation for fullscreenDialog runs ~400-500ms; double-
      // pump well past so the AppBar title is gone.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('New goal'), findsNothing);
      expect(prefs.goals, isEmpty);
    });

    testWidgets('resolves to "Goal saved" after a successful save',
        (tester) async {
      final prefs = await _makePrefs();
      String? result;
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  result = await showGoalEditorSheet(ctx, preferences: prefs);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final distanceField = find.ancestor(
        of: find.textContaining('km'),
        matching: find.byType(TextField),
      );
      await tester.enterText(distanceField.first, '10');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(result, 'Goal saved');
    });

    testWidgets('resolves to "Goal deleted" when an existing goal is removed',
        (tester) async {
      final prefs = await _makePrefs();
      final goal = RunGoal(
        id: 'g1',
        period: GoalPeriod.week,
        distanceMetres: 20000,
      );
      await prefs.upsertGoal(goal);
      String? result;
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  result = await showGoalEditorSheet(
                    ctx,
                    preferences: prefs,
                    existing: goal,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('Delete'));
      await tester.tap(find.text('Delete'));
      // pumpAndSettle hangs on the editor's blinking-cursor TextField;
      // use timed pumps for the dialog slide-in (same as _pumpSheet).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Delete this goal?'), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Delete'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(result, 'Goal deleted');
      expect(prefs.goals, isEmpty);
    });

    testWidgets('a failed roam push still saves locally and pops (L4 best-effort)',
        (tester) async {
      final prefs = await _makePrefs();
      String? result;
      await _pumpWithSync(tester, prefs, _ThrowingSync(prefs),
          onResult: (r) => result = r);
      final distanceField = find.ancestor(
        of: find.textContaining('km'),
        matching: find.byType(TextField),
      );
      await tester.enterText(distanceField.first, '10');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      // The roam threw, but the local save committed and the sheet popped.
      expect(result, 'Goal saved');
      expect(prefs.goals, isNotEmpty);
    });

    testWidgets('a failed local save surfaces a banner and keeps the sheet open',
        (tester) async {
      final prefs = await _makeCountingPrefs();
      prefs.throwOnUpsert = true;
      await _pumpWithSync(tester, prefs, null);
      final distanceField = find.ancestor(
        of: find.textContaining('km'),
        matching: find.byType(TextField),
      );
      await tester.enterText(distanceField.first, '10');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining("Couldn't save the goal"), findsOneWidget);
      // Sheet stays open (its AppBar title is still mounted).
      expect(find.text('New goal'), findsOneWidget);
      expect(prefs.goals, isEmpty);
      await tester.pump(const Duration(seconds: 4)); // drain banner timer
    });

    testWidgets('double-tapping Save upserts the goal only once', (tester) async {
      final prefs = await _makeCountingPrefs();
      prefs.gate = Completer<void>();
      await _pumpWithSync(tester, prefs, null);
      final distanceField = find.ancestor(
        of: find.textContaining('km'),
        matching: find.byType(TextField),
      );
      await tester.enterText(distanceField.first, '10');
      await tester.ensureVisible(find.text('Save'));

      await tester.tap(find.text('Save'));
      // Second tap while the first upsert is gated in flight — the button is
      // disabled now, so the tap is expected to miss.
      await tester.tap(find.text('Save'), warnIfMissed: false);
      await tester.pump();

      expect(prefs.upsertCalls, 1);

      prefs.gate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
    });

    testWidgets('Cancelling the delete confirm keeps the goal', (tester) async {
      final prefs = await _makePrefs();
      final goal = RunGoal(
        id: 'g1',
        period: GoalPeriod.week,
        distanceMetres: 20000,
      );
      await prefs.upsertGoal(goal);
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await _pumpSheet(tester, prefs, existing: goal);

      await tester.ensureVisible(find.text('Delete'));
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Delete this goal?'), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(prefs.goals, isNotEmpty);
    });
  });
}

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_library_screen.dart';
import '../lib/training_service.dart';

TrainingPlanRow _plan(String id, String name) => TrainingPlanRow(
      id: id,
      userId: 'author-1',
      name: name,
      goalEvent: 'distance_full',
      goalDistanceM: 42195,
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2026, 8, 23),
      daysPerWeek: 5,
      status: 'completed',
      source: 'manual',
      isTemplate: true,
      isPublicTemplate: true,
    );

class _FakeTraining extends TrainingService {
  _FakeTraining({this.viewerId = 'u-viewer'});

  /// The library gates on the viewer id (an anon read of the template
  /// policy returns 0 rows, which used to render a false empty state),
  /// so a fake must declare who is looking.
  final String? viewerId;
  String? clonedTemplateId;
  String lastQuery = '';

  @override
  String? get currentUserId => viewerId;

  @override
  Future<List<PublicPlanLibraryEntry>> fetchPublicPlanLibrary({
    String query = '',
  }) async {
    lastQuery = query;
    final all = [
      PublicPlanLibraryEntry(
        plan: _plan('tmpl-1', 'Sub-4 Marathon'),
        authorHandle: 'Coach Dana',
      ),
      PublicPlanLibraryEntry(
        plan: _plan('tmpl-2', 'Beginner Half'),
        authorHandle: null,
      ),
    ];
    if (query.trim().isEmpty) return all;
    return all
        .where((e) => e.plan.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  @override
  Future<String> clonePublicPlan({
    required String templateId,
    DateTime? startDate,
  }) async {
    clonedTemplateId = templateId;
    return 'cloned-plan-id';
  }

  @override
  Future<({TrainingPlanRow? plan, List<PlanWeekRow> weeks, List<PlanWorkoutRow> workouts})>
      fetchPlan(String id) async =>
          (plan: null, weeks: const <PlanWeekRow>[], workouts: const <PlanWorkoutRow>[]);
}

Widget _host(TrainingService t) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlanLibraryScreen(training: t),
    );

void main() {
  testWidgets('library lists public plans with author handle + anonymous fallback',
      (tester) async {
    final t = _FakeTraining();
    await tester.pumpWidget(_host(t));
    await tester.pumpAndSettle();

    expect(find.text('Sub-4 Marathon'), findsOneWidget);
    expect(find.text('Beginner Half'), findsOneWidget);
    // Named author shown; the null-handle plan falls back to anonymous.
    expect(find.text('by Coach Dana'), findsOneWidget);
    expect(find.text('by a runner'), findsOneWidget);
  });

  testWidgets('search filters the list', (tester) async {
    final t = _FakeTraining();
    await tester.pumpWidget(_host(t));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'beginner');
    // Debounced 300ms.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(t.lastQuery, 'beginner');
    expect(find.text('Beginner Half'), findsOneWidget);
    expect(find.text('Sub-4 Marathon'), findsNothing);
  });

  testWidgets('tapping a plan opens preview and clone invokes clonePublicPlan',
      (tester) async {
    final t = _FakeTraining();
    await tester.pumpWidget(_host(t));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sub-4 Marathon'));
    await tester.pumpAndSettle();

    // Preview screen shows the clone CTA.
    final cloneBtn = find.widgetWithText(FilledButton, 'Clone into my plans');
    expect(cloneBtn, findsOneWidget);

    await tester.tap(cloneBtn);
    await tester.pump();

    expect(t.clonedTemplateId, 'tmpl-1');
  });
}

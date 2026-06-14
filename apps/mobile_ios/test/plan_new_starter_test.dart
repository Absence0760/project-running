import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_new_screen.dart';
import '../lib/social_service.dart';
import '../lib/training.dart';
import '../lib/training_service.dart';

class _FakeTraining extends TrainingService {
  ({String name, GoalEvent goal, int days})? created;

  @override
  Future<TrainingGender> fetchViewerGender() async => null;

  @override
  Future<int?> fetchViewerAge() async => null;

  @override
  Future<List<TrainingPlanRow>> fetchClubTemplates(String clubId) async => [];

  @override
  Future<
      ({
        TrainingPlanRow? plan,
        List<PlanWeekRow> weeks,
        List<PlanWorkoutRow> workouts
      })> fetchPlan(String id) async =>
      (plan: null, weeks: <PlanWeekRow>[], workouts: <PlanWorkoutRow>[]);

  @override
  Future<TrainingPlanRow> createPlan({
    required String name,
    required GoalEvent goalEvent,
    required double goalDistanceM,
    int? goalTimeSec,
    int? recent5kSec,
    required DateTime startDate,
    required int daysPerWeek,
    String? notes,
    required GeneratedPlan generated,
  }) async {
    created = (name: name, goal: goalEvent, days: daysPerWeek);
    return TrainingPlanRow(
      id: 'new-plan',
      userId: 'u',
      name: name,
      goalEvent: goalEventDbValue(goalEvent),
      goalDistanceM: goalDistanceM,
      startDate: startDate,
      endDate: startDate.add(const Duration(days: 84)),
      daysPerWeek: daysPerWeek,
      status: 'active',
      source: 'generated',
      isTemplate: false,
      isPublicTemplate: false,
    );
  }
}

class _FakeSocial extends SocialService {
  @override
  Future<List<ClubView>> fetchMyClubs() async => [];
}

Widget _host(TrainingService t, SocialService s) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlanNewScreen(training: t, social: s),
    );

void main() {
  testWidgets('starter card renders and opens the picker', (tester) async {
    final t = _FakeTraining();
    await tester.pumpWidget(_host(t, _FakeSocial()));
    await tester.pump();

    expect(find.text('Start from a built-in plan'), findsOneWidget);
    expect(find.text('Browse starter plans'), findsOneWidget);

    await tester.tap(find.text('Browse starter plans'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a starter plan'), findsOneWidget);
    expect(find.text('Couch to 5K (beginner walk-run)'), findsOneWidget);
    expect(find.text('Half Marathon — 12 weeks'), findsOneWidget);
    expect(find.text('Marathon — 16 weeks'), findsOneWidget);
  });

  testWidgets('picking a starter creates a plan from its preset', (tester) async {
    final t = _FakeTraining();
    await tester.pumpWidget(_host(t, _FakeSocial()));
    await tester.pump();

    await tester.tap(find.text('Browse starter plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marathon — 16 weeks'));
    await tester.pump();

    expect(t.created, isNotNull);
    expect(t.created!.name, 'Marathon — 16 weeks');
    expect(t.created!.goal, GoalEvent.distanceFull);
    expect(t.created!.days, 5);
  });
}

import 'dart:io' show SocketException;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/coaching_athlete_screen.dart';

class _FakeApi extends ApiClient {
  _FakeApi({
    this.runs = const [],
    this.overview,
    this.plans = const [],
    this.assignError,
    this.loadError,
  });

  final List<AthleteRunSummary> runs;
  final AthletePlanOverview? overview;
  final List<TrainingPlanRow> plans;
  final String? assignError;
  final Object? loadError;

  String? lastAssignedPlanId;

  @override
  String? get userId => 'coach-1';

  @override
  Future<List<AthleteRunSummary>> fetchAthleteRuns(String athleteId,
          {int limit = 20}) async {
    if (loadError != null) throw loadError!;
    return runs;
  }

  @override
  Future<AthletePlanOverview?> fetchAthletePlanOverview(String athleteId) async =>
      overview;

  @override
  Future<List<TrainingPlanRow>> fetchMyPlans({int limit = 100}) async => plans;

  @override
  Future<String> assignPlanToAthlete({
    required String sourcePlanId,
    required String athleteId,
    required DateTime startDate,
    String? Function(DateTime)? toIso,
  }) async {
    if (assignError != null) throw Exception(assignError);
    lastAssignedPlanId = sourcePlanId;
    return 'new-plan';
  }
}

TrainingPlanRow _plan(String id, String name, {String? assignedBy}) =>
    TrainingPlanRow(
      id: id,
      userId: 'coach-1',
      name: name,
      goalEvent: 'marathon',
      goalDistanceM: 42195,
      startDate: DateTime.utc(2026, 1, 1),
      endDate: DateTime.utc(2026, 3, 1),
      daysPerWeek: 5,
      status: 'active',
      source: 'app',
      isTemplate: false,
      isPublicTemplate: false,
      assignedByCoachId: assignedBy,
    );

AthleteRunSummary _run(String id) => AthleteRunSummary(
      id: id,
      startedAt: DateTime.utc(2026, 1, 10, 7),
      distanceM: 10000,
      durationS: 3000,
      isPublic: true,
      source: 'app',
      routeId: null,
      activityType: 'run',
      metadata: null,
    );

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Future<void> _pump(WidgetTester tester, ApiClient api, Preferences prefs) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CoachingAthleteScreen(
        api: api,
        preferences: prefs,
        athleteId: 'a1',
        displayName: 'Alice Runner',
        acceptedAt: DateTime.utc(2026, 1, 2),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets('shows recent runs and the no-plan empty state', (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(runs: [_run('r1')]);
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text('Alice Runner'), findsWidgets);
    // No active plan AND no coach plans → the "create a plan first" hint
    // (mirrors web's `assignNoPlans` branch).
    expect(find.text(l10n.coachingAthleteAssignNoPlans), findsOneWidget);
    expect(find.text(l10n.coachingAthleteRecentRuns), findsOneWidget);
  });

  testWidgets('offers the assign control when the coach has plans and the '
      'athlete has none', (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(plans: [_plan('p1', 'Base Builder')]);
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.coachingAthleteAssignTitle), findsOneWidget);
    expect(find.text(l10n.coachingAthleteAssignButton), findsOneWidget);
  });

  testWidgets('shows the assigned-by-you badge for a plan the coach assigned',
      (tester) async {
    final prefs = await _prefs();
    final plan = _plan('p1', 'My Plan', assignedBy: 'coach-1');
    final overview = AthletePlanOverview(
      plan: plan,
      weeks: const [],
      workouts: const [],
      completionPct: 0,
    );
    await _pump(tester, _FakeApi(overview: overview), prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.coachingAthleteAssignedByYou), findsOneWidget);
  });

  testWidgets('surfaces the assign RPC raise as a banner (no swallow)',
      (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(
      plans: [_plan('p1', 'Base Builder')],
      assignError: 'athlete already has an active plan',
    );
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Pick the plan, then assign.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Base Builder').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.coachingAthleteAssignButton));
    await tester.pump();
    await tester.pump();

    expect(find.text('athlete already has an active plan'), findsOneWidget);
    // showTopBanner schedules an auto-dismiss timer; drain it past the hard
    // ceiling so the test doesn't trip the pending-timer invariant.
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets(
      'shows friendly, localized copy (not the raw exception) when the '
      'athlete load fails', (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(
      loadError: const SocketException("Failed host lookup: 'xyz.supabase.co'"),
    );
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.text(l10n.coachingAthleteLoadError(l10n.authErrorOffline)),
        findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
    expect(find.textContaining('Exception:'), findsNothing);

    // showTopBanner schedules an auto-dismiss timer; drain it past the hard
    // ceiling so the test doesn't trip the pending-timer invariant.
    await tester.pump(const Duration(seconds: 7));
  });
}

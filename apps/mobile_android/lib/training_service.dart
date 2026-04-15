import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'training.dart';

/// View-model pairing a plan row with its current-week index + today's
/// workout + completion percentage. Used by the dashboard/Run-tab card.
class ActivePlanOverview {
  final TrainingPlanRow plan;
  final List<PlanWeekRow> weeks;
  final List<PlanWorkoutRow> workouts;
  final PlanWorkoutRow? todayWorkout;
  final int completionPct;
  final int currentWeekIndex;

  const ActivePlanOverview({
    required this.plan,
    required this.weeks,
    required this.workouts,
    required this.todayWorkout,
    required this.completionPct,
    required this.currentWeekIndex,
  });
}

class TrainingService extends ChangeNotifier {
  SupabaseClient get _c => Supabase.instance.client;
  String? get _uid => _c.auth.currentUser?.id;

  Future<List<TrainingPlanRow>> fetchMyPlans() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _c
        .from('training_plans')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(TrainingPlanRow.fromJson)
        .toList();
  }

  Future<({TrainingPlanRow? plan, List<PlanWeekRow> weeks, List<PlanWorkoutRow> workouts})>
      fetchPlan(String id) async {
    final planRow = await _c
        .from('training_plans')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (planRow == null) {
      return (
        plan: null,
        weeks: <PlanWeekRow>[],
        workouts: <PlanWorkoutRow>[],
      );
    }
    final weekRows = await _c
        .from('plan_weeks')
        .select()
        .eq('plan_id', id)
        .order('week_index', ascending: true);
    final weeks = (weekRows as List)
        .cast<Map<String, dynamic>>()
        .map(PlanWeekRow.fromJson)
        .toList();
    if (weeks.isEmpty) {
      return (
        plan: TrainingPlanRow.fromJson(planRow),
        weeks: <PlanWeekRow>[],
        workouts: <PlanWorkoutRow>[],
      );
    }
    final woRows = await _c
        .from('plan_workouts')
        .select()
        .inFilter('week_id', weeks.map((w) => w.id).toList())
        .order('scheduled_date', ascending: true);
    final workouts = (woRows as List)
        .cast<Map<String, dynamic>>()
        .map(PlanWorkoutRow.fromJson)
        .toList();
    return (
      plan: TrainingPlanRow.fromJson(planRow),
      weeks: weeks,
      workouts: workouts,
    );
  }

  Future<PlanWorkoutRow?> fetchWorkout(String id) async {
    final row = await _c
        .from('plan_workouts')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : PlanWorkoutRow.fromJson(row);
  }

  Future<ActivePlanOverview?> fetchActiveOverview() async {
    final uid = _uid;
    if (uid == null) return null;
    final planRow = await _c
        .from('training_plans')
        .select()
        .eq('user_id', uid)
        .eq('status', 'active')
        .maybeSingle();
    if (planRow == null) return null;
    final plan = TrainingPlanRow.fromJson(planRow);
    final res = await fetchPlan(plan.id);
    if (res.plan == null) return null;
    final today = toIsoDate(DateTime.now());
    final todayWorkout = res.workouts
        .where((w) =>
            toIsoDate(w.scheduledDate) == today && w.kind != 'rest')
        .cast<PlanWorkoutRow?>()
        .firstOrNull;
    final active = res.workouts.where((w) => w.kind != 'rest').toList();
    final done = active.where((w) => w.completedRunId != null).length;
    final pct = active.isEmpty ? 0 : (100 * done / active.length).round();
    final startDate = parseIsoDate(toIsoDate(plan.startDate));
    final dayIndex = DateTime.now().difference(startDate).inDays;
    final currentWeek = dayIndex < 0
        ? 0
        : (dayIndex ~/ 7).clamp(0, res.weeks.length - 1);
    return ActivePlanOverview(
      plan: plan,
      weeks: res.weeks,
      workouts: res.workouts,
      todayWorkout: todayWorkout,
      completionPct: pct,
      currentWeekIndex: currentWeek,
    );
  }

  /// Write a freshly generated plan — plan row, weeks, workouts. Auto-
  /// completes any existing active plan so the partial unique index
  /// (one-active-per-user) doesn't reject the insert.
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
    final uid = _uid;
    if (uid == null) {
      throw Exception(
        'Please sign in first — plans sync to your account.',
      );
    }

    // Client-side validation mirroring the TS path. Cheaper to reject here
    // with a readable message than to catch a PostgrestError 23xxx later.
    if (name.trim().isEmpty) {
      throw Exception('Name is required.');
    }
    if (goalDistanceM <= 0) {
      throw Exception('Goal distance must be positive.');
    }
    if (daysPerWeek < 3 || daysPerWeek > 7) {
      throw Exception('Days per week must be between 3 and 7.');
    }
    if (goalTimeSec != null && goalTimeSec <= 0) {
      throw Exception('Goal time must be positive.');
    }
    if (recent5kSec != null && recent5kSec <= 0) {
      throw Exception('Recent 5K time must be positive.');
    }
    if (generated.weeks.isEmpty) {
      throw Exception('Generated plan has no weeks.');
    }
    // Defence in depth for the same class of generator bug we fixed in
    // training.ts — catch any null kind before the DB rejects the insert.
    for (final w in generated.weeks) {
      for (final wo in w.workouts) {
        // kind is non-nullable in Dart, but an uninitialised code path
        // could still produce WorkoutKind.rest unintentionally; we rely on
        // the non-null type rather than a null check here.
        if (wo.scheduledDate.isBefore(DateTime(2000))) {
          throw Exception(
            'Generator produced a workout with no date (week ${w.weekIndex}).',
          );
        }
      }
    }

    await _c
        .from('training_plans')
        .update({'status': 'completed'})
        .eq('user_id', uid)
        .eq('status', 'active');

    final inserted = await _c
        .from('training_plans')
        .insert({
          'user_id': uid,
          'name': name.trim(),
          'goal_event': goalEventDbValue(goalEvent),
          'goal_distance_m': goalDistanceM,
          'goal_time_seconds': goalTimeSec,
          'start_date': toIsoDate(startDate),
          'end_date': toIsoDate(generated.endDate),
          'days_per_week': daysPerWeek,
          'vdot': generated.vdot,
          'current_5k_seconds': recent5kSec,
          'status': 'active',
          'notes': notes?.trim(),
        })
        .select()
        .single();
    final plan = TrainingPlanRow.fromJson(inserted);

    final weekRows = await _c
        .from('plan_weeks')
        .insert([
          for (final w in generated.weeks)
            {
              'plan_id': plan.id,
              'week_index': w.weekIndex,
              'phase': planPhaseDbValue(w.phase),
              'target_volume_m': w.targetVolumeM,
              'notes': w.notes,
            }
        ])
        .select();

    final byIndex = <int, String>{};
    for (final r in weekRows as List) {
      final m = r as Map<String, dynamic>;
      byIndex[m['week_index'] as int] = m['id'] as String;
    }

    final workoutPayload = <Map<String, dynamic>>[];
    for (final w in generated.weeks) {
      final weekId = byIndex[w.weekIndex]!;
      for (final wo in w.workouts) {
        workoutPayload.add({
          'week_id': weekId,
          'scheduled_date': toIsoDate(wo.scheduledDate),
          'kind': workoutKindDbValue(wo.kind),
          'target_distance_m': wo.targetDistanceM,
          'target_duration_seconds': wo.targetDurationSeconds,
          'target_pace_sec_per_km': wo.targetPaceSecPerKm,
          'target_pace_tolerance_sec': wo.targetPaceToleranceSec,
          'structure': wo.structure?.toJson(),
          'notes': wo.notes,
        });
      }
    }
    if (workoutPayload.isNotEmpty) {
      await _c.from('plan_workouts').insert(workoutPayload);
    }

    notifyListeners();
    return plan;
  }

  Future<void> updateStatus(String id, String status) async {
    await _c.from('training_plans').update({'status': status}).eq('id', id);
    notifyListeners();
  }

  Future<void> deletePlan(String id) async {
    await _c.from('training_plans').delete().eq('id', id);
    notifyListeners();
  }

  Future<void> markCompleted(String workoutId, String? runId) async {
    await _c.from('plan_workouts').update({
      'completed_run_id': runId,
      'completed_at': runId == null ? null : DateTime.now().toIso8601String(),
    }).eq('id', workoutId);
    notifyListeners();
  }
}

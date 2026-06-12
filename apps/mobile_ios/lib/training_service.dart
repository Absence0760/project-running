import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'training.dart' show TrainingGender;

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
  final SupabaseClient? _override;

  TrainingService() : _override = null;

  /// Test-only DI seam mirroring `ApiClient.withClient` and
  /// `SocialService.withClient`. Production callsites use the unnamed
  /// constructor and resolve through the global; tests inject a
  /// real-but-local-loopback `SupabaseClient` so the Supabase-touching
  /// methods can be driven without booting `Supabase.initialize`.
  @visibleForTesting
  TrainingService.withClient(SupabaseClient client) : _override = client;

  SupabaseClient get _c {
    final override = _override;
    if (override != null) return override;
    if (!ApiClient.isInitialized) {
      throw StateError(
        'TrainingService called before Supabase.initialize() resolved.',
      );
    }
    return Supabase.instance.client;
  }
  String? get _uid => _c.auth.currentUser?.id;

  /// Persona-hunt Round 3 finding Woman #3. Reads the viewer's
  /// `user_profiles.gender` so the plan wizard can apply the
  /// gender-aware pace calibration. Returns null when the column is
  /// unset (the default) — pacesFromGoalPace then uses the
  /// male-derived curve unchanged. Mirror of the inline supabase
  /// read on web `PlanEditor.svelte`.
  ///
  /// L4 best-effort by contract: the plan wizard's initState awaits
  /// this without blocking, and any failure here only means the
  /// paces fall through to the unmodified male-derived curve. The
  /// try/catch must therefore wrap BOTH the `_uid` access (which
  /// touches `_c`, which throws `StateError` in widget tests that
  /// don't initialise Supabase) AND the network read. A regression
  /// that narrowed the catch to the inner read alone surfaced as
  /// `plan_new_screen_test` failing with "TrainingService called
  /// before Supabase.initialize() resolved" in CI.
  Future<TrainingGender> fetchViewerGender() async {
    try {
      final uid = _uid;
      if (uid == null) return null;
      final row = await _c
          .from('user_profiles')
          .select('gender')
          .eq('id', uid)
          .maybeSingle();
      final g = row?['gender'] as String?;
      if (g == 'male' || g == 'female' || g == 'nonbinary') return g;
    } catch (_) {
      /* L4 best-effort — fall back to null on any failure,
         including the not-yet-initialised StateError thrown by
         the _c getter in widget tests. */
    }
    return null;
  }

  /// Persona-hunt finding Older #30. Reads the viewer's
  /// `user_profiles.date_of_birth` and returns whole years so the plan
  /// wizard can apply the masters recovery calibration (50+). Returns
  /// null when the column is unset or unparseable — generatePlan then
  /// uses the standard younger-physiology schedule. Same L4 best-effort
  /// contract as fetchViewerGender (the try/catch must wrap the `_uid`
  /// access too, for widget tests without an initialised Supabase).
  Future<int?> fetchViewerAge() async {
    try {
      final uid = _uid;
      if (uid == null) return null;
      final row = await _c
          .from('user_profiles')
          .select('date_of_birth')
          .eq('id', uid)
          .maybeSingle();
      final dob = row?['date_of_birth'] as String?;
      if (dob == null) return null;
      final born = DateTime.tryParse(dob);
      if (born == null) return null;
      final now = DateTime.now();
      var age = now.year - born.year;
      if (now.month < born.month ||
          (now.month == born.month && now.day < born.day)) {
        age--;
      }
      if (age >= 0 && age < 120) return age;
    } catch (_) {
      /* L4 best-effort — null on any failure. */
    }
    return null;
  }

  /// Plan templates owned by `clubId`. Visible to club members per RLS.
  Future<List<TrainingPlanRow>> fetchClubTemplates(String clubId) async {
    final rows = await _c
        .from('training_plans')
        .select()
        .eq('is_template', true)
        .eq('club_id', clubId)
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(TrainingPlanRow.fromJson)
        .toList();
  }

  /// Publish one of the viewer's plans as a template under a club they
  /// admin. Returns the new template id. Mirrors the canonical web
  /// path at `apps/web/src/lib/data.ts#publishPlanAsTemplate` — a
  /// multi-table INSERT rather than an RPC (there is no
  /// `publish_plan_as_template` function server-side; only
  /// `clone_plan_template` exists, for the adopt direction).
  ///
  /// `vdot` + `current_5k_seconds` are intentionally nulled on the
  /// template row — they're the publisher's personal fitness numbers
  /// and would otherwise leak to every club member via
  /// `fetchClubTemplates` (see migration 20260721_001_plan_templates_strip_fitness).
  Future<String> publishPlanAsTemplate({
    required String planId,
    required String clubId,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');

    final src = await fetchPlan(planId);
    final source = src.plan;
    if (source == null) {
      throw Exception('Source plan not found');
    }
    if (source.userId != uid) {
      throw Exception('Only the plan owner can publish');
    }

    final templateRow = await _c.from('training_plans').insert({
      'user_id': uid,
      'name': source.name,
      'goal_event': source.goalEvent,
      'goal_distance_m': source.goalDistanceM,
      'goal_time_seconds': source.goalTimeSeconds,
      'start_date': toIsoDate(source.startDate),
      'end_date': toIsoDate(source.endDate),
      'days_per_week': source.daysPerWeek,
      'vdot': null,
      'current_5k_seconds': null,
      'status': 'completed',
      'source': source.source,
      'notes': source.notes,
      'rules': source.rules,
      'is_template': true,
      'club_id': clubId,
      'parent_template_id': null,
    }).select('id').single();
    final newPlanId = templateRow['id'] as String;

    if (src.weeks.isEmpty) {
      notifyListeners();
      return newPlanId;
    }

    final weekRes = await _c.from('plan_weeks').insert([
      for (final w in src.weeks)
        {
          'plan_id': newPlanId,
          'week_index': w.weekIndex,
          'phase': w.phase,
          'target_volume_m': w.targetVolumeM,
          'notes': w.notes,
        },
    ]).select('id, week_index');

    final byIdx = <int, String>{};
    for (final r in weekRes as List) {
      final m = r as Map<String, dynamic>;
      byIdx[m['week_index'] as int] = m['id'] as String;
    }
    final oldToNew = <String, String>{};
    for (final w in src.weeks) {
      final newId = byIdx[w.weekIndex];
      if (newId != null) oldToNew[w.id] = newId;
    }

    final workoutPayload = <Map<String, dynamic>>[];
    for (final w in src.workouts) {
      final newWeekId = oldToNew[w.weekId];
      if (newWeekId == null) continue;
      workoutPayload.add({
        'week_id': newWeekId,
        'scheduled_date': toIsoDate(w.scheduledDate),
        'kind': w.kind,
        'target_distance_m': w.targetDistanceM,
        'target_duration_seconds': w.targetDurationSeconds,
        'target_pace_sec_per_km': w.targetPaceSecPerKm,
        'target_pace_tolerance_sec': w.targetPaceToleranceSec,
        'structure': w.structure,
        'notes': w.notes,
      });
    }
    if (workoutPayload.isNotEmpty) {
      await _c.from('plan_workouts').insert(workoutPayload);
    }
    notifyListeners();
    return newPlanId;
  }

  /// Adopt a club template — RPC clones it back into a personal plan.
  /// Parameter names mirror the server function signature
  /// (`clone_plan_template(template_id uuid, new_start_date date)`)
  /// exactly — postgrest passes these through verbatim, so a typo
  /// surfaces as `PGRST202 function not found`.
  Future<String> clonePlanTemplate({
    required String templateId,
    DateTime? startDate,
  }) async {
    final newId = await _c.rpc(
      'clone_plan_template',
      params: {
        'template_id': templateId,
        'new_start_date': toIsoDate(startDate ?? DateTime.now()),
      },
    );
    notifyListeners();
    return newId as String;
  }

  /// Duplicate a plan week — insert a copy right after [weekIndex], pushing
  /// every later week + the plan end date back by 7 days. The
  /// (plan_id, week_index) re-index is atomic server-side (duplicate_plan_week
  /// RPC) — a client-side multi-update would transiently break the unique
  /// index. Mirrors web `data.ts#duplicatePlanWeek`. Returns the new week id.
  Future<String> duplicatePlanWeek(String planId, int weekIndex) async {
    final newId = await _c.rpc(
      'duplicate_plan_week',
      params: {
        'p_plan_id': planId,
        'p_week_index': weekIndex,
      },
    );
    notifyListeners();
    return newId as String;
  }

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
          'source': 'generated',
          // Match web's `notes?.trim() || null` — whitespace-only
          // collapses to null so the column stays clean for
          // `IS NOT NULL` filters. Mobile previously stored `""`.
          'notes': _trimToNull(notes),
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

  /// Look up the plan that owns a given workout. Walks via `plan_weeks`
  /// because `plan_workouts` doesn't carry a direct `plan_id` column.
  /// Returns null when the row is missing or the user lacks RLS access.
  Future<TrainingPlanRow?> fetchPlanForWorkout(PlanWorkoutRow wo) async {
    try {
      final week = await _c
          .from(PlanWeekRow.table)
          .select()
          .eq('id', wo.weekId)
          .maybeSingle();
      if (week == null) return null;
      final w = PlanWeekRow.fromJson(week);
      final plan = await _c
          .from(TrainingPlanRow.table)
          .select()
          .eq('id', w.planId)
          .maybeSingle();
      if (plan == null) return null;
      return TrainingPlanRow.fromJson(plan);
    } catch (e) {
      debugPrint('[TrainingService.fetchPlanForWorkout] $e');
      return null;
    }
  }

  Future<void> markCompleted(
    String workoutId,
    String? runId, {
    bool manual = false,
  }) async {
    final isCompleting = runId != null || manual;
    await _c.from('plan_workouts').update({
      'completed_run_id': runId,
      'manually_completed': manual,
      'completed_at': isCompleting ? DateTime.now().toIso8601String() : null,
    }).eq('id', workoutId);
    notifyListeners();
  }

  /// Patch the editable fields on a planned workout. Pass any subset
  /// of [kind], [targetDistanceM], [targetPaceSecPerKm], [notes].
  /// Server-side RLS scopes writes to the plan owner.
  Future<void> updateWorkout(
    String workoutId, {
    String? kind,
    double? targetDistanceM,
    int? targetPaceSecPerKm,
    String? notes,
  }) async {
    final patch = <String, dynamic>{};
    if (kind != null) patch[PlanWorkoutRow.colKind] = kind;
    if (targetDistanceM != null) {
      patch[PlanWorkoutRow.colTargetDistanceM] = targetDistanceM;
    }
    if (targetPaceSecPerKm != null) {
      patch[PlanWorkoutRow.colTargetPaceSecPerKm] = targetPaceSecPerKm;
    }
    if (notes != null) {
      // Match `createPlan` + web's `updatePlanWorkout` — trim and
      // collapse empty-after-trim to null so clearing a workout's
      // notes via the inline editor actually nulls the column.
      patch[PlanWorkoutRow.colNotes] = _trimToNull(notes);
    }
    if (patch.isEmpty) return;
    await _c.from(PlanWorkoutRow.table).update(patch).eq('id', workoutId);
    notifyListeners();
  }

  /// Pure helper: trim a string then collapse empty-after-trim to
  /// null. Mirrors web's `s?.trim() || null` pattern used across
  /// `apps/web/src/lib/data.ts` for every optional text column.
  /// Exposed `@visibleForTesting` so the contract can be pinned in
  /// the parity test suite alongside the other normalisation helpers.
  @visibleForTesting
  static String? trimToNull(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  // Internal alias for the public helper above. Keeps callers inside
  // this file short while the public name stays explicit.
  static String? _trimToNull(String? s) => trimToNull(s);
}

import 'dart:async';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../local_run_store.dart';
import '../main.dart' show pendingStartWorkout;
import '../plan_adherence.dart';
import '../plan_replan.dart';
import '../plan_adaptive_replan.dart';
import '../social_service.dart' show ClubView, RecentRunRow, SocialService;
import '../training.dart';
import '../training_labels.dart';
import '../training_load.dart';
import '../training_service.dart';
import '../backend_timeout.dart';
import '../widgets/error_state.dart';
import '../widgets/current_week_strip.dart';
import '../widgets/plan_calendar.dart';
import '../widgets/top_banner.dart';
import '../widgets/workout_edit_sheet.dart';
import 'workout_detail_screen.dart';

/// Web `isWorkoutCompleted` twin — a planned workout is done when a tracked
/// run is linked OR the runner manually marked it complete.
bool _isWorkoutCompleted(PlanWorkoutRow wo) =>
    wo.completedRunId != null || wo.manuallyCompleted;

/// P2 fitness direction gate (gen v2, decisions §144). OFF by default — the
/// health-derived-load → prescription path stays inert until this dotenv flag
/// is flipped, which is the CISO/Security-Analyst sign-off-gated action
/// (reviews/plan-generator-v2-p2-ciso-note.md; mirrors the web
/// PUBLIC_ADAPTIVE_FITNESS_GATE + the paid-events pre-prod gate, §139). The
/// wiring below is dormant until then.
bool get _adaptiveFitnessGate {
  try {
    final v = dotenv.env['ADAPTIVE_FITNESS_GATE'];
    return v == '1' || v == 'true';
  } catch (_) {
    // dotenv not loaded (e.g. widget tests) → gate stays off.
    return false;
  }
}

/// Filter the viewer's club memberships to ones they can publish a
/// plan-template into — owner or admin. Pure so it's directly
/// unit-tested in `plan_detail_screen_test.dart`.
@visibleForTesting
List<ClubView> adminClubsForPublish(Iterable<ClubView> clubs) {
  return clubs.where((c) => c.isAdmin).toList();
}

class PlanDetailScreen extends StatefulWidget {
  final TrainingService training;
  final String planId;

  /// Optional SocialService injection so tests can drive the publish
  /// flow with a fake. Production callsites pass `null` and the screen
  /// constructs its own SocialService against the global Supabase
  /// client.
  final SocialService? social;

  /// Test-only override for the signed-in user id. Production passes null and
  /// the screen reads it from the global Supabase auth session; widget tests
  /// inject it so the owner-gated adherence / re-plan / duplicate surfaces are
  /// reachable without a live auth session.
  @visibleForTesting
  final String? viewerIdOverride;

  /// Source of full `Run`s (with `metadata.avg_bpm`) for the P2 adaptive-replan
  /// fitness gate. Only consumed when `ADAPTIVE_FITNESS_GATE` is on (gated OFF
  /// by default, pending P2 CISO sign-off); null leaves the P1 behaviour intact.
  /// Threaded from the Fitness hub via PlansScreen; other call sites pass null.
  final LocalRunStore? runStore;

  const PlanDetailScreen({
    super.key,
    required this.training,
    required this.planId,
    this.social,
    this.viewerIdOverride,
    this.runStore,
  });

  @override
  State<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends State<PlanDetailScreen> {
  TrainingPlanRow? _plan;
  List<PlanWeekRow> _weeks = const [];
  Map<String, List<PlanWorkoutRow>> _byWeek = const {};
  bool _loading = true;
  _PlanDetailLoadError? _error;
  bool _publishing = false;
  bool _bulkBusy = false;
  List<RecentRunRow> _recentRuns = const [];
  List<ReplanChange>? _replanPreview;
  // Set only when the current preview came from the adaptive (trend-based)
  // path, so its header can explain the multi-week reason + confidence.
  ({AdaptiveReason reason, AdaptiveConfidence confidence})? _adaptiveInfo;

  // Lazily construct a SocialService against the global Supabase client
  // when none was injected. Tests pass a fake via the constructor.
  late final SocialService _social = widget.social ?? SocialService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.training
          .fetchPlan(widget.planId)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      final byWeek = <String, List<PlanWorkoutRow>>{};
      for (final w in res.workouts) {
        byWeek.putIfAbsent(w.weekId, () => []).add(w);
      }
      setState(() {
        _plan = res.plan;
        _weeks = res.weeks;
        _byWeek = byWeek;
        _loading = false;
      });
      _loadRecentRuns();
    } on TimeoutException catch (e) {
      debugPrint('PlanDetailScreen._load timed out: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _PlanDetailLoadError.timeout;
        });
      }
    } catch (e, s) {
      debugPrint('PlanDetailScreen._load failed: $e\n$s');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _PlanDetailLoadError.generic;
        });
      }
    }
  }

  /// Best-effort fetch of the viewer's recent runs so the adherence banner
  /// + re-plan flow can compare actual weekly mileage to the plan. A failure
  /// leaves the adherence surfaces hidden — the rest of the plan still loads.
  Future<void> _loadRecentRuns() async {
    final plan = _plan;
    if (plan == null || !_isOwner(plan)) return;
    try {
      final runs =
          await _social.fetchRecentRuns(limit: 50).timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() => _recentRuns = runs);
    } catch (_) {
      /* L4 best-effort — leave the adherence surfaces hidden. */
    }
  }

  bool _isOwner(TrainingPlanRow plan) {
    final uid = widget.viewerIdOverride ??
        Supabase.instance.client.auth.currentUser?.id;
    return uid != null && plan.userId == uid;
  }

  int _currentWeekIndex(TrainingPlanRow plan) {
    final dayIndex = DateTime.now().difference(plan.startDate).inDays;
    return dayIndex < 0 ? 0 : (dayIndex ~/ 7).clamp(0, _weeks.length - 1);
  }

  /// Summed actual run mileage dated inside `[weekIndex]`'s 7-day window.
  double _actualMetresForWeek(TrainingPlanRow plan, int weekIndex) {
    final weekStart = plan.startDate.add(Duration(days: weekIndex * 7));
    final weekEnd = weekStart.add(const Duration(days: 7));
    var actual = 0.0;
    for (final r in _recentRuns) {
      final t = r.startedAt.toLocal();
      if (!t.isBefore(weekStart) && t.isBefore(weekEnd)) actual += r.distanceM;
    }
    return actual;
  }

  double _plannedMetresForWeek(PlanWeekRow week) {
    var planned = week.targetVolumeM ?? 0;
    if (!(planned > 0)) {
      planned = 0;
      for (final wo in _byWeek[week.id] ?? const <PlanWorkoutRow>[]) {
        if (wo.kind != 'rest') planned += wo.targetDistanceM ?? 0;
      }
    }
    return planned;
  }

  /// Current-week mileage drift, or null when on-track / not the owner.
  WeeklyDrift? _currentWeekDrift(TrainingPlanRow plan) {
    if (!_isOwner(plan) || _weeks.isEmpty) return null;
    final idx = _currentWeekIndex(plan);
    if (idx >= _weeks.length) return null;
    final week = _weeks[idx];
    final d = weeklyDrift(
        _plannedMetresForWeek(week), _actualMetresForWeek(plan, idx));
    return d.flagged ? d : null;
  }

  /// A long run in the current week that's past + uncompleted → make-up/skip
  /// advice driven by phase + whether a step-back week is imminent.
  MissedWorkoutAdvice? _missedLongRun(TrainingPlanRow plan) {
    if (!_isOwner(plan) || _weeks.isEmpty) return null;
    final idx = _currentWeekIndex(plan);
    if (idx >= _weeks.length) return null;
    final week = _weeks[idx];
    final today = toIsoDate(DateTime.now());
    final missed = (_byWeek[week.id] ?? const <PlanWorkoutRow>[]).where((w) =>
        w.kind == 'long' &&
        toIsoDate(w.scheduledDate).compareTo(today) < 0 &&
        !_isWorkoutCompleted(w));
    if (missed.isEmpty) return null;
    final next = idx + 1 < _weeks.length ? _weeks[idx + 1] : null;
    final nextVol = next?.targetVolumeM ?? 0;
    final curVol = week.targetVolumeM ?? 0;
    final recoveryImminent =
        next != null && nextVol > 0 && curVol > 0 && nextVol < curVol * 0.85;
    return missedWorkoutAdvice(MissedWorkoutInput(
      kind: 'long',
      isTaper: week.phase == 'taper' || week.phase == 'race',
      recoveryWeekImminent: recoveryImminent,
    ));
  }

  List<ReplanWeek> _buildReplanInput(TrainingPlanRow plan) {
    final today = toIsoDate(DateTime.now());
    final todayD = DateTime.now();
    return _weeks.map((w) {
      final weekStart = plan.startDate.add(Duration(days: w.weekIndex * 7));
      final weekEnd = weekStart.add(const Duration(days: 7));
      return ReplanWeek(
        weekIndex: w.weekIndex,
        phase: w.phase,
        plannedMetres: _plannedMetresForWeek(w),
        actualMetres: _actualMetresForWeek(plan, w.weekIndex),
        isComplete: !weekEnd.isAfter(todayD),
        workouts: (_byWeek[w.id] ?? const <PlanWorkoutRow>[])
            .map((x) => ReplanWorkout(
                  id: x.id,
                  scheduledDate: toIsoDate(x.scheduledDate),
                  kind: x.kind,
                  targetDistanceM: x.targetDistanceM,
                  completed: _isWorkoutCompleted(x),
                  isPast: toIsoDate(x.scheduledDate).compareTo(today) < 0,
                ))
            .toList(),
      );
    }).toList();
  }

  void _proposeReplan(TrainingPlanRow plan) {
    if (!_isOwner(plan) || _bulkBusy) return;
    final l10n = AppLocalizations.of(context);
    final res = replanRemaining(
        weeks: _buildReplanInput(plan), today: toIsoDate(DateTime.now()));
    if (res.onTrack || res.changes.isEmpty) {
      setState(() => _replanPreview = null);
      showTopBanner(context, l10n.planDetailReplanOnTrack);
      return;
    }
    setState(() {
      _adaptiveInfo = null;
      _replanPreview = res.changes;
    });
  }

  /// P2 (gated): the runner's latest training-load point as the fitness input.
  /// Null unless `ADAPTIVE_FITNESS_GATE` is on, so the health-derived-load path
  /// is dormant by default. Mirrors web's `adaptiveFitnessInput`: feed FULL
  /// `Run`s (with `metadata.avg_bpm`) from `LocalRunStore` — NOT `_recentRuns`
  /// (`RecentRunRow`, no HR) — to `computeTrainingLoadSeries`, default HR prefs.
  AdaptiveFitness? _adaptiveFitnessInput() {
    if (!_adaptiveFitnessGate) return null;
    final runs = widget.runStore?.runs;
    if (runs == null || runs.isEmpty) return null;
    final series = computeTrainingLoadSeries(runs, endDate: DateTime.now());
    if (series.isEmpty) return null;
    final last = series.last;
    return AdaptiveFitness(tsb: last.tsb, atl: last.atl, ctl: last.ctl);
  }

  /// Adaptive (trend-based) re-plan: only proposes when the last few completed
  /// weeks show a sustained drift, suppressing single-week noise.
  void _proposeAdaptiveReplan(TrainingPlanRow plan) {
    if (!_isOwner(plan) || _bulkBusy) return;
    final l10n = AppLocalizations.of(context);
    final res = adaptiveReplanRemaining(
      weeks: _buildReplanInput(plan),
      today: toIsoDate(DateTime.now()),
      fitness: _adaptiveFitnessInput(),
    );
    if (res.fitnessGated) {
      // P2: an add-volume trend was withheld because the runner is carrying
      // fatigue (TSB < 0) — the adherence and fitness signals disagree.
      setState(() {
        _replanPreview = null;
        _adaptiveInfo = null;
      });
      showTopBanner(context, l10n.planDetailAdaptiveFitnessHeld);
      return;
    }
    if (res.reason == AdaptiveReason.onTrack) {
      setState(() {
        _replanPreview = null;
        _adaptiveInfo = null;
      });
      showTopBanner(context, l10n.planDetailAdaptiveOnTrack);
      return;
    }
    if (res.changes.isEmpty) {
      setState(() {
        _replanPreview = null;
        _adaptiveInfo = null;
      });
      showTopBanner(context, l10n.planDetailAdaptiveNoSafeChange);
      return;
    }
    setState(() {
      _adaptiveInfo = (reason: res.reason, confidence: res.confidence);
      _replanPreview = res.changes;
    });
  }

  String _adaptiveBadgeText(AppLocalizations l10n) {
    final info = _adaptiveInfo!;
    final reason = info.reason == AdaptiveReason.trendUnderfitness
        ? l10n.planDetailAdaptiveReasonUnder
        : l10n.planDetailAdaptiveReasonOver;
    final confidence = info.confidence == AdaptiveConfidence.high
        ? l10n.planDetailAdaptiveConfidenceHigh
        : l10n.planDetailAdaptiveConfidenceMedium;
    return l10n.planDetailAdaptiveBadge(reason, confidence);
  }

  Future<void> _applyReplan() async {
    final changes = _replanPreview;
    if (changes == null || _bulkBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _bulkBusy = true);
    try {
      for (final c in changes) {
        await widget.training
            .updateWorkout(c.workoutId, targetDistanceM: c.toMetres)
            .timeout(kBackendLoadTimeout);
      }
      if (!mounted) return;
      setState(() {
        _replanPreview = null;
        _adaptiveInfo = null;
        _bulkBusy = false;
      });
      showTopBanner(context, l10n.planDetailReplanApplied(changes.length));
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _bulkBusy = false);
      showTopBanner(context, l10n.planDetailBulkFailed(e.toString()));
    }
  }

  Future<void> _duplicateWeek(TrainingPlanRow plan, PlanWeekRow week) async {
    if (_bulkBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _bulkBusy = true);
    try {
      await widget.training
          .duplicatePlanWeek(plan.id, week.weekIndex)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() => _bulkBusy = false);
      showTopBanner(
          context, l10n.planDetailDuplicateWeekDone(week.weekIndex + 1));
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _bulkBusy = false);
      showTopBanner(context, l10n.planDetailBulkFailed(e.toString()));
    }
  }

  Future<void> _publishToClub(TrainingPlanRow plan) async {
    if (_publishing) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _publishing = true);

    List<ClubView> myClubs;
    try {
      myClubs = await _social.fetchMyClubs().timeout(kBackendLoadTimeout);
    } on TimeoutException {
      if (mounted) {
        setState(() => _publishing = false);
        showTopBanner(context, l10n.planDetailPublishLoadClubsTimeout);
      }
      return;
    } catch (e, s) {
      debugPrint('publish: fetchMyClubs failed: $e\n$s');
      if (mounted) {
        setState(() => _publishing = false);
        showTopBanner(context, l10n.planDetailPublishLoadClubsFailed);
      }
      return;
    }
    if (!mounted) return;

    final eligible = adminClubsForPublish(myClubs);
    if (eligible.isEmpty) {
      setState(() => _publishing = false);
      showTopBanner(
        context,
        l10n.planDetailPublishNoClubs,
      );
      return;
    }

    final clubId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PublishClubPicker(clubs: eligible),
    );
    if (clubId == null) {
      if (mounted) setState(() => _publishing = false);
      return;
    }

    try {
      await widget.training
          .publishPlanAsTemplate(planId: plan.id, clubId: clubId)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() => _publishing = false);
      showTopBanner(context, l10n.planDetailPublishSuccess(plan.name));
    } catch (e, s) {
      debugPrint('publishPlanAsTemplate failed: $e\n$s');
      if (!mounted) return;
      setState(() => _publishing = false);
      showTopBanner(context, l10n.planDetailPublishFailed(e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(
            message: _error == _PlanDetailLoadError.timeout
                ? l10n.planDetailTimeoutError
                : l10n.planDetailLoadError,
            onRetry: _load),
      );
    }
    final p = _plan;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.planDetailNotFound)),
      );
    }
    final theme = Theme.of(context);
    final today = toIsoDate(DateTime.now());
    final start = p.startDate;
    final dayIndex = DateTime.now().difference(start).inDays;
    final currentWeek = dayIndex < 0
        ? 0
        : (dayIndex ~/ 7).clamp(0, _weeks.length - 1);
    final todayWorkout = _byWeek.values
        .expand((x) => x)
        .where((w) => toIsoDate(w.scheduledDate) == today && w.kind != 'rest')
        .cast<PlanWorkoutRow?>()
        .firstOrNull;
    final allActive =
        _byWeek.values.expand((x) => x).where((w) => w.kind != 'rest').toList();
    final done = allActive.where((w) => w.completedRunId != null).length;
    final pct =
        allActive.isEmpty ? 0 : (100 * done / allActive.length).round();

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          IconButton(
            icon: _publishing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.publish),
            tooltip: l10n.planDetailPublishTooltip,
            onPressed: _publishing ? null : () => _publishToClub(p),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _heroCard(theme, l10n, p, pct, done, allActive.length),
            if (todayWorkout != null) ...[
              const SizedBox(height: 12),
              _todayCard(theme, l10n, p, todayWorkout),
            ],
            ..._adherenceSection(theme, l10n, p),
            ..._replanSection(theme, l10n, p),
            if (_weeks.isNotEmpty) ...[
              const SizedBox(height: 16),
              CurrentWeekStrip(
                startDate: p.startDate,
                weekIndex: _weeks[currentWeek].weekIndex,
                weekWorkouts: _byWeek[_weeks[currentWeek].id] ?? const [],
                onSelect: _openWorkout,
              ),
            ],
            const SizedBox(height: 16),
            PlanCalendar(
              startDate: p.startDate,
              endDate: p.endDate,
              workouts: _byWeek.values.expand((x) => x).toList(),
              onSelect: _openWorkout,
            ),
            const SizedBox(height: 16),
            for (final w in _weeks)
              _weekCard(theme, l10n, p, w, currentWeek),
          ],
        ),
      ),
    );
  }

  List<Widget> _adherenceSection(
      ThemeData theme, AppLocalizations l10n, TrainingPlanRow p) {
    final drift = _currentWeekDrift(p);
    final missed = _missedLongRun(p);
    if (drift == null && missed == null) return const [];
    final flags = <Widget>[];
    if (drift != null) {
      final pctOff = (drift.driftFraction.abs() * 100).round();
      flags.add(_adherenceFlag(
        theme,
        Icons.insights,
        drift.direction == DriftDirection.over
            ? l10n.planDetailDriftOverFlag(pctOff)
            : l10n.planDetailDriftUnderFlag(pctOff),
      ));
    }
    if (missed != null) {
      final text = missed.reason == MissedWorkoutReason.taper
          ? l10n.planDetailMissedLongTaper
          : missed.reason == MissedWorkoutReason.recoverySoon
              ? l10n.planDetailMissedLongRecovery
              : l10n.planDetailMissedLongMakeUp;
      flags.add(_adherenceFlag(theme, Icons.event_busy, text));
    }
    return [
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < flags.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              flags[i],
            ],
          ],
        ),
      ),
    ];
  }

  Widget _adherenceFlag(ThemeData theme, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }

  List<Widget> _replanSection(
      ThemeData theme, AppLocalizations l10n, TrainingPlanRow p) {
    if (!_isOwner(p) || p.isTemplate) return const [];
    final preview = _replanPreview;
    return [
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _bulkBusy ? null : () => _proposeReplan(p),
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: Text(l10n.planDetailReplan),
            ),
            OutlinedButton.icon(
              onPressed: _bulkBusy ? null : () => _proposeAdaptiveReplan(p),
              icon: const Icon(Icons.trending_up, size: 18),
              label: Text(l10n.planDetailAdaptiveReplan),
            ),
          ],
        ),
      ),
      if (preview != null) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.planDetailReplanPreviewTitle,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              if (_adaptiveInfo != null) ...[
                const SizedBox(height: 4),
                Text(_adaptiveBadgeText(l10n),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    )),
              ],
              const SizedBox(height: 8),
              for (final c in preview)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 92,
                        child: Text(c.scheduledDate,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            )),
                      ),
                      Expanded(
                        child: Text(
                          c.reason == ReplanReason.makeUpLong
                              ? l10n.planDetailReplanMakeUp(
                                  fmtKm(c.fromMetres), fmtKm(c.toMetres))
                              : l10n.planDetailReplanEase(
                                  fmtKm(c.fromMetres), fmtKm(c.toMetres)),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _bulkBusy
                        ? null
                        : () => setState(() {
                              _replanPreview = null;
                              _adaptiveInfo = null;
                            }),
                    child: Text(l10n.planDetailReplanCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _bulkBusy ? null : _applyReplan,
                    child: Text(l10n.planDetailReplanApply),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _heroCard(ThemeData theme, AppLocalizations l10n, TrainingPlanRow p,
      int pct, int done, int total) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    _chip(theme, Icons.flag, fmtKm(p.goalDistanceM, 1)),
                    if (p.goalTimeSeconds != null)
                      _chip(theme, Icons.timer, fmtHms(p.goalTimeSeconds)),
                    if (p.vdot != null)
                      _chip(theme, Icons.trending_up,
                          'VDOT ${formatFixed(p.vdot!, 1, activeLocaleTag)}'),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${toIsoDate(p.startDate)} → ${toIsoDate(p.endDate)} · '
                  '${l10n.planDetailDaysPerWeek(p.daysPerWeek)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _progressRing(theme, pct, done, total),
        ],
      ),
    );
  }

  Widget _chip(ThemeData theme, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: theme.colorScheme.outline),
        const SizedBox(width: 3),
        Text(text, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _progressRing(ThemeData theme, int pct, int done, int total) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
              value: pct / 100,
              strokeWidth: 5,
              color: theme.colorScheme.primary,
              backgroundColor: theme.dividerColor,
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$pct%',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text('$done/$total',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _todayCard(ThemeData theme, AppLocalizations l10n, TrainingPlanRow p,
      PlanWorkoutRow wo) {
    final kind = workoutKindFromDb(wo.kind);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openWorkout(wo),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer,
              theme.colorScheme.surfaceContainerHighest,
            ],
          ),
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.planDetailToday,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 4),
            Text(workoutKindLabel(l10n, kind),
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Row(
              children: [
                if (wo.targetDistanceM != null) ...[
                  Text(fmtKm(wo.targetDistanceM)),
                  const SizedBox(width: 8),
                ],
                if (wo.targetPaceSecPerKm != null)
                  Text('@ ${fmtPace(wo.targetPaceSecPerKm)}',
                      style: TextStyle(color: theme.colorScheme.outline)),
                if (wo.completedRunId != null) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.check_circle,
                      color: theme.colorScheme.primary, size: 18),
                  const SizedBox(width: 3),
                  Text(l10n.planDetailCompleted,
                      style: TextStyle(color: theme.colorScheme.primary)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekCard(ThemeData theme, AppLocalizations l10n, TrainingPlanRow p,
      PlanWeekRow w, int currentWeek) {
    final phase = planPhaseFromDb(w.phase);
    final today = toIsoDate(DateTime.now());
    final workouts = _byWeek[w.id] ?? const [];
    final isCurrent = w.weekIndex == currentWeek;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: isCurrent
              ? theme.colorScheme.primary
              : theme.dividerColor,
          width: isCurrent ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l10n.planDetailWeek(w.weekIndex + 1),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text(planPhaseLabel(l10n, phase).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                  )),
              const Spacer(),
              Text(fmtKm(w.targetVolumeM, 0),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  )),
              if (_isOwner(p) && !p.isTemplate)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    splashRadius: 18,
                    visualDensity: VisualDensity.compact,
                    tooltip: l10n.planDetailDuplicateWeek,
                    icon: Icon(Icons.content_copy,
                        color: theme.colorScheme.outline),
                    onPressed: _bulkBusy ? null : () => _duplicateWeek(p, w),
                  ),
                ),
            ],
          ),
          if (w.notes != null && w.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(w.notes!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  )),
            ),
          const SizedBox(height: 8),
          for (final wo in workouts)
            _workoutRow(theme, l10n, p, wo, today),
        ],
      ),
    );
  }

  Widget _workoutRow(ThemeData theme, AppLocalizations l10n, TrainingPlanRow p,
      PlanWorkoutRow wo, String today) {
    final kind = workoutKindFromDb(wo.kind);
    final isRest = kind == WorkoutKind.rest;
    final isToday = toIsoDate(wo.scheduledDate) == today;
    final dow = formatDow(
        wo.scheduledDate, localeToTag(Localizations.localeOf(context)));
    return InkWell(
      onTap: isRest ? null : () => _openWorkout(wo),
      onLongPress: () => _editWorkout(wo),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: isToday
              ? theme.colorScheme.primaryContainer.withOpacity(0.5)
              : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            SizedBox(width: 34, child: Text(dow,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ))),
            Expanded(
              child: Text(
                workoutKindLabel(l10n, kind),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isRest ? theme.colorScheme.outline : null,
                  fontWeight: isRest ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            ),
            if (wo.targetDistanceM != null && !isRest) ...[
              Text(fmtKm(wo.targetDistanceM, 1),
                  style: theme.textTheme.bodySmall),
              const SizedBox(width: 6),
            ],
            if (wo.completedRunId != null)
              Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 16),
            // Inline edit affordance — discoverable button alongside the
            // long-press gesture. Hidden on rest days; nothing to edit.
            if (!isRest)
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  splashRadius: 18,
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.planDetailEditTooltip,
                  icon: Icon(Icons.edit_outlined,
                      color: theme.colorScheme.outline),
                  onPressed: () => _editWorkout(wo),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editWorkout(PlanWorkoutRow wo) async {
    final ok = await showWorkoutEditSheet(
      context,
      workout: wo,
      training: widget.training,
    );
    if (ok) await _load();
  }

  /// Push WorkoutDetailScreen, then either kick the structured runner
  /// (when the user tapped Start) or just refresh the plan. The runner
  /// lives on the Run tab — popping back to root and signalling
  /// `pendingStartWorkout` lets HomeScreen switch tabs and RunScreen
  /// load the workout.
  Future<void> _openWorkout(PlanWorkoutRow wo) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute<PlanWorkoutRow?>(
        builder: (_) => WorkoutDetailScreen(
          training: widget.training,
          planId: widget.planId,
          workoutId: wo.id,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      pendingStartWorkout.value = result;
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    _load();
  }
}

enum _PlanDetailLoadError { timeout, generic }

/// Modal that lists the viewer's admin-able clubs and pops the picked
/// club id (or `null` on cancel). Pure presentation — the parent does
/// the fetch + commit so cancel doesn't leave a half-state.
class PublishClubPicker extends StatelessWidget {
  final List<ClubView> clubs;
  const PublishClubPicker({super.key, required this.clubs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.planDetailPublishPickerTitle,
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              l10n.planDetailPublishPickerBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: clubs.length,
                itemBuilder: (_, i) {
                  final c = clubs[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.group),
                    title: Text(c.row.name),
                    subtitle: Text(
                      '${c.row.locationLabel ?? c.row.slug} · '
                      '${l10n.planDetailPublishPickerMembers(c.memberCount)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, c.row.id),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.planDetailPublishCancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

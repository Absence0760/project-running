import 'dart:async';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../main.dart' show pendingStartWorkout;
import '../social_service.dart' show ClubView, SocialService;
import '../training.dart';
import '../training_service.dart';
import '../backend_timeout.dart';
import '../widgets/error_state.dart';
import '../widgets/plan_calendar.dart';
import '../widgets/top_banner.dart';
import '../widgets/workout_edit_sheet.dart';
import 'workout_detail_screen.dart';

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

  const PlanDetailScreen({
    super.key,
    required this.training,
    required this.planId,
    this.social,
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
                          'VDOT ${p.vdot!.toStringAsFixed(1)}'),
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
            Text(workoutKindLabel(kind),
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
              Text(planPhaseLabel(phase).toUpperCase(),
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
                workoutKindLabel(kind),
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

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/date_format.dart';
import '../l10n/locale_support.dart';
import '../preferences.dart';
import '../widgets/top_banner.dart';

/// Coach run-review surface — mobile mirror of web
/// `/coaching/athletes/[id]` (`.../athletes/[id]/+page.svelte`): a linked
/// athlete's recent runs (public + private, gated by the active-coach RLS
/// policy) + active-plan compliance + the assign-a-plan control. Reached from
/// `coaching_screen.dart`. Reads/writes through [ApiClient]'s coaching methods.
class CoachingAthleteScreen extends StatefulWidget {
  final ApiClient api;
  final Preferences preferences;
  final String athleteId;
  final String? displayName;
  final DateTime? acceptedAt;

  const CoachingAthleteScreen({
    super.key,
    required this.api,
    required this.preferences,
    required this.athleteId,
    this.displayName,
    this.acceptedAt,
  });

  @override
  State<CoachingAthleteScreen> createState() => _CoachingAthleteScreenState();
}

class _CoachingAthleteScreenState extends State<CoachingAthleteScreen> {
  bool _loading = true;
  List<AthleteRunSummary> _runs = const [];
  AthletePlanOverview? _overview;
  List<TrainingPlanRow> _myPlans = const [];

  String? _selectedPlanId;
  DateTime _startDate = DateTime.now();
  bool _assigning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.api.fetchAthleteRuns(widget.athleteId, limit: 20),
        widget.api.fetchAthletePlanOverview(widget.athleteId),
        widget.api.fetchMyPlans(),
      ]);
      if (!mounted) return;
      setState(() {
        _runs = results[0] as List<AthleteRunSummary>;
        _overview = results[1] as AthletePlanOverview?;
        _myPlans = results[2] as List<TrainingPlanRow>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showTopBanner(
          context,
          AppLocalizations.of(context).coachingAthleteLoadError(
              friendlyError(AppLocalizations.of(context), e)));
    }
  }

  bool get _assignedByMe {
    final o = _overview;
    return o != null &&
        o.plan.assignedByCoachId != null &&
        o.plan.assignedByCoachId == widget.api.userId;
  }

  Future<void> _assignPlan() async {
    final l10n = AppLocalizations.of(context);
    final planId = _selectedPlanId;
    if (planId == null || _assigning) return;
    setState(() => _assigning = true);
    try {
      await widget.api.assignPlanToAthlete(
        sourcePlanId: planId,
        athleteId: widget.athleteId,
        startDate: _startDate,
      );
      final overview = await widget.api.fetchAthletePlanOverview(widget.athleteId);
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _selectedPlanId = null;
      });
      showTopBanner(
        context,
        l10n.coachingAthleteAssignSuccess(
            widget.displayName ?? l10n.coachingAthleteRunnerFallback),
      );
    } catch (e) {
      // assignPlanToAthlete rethrows the RPC's RAISE text as an Exception
      // (e.g. the athlete already has an active plan). Surface it rather than
      // swallow — strip the leading "Exception: " the toString() adds.
      if (!mounted) return;
      showTopBanner(context, _cleanMessage(e));
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  static String _cleanMessage(Object e) {
    final s = '$e';
    return s.startsWith('Exception: ') ? s.substring('Exception: '.length) : s;
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.displayName ?? l10n.coachingAthleteAthleteFallback),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _header(l10n),
                  const SizedBox(height: 16),
                  _planCard(l10n),
                  const SizedBox(height: 16),
                  _runsCard(l10n),
                ],
              ),
            ),
    );
  }

  Widget _header(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final since = widget.acceptedAt != null
        ? formatDateMed(widget.acceptedAt!, activeLocaleTag)
        : '—';
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          child: Text(_initial(widget.displayName),
              style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.displayName ?? l10n.coachingAthleteRunnerFallback,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(l10n.coachingAthleteCoachingSince(since),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _planCard(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.coachingAthletePlanCompliance,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (_overview == null)
              _noPlanBody(l10n)
            else
              _activePlanBody(_overview!, l10n),
          ],
        ),
      ),
    );
  }

  Widget _noPlanBody(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final name = widget.displayName ?? l10n.coachingAthleteRunnerFallback;
    if (_myPlans.isEmpty) {
      return Text(l10n.coachingAthleteAssignNoPlans,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.coachingAthleteNoActivePlan,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
        const Divider(height: 24),
        Text(l10n.coachingAthleteAssignTitle,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(l10n.coachingAthleteAssignHint(name),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedPlanId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.coachingAthleteAssignSelectLabel,
            border: const OutlineInputBorder(),
          ),
          hint: Text(l10n.coachingAthleteAssignSelectPlaceholder),
          items: [
            for (final p in _myPlans)
              DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: _assigning
              ? null
              : (v) => setState(() => _selectedPlanId = v),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _assigning ? null : _pickStartDate,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.coachingAthleteAssignStartLabel,
              border: const OutlineInputBorder(),
            ),
            child: Text(formatDateMed(_startDate, activeLocaleTag)),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: (_selectedPlanId == null || _assigning) ? null : _assignPlan,
          child: Text(_assigning
              ? l10n.coachingAthleteAssigning
              : l10n.coachingAthleteAssignButton),
        ),
      ],
    );
  }

  Widget _activePlanBody(AthletePlanOverview o, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final todayISO = _todayISO();
    final real = o.workouts.where((w) => w.kind != 'rest').toList();
    final done = real
        .where((w) => w.manuallyCompleted == true || w.completedRunId != null)
        .length;
    final missed = real
        .where((w) =>
            !(w.manuallyCompleted == true || w.completedRunId != null) &&
            _isoOf(w.scheduledDate).compareTo(todayISO) < 0)
        .length;
    final pct = o.completionPct;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(o.plan.name,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (_assignedByMe) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(l10n.coachingAthleteAssignedByYou,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    )),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: '$pct% ',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: l10n.coachingAthleteComplete),
            TextSpan(
                text:
                    ' · ${l10n.coachingAthleteDoneCount(done, real.length)}'),
            if (missed > 0)
              TextSpan(
                text: ' · ${l10n.coachingAthleteMissedCount(missed)}',
                style: TextStyle(color: theme.colorScheme.error),
              ),
          ]),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (final w in _focusWorkouts(o)) _workoutRow(w, l10n),
        if (!_assignedByMe) ...[
          const SizedBox(height: 8),
          Text(l10n.coachingAthleteCannotAssignHasPlan,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ],
      ],
    );
  }

  /// A window around today: recent misses + what's coming up, rather than the
  /// whole plan. Mirrors web's focusWorkouts (4 before the pivot, 6 after).
  List<PlanWorkoutRow> _focusWorkouts(AthletePlanOverview o) {
    final sorted = o.workouts.where((w) => w.kind != 'rest').toList()
      ..sort((a, b) => _isoOf(a.scheduledDate).compareTo(_isoOf(b.scheduledDate)));
    final todayISO = _todayISO();
    var idx = sorted.indexWhere((w) => _isoOf(w.scheduledDate).compareTo(todayISO) >= 0);
    final pivot = idx == -1 ? sorted.length : idx;
    final from = (pivot - 4) < 0 ? 0 : pivot - 4;
    final to = (pivot + 6) > sorted.length ? sorted.length : pivot + 6;
    return sorted.sublist(from, to);
  }

  Widget _workoutRow(PlanWorkoutRow w, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final status = _workoutStatus(w);
    final (label, color) = switch (status) {
      'done' => (l10n.coachingAthleteStatusDone, theme.colorScheme.primary),
      'missed' => (l10n.coachingAthleteStatusMissed, theme.colorScheme.error),
      _ => (
          l10n.coachingAthleteStatusUpcoming,
          theme.colorScheme.onSurfaceVariant
        ),
    };
    final unit = widget.preferences.unit;
    final target = <String>[];
    if (w.targetDistanceM != null && w.targetDistanceM! > 0) {
      target.add(UnitFormat.distance(w.targetDistanceM!, unit));
    }
    if (w.targetPaceSecPerKm != null && w.targetPaceSecPerKm! > 0) {
      target.add(
          '${UnitFormat.pace(w.targetPaceSecPerKm!.toDouble(), unit)} ${UnitFormat.paceLabel(unit)}');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(formatDateShort(w.scheduledDate, activeLocaleTag),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_workoutLabel(w),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (target.isNotEmpty)
                  Text(target.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _runsCard(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.coachingAthleteRecentRuns,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_runs.isEmpty)
              Text(l10n.coachingAthleteNoRunsYet,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ))
            else
              for (final r in _runs) _runRow(r, unit, l10n),
          ],
        ),
      ),
    );
  }

  Widget _runRow(AthleteRunSummary r, DistanceUnit unit, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final paceSecPerKm = (r.distanceM > 0 && r.durationS > 0)
        ? r.durationS / (r.distanceM / 1000)
        : null;
    final pace = paceSecPerKm == null
        ? '—'
        : '${UnitFormat.pace(paceSecPerKm, unit)} ${UnitFormat.paceLabel(unit)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(formatDateShort(r.startedAt, activeLocaleTag),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ),
          SizedBox(
            width: 64,
            child: Text(_activityLabel(r.activityType),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(
                '${UnitFormat.distance(r.distanceM, unit)} · ${_formatDuration(r.durationS)} · $pace',
                style: theme.textTheme.bodySmall),
          ),
          if (!r.isPublic)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(l10n.coachingAthletePrivate,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
              ),
            ),
        ],
      ),
    );
  }

  String _workoutStatus(PlanWorkoutRow w) {
    if (w.kind == 'rest') return 'rest';
    if (w.manuallyCompleted == true || w.completedRunId != null) return 'done';
    return _isoOf(w.scheduledDate).compareTo(_todayISO()) < 0
        ? 'missed'
        : 'upcoming';
  }

  static String _workoutLabel(PlanWorkoutRow w) {
    final k = w.kind.replaceAll('_', ' ');
    return k.isEmpty ? 'Run' : '${k[0].toUpperCase()}${k.substring(1)}';
  }

  static String _activityLabel(String a) {
    final s = a.isEmpty ? 'run' : a;
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }

  static String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Local-tz today as a YYYY-MM-DD string, matching web's date comparison.
  static String _todayISO() => _isoOf(DateTime.now());

  static String _isoOf(DateTime dt) {
    final d = dt.isUtc ? dt.toLocal() : dt;
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _initial(String? name) {
    final n = name?.trim() ?? '';
    return n.isEmpty ? '?' : n.substring(0, 1).toUpperCase();
  }
}

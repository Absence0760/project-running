import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../backend_timeout.dart';
import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../social_service.dart' show ClubView, SocialService;
import '../starter_plans.dart';
import '../training.dart';
import '../training_labels.dart';
import '../training_service.dart';
import '../widgets/top_banner.dart';
import 'plan_detail_screen.dart';

/// A club plan template paired with the owning club's display name, for the
/// "Start from a club template" picker. Mirrors the web `/plans/new`
/// template-picker option shape.
class _TemplateOption {
  final TrainingPlanRow template;
  final String clubName;
  const _TemplateOption(this.template, this.clubName);
}

/// Wizard: goal race + goal time + recent 5K + days/week. Live preview of
/// paces + week outline updates as inputs change. Mirrors the web page.
class PlanNewScreen extends StatefulWidget {
  final TrainingService training;

  /// Optional SocialService injection so tests can drive the club-template
  /// picker with a fake. Production callsites pass `null` and the screen
  /// constructs its own against the global Supabase client.
  final SocialService? social;

  /// Preselect the goal + beginner toggle on mount (the onboarding
  /// "create my training plan" nudge keys these off the runner's
  /// primary_goal). Null → the normal defaults.
  final GoalEvent? initialGoal;
  final bool initialBeginnerWalkRun;

  const PlanNewScreen({
    super.key,
    required this.training,
    this.social,
    this.initialGoal,
    this.initialBeginnerWalkRun = false,
  });

  @override
  State<PlanNewScreen> createState() => _PlanNewScreenState();
}

class _PlanNewScreenState extends State<PlanNewScreen> {
  final _nameCtrl = TextEditingController();
  // Persistent controllers for the numeric fields — creating them inside
  // build() (as the first pass did) resets the cursor every character and
  // makes the boxes nearly unusable. State-owned + disposed below.
  final _goalHoursCtrl = TextEditingController();
  final _goalMinutesCtrl = TextEditingController();
  final _goalSecondsCtrl = TextEditingController();
  final _recent5kMinCtrl = TextEditingController();
  final _recent5kSecCtrl = TextEditingController();
  final _weekOverrideCtrl = TextEditingController();

  GoalEvent _goal = GoalEvent.distanceHalf;
  DateTime _startDate = _nextSunday();
  int _daysPerWeek = 4;

  int? _goalHours, _goalMinutes, _goalSeconds;
  int? _recent5kMin, _recent5kSec;
  // Returning runners type an old PR; the engine would treat it as current
  // fitness and prescribe paces that are too fast (injury risk — comeback
  // persona #24). The time only anchors paces once confirmed current;
  // otherwise paces stay on the conservative goal-based fallback.
  bool _recent5kConfirmed = false;
  // Beginner / return-to-run: generate a C25K-style walk-run plan (persona #22).
  bool _beginnerWalkRun = false;
  int? _weekOverride;
  bool _busy = false;
  String? _error;
  // Persona-hunt Round 3 finding Woman #3. Pulled lazily on mount
  // and threaded into `generatePlan` so the pace bands reflect the
  // gender-aware calibration when present. Null → unmodified
  // (male-curve) paces, matching pre-fix behaviour.
  TrainingGender _viewerGender;
  // Persona-hunt finding Older #30. Pulled lazily on mount and threaded
  // into `generatePlan` so 50+ runners get the masters recovery
  // calibration (72h hard-day spacing + 3-week cycle). Null → standard
  // schedule.
  int? _viewerAge;

  late final SocialService _social = widget.social ?? SocialService();
  List<_TemplateOption> _templates = const [];
  bool _cloning = false;
  bool _creatingStarter = false;

  static DateTime _nextSunday() {
    var d = DateTime.now().add(const Duration(days: 7));
    while (d.weekday != DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return DateTime(d.year, d.month, d.day);
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialGoal != null) _goal = widget.initialGoal!;
    _beginnerWalkRun = widget.initialBeginnerWalkRun;
    widget.training.fetchViewerGender().then((g) {
      if (!mounted) return;
      setState(() => _viewerGender = g);
    });
    widget.training.fetchViewerAge().then((a) {
      if (!mounted) return;
      setState(() => _viewerAge = a);
    });
    _loadTemplates();
  }

  /// Best-effort fetch of every plan template the viewer can adopt across
  /// their clubs (mirrors web `/plans/new`'s onMount). A failure leaves the
  /// picker hidden — generating from scratch is always available.
  Future<void> _loadTemplates() async {
    try {
      final clubs =
          await _social.fetchMyClubs().timeout(kBackendLoadTimeout);
      final options = <_TemplateOption>[];
      for (final ClubView c in clubs) {
        final list = await widget.training
            .fetchClubTemplates(c.row.id)
            .timeout(kBackendLoadTimeout);
        for (final t in list) {
          options.add(_TemplateOption(t, c.row.name));
        }
      }
      if (!mounted) return;
      setState(() => _templates = options);
    } catch (_) {
      /* L4 best-effort — leave the picker hidden on any failure. */
    }
  }

  /// Creating any plan auto-completes the runner's existing active plan
  /// (the one-active-per-user partial unique index — see
  /// `TrainingService.createPlan` / `clonePlanTemplate`). That retirement is
  /// silent and feels irreversible — weeks of a current build get marked
  /// `completed` with no warning. Mirror web's `PlanEditor` gate: before any
  /// create path runs, if there's an active plan, confirm the swap and show
  /// its name. Returns true to proceed, false to keep the current plan. A
  /// best-effort overview fetch that fails (offline) proceeds rather than
  /// blocking creation — the backend still enforces the invariant.
  Future<bool> _confirmReplaceActivePlan() async {
    String? activeName;
    try {
      final overview = await widget.training
          .fetchActiveOverview()
          .timeout(kBackendLoadTimeout);
      if (overview == null) return true;
      activeName = overview.plan.name;
    } catch (_) {
      return true;
    }
    if (!mounted) return false;
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.planNewReplaceActiveTitle),
        content: Text(activeName != null
            ? l10n.planNewReplaceActiveNamed(activeName)
            : l10n.planNewReplaceActiveUnnamed),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.planNewReplaceActiveKeep),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.planNewReplaceActiveConfirm),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _pickTemplate() async {
    if (_templates.isEmpty || _cloning) return;
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<_TemplateOption>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TemplatePicker(options: _templates),
    );
    if (picked == null || !mounted) return;
    if (!await _confirmReplaceActivePlan() || !mounted) return;
    setState(() => _cloning = true);
    try {
      final newId = await widget.training
          .clonePlanTemplate(
            templateId: picked.template.id,
            startDate: _startDate,
          )
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              PlanDetailScreen(training: widget.training, planId: newId),
        ),
      );
    } catch (e) {
      debugPrint('Template clone failed: $e');
      if (mounted) {
        setState(() => _cloning = false);
        showTopBanner(context, l10n.planNewTemplateCloneFailed);
      }
    }
  }

  String _starterName(AppLocalizations l10n, String id) {
    switch (id) {
      case 'c25k':
        return l10n.planNewStarterC25k;
      case 'half_12wk':
        return l10n.planNewStarterHalf12;
      case 'marathon_16wk':
        return l10n.planNewStarterMarathon16;
      default:
        return id;
    }
  }

  Future<void> _pickStarter() async {
    if (_creatingStarter) return;
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<StarterPlan>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _StarterPicker(
        plans: starterPlans,
        nameFor: (id) => _starterName(l10n, id),
      ),
    );
    if (picked == null || !mounted) return;
    final generated = instantiateStarter(picked.id, _startDate, age: _viewerAge);
    if (generated == null) return;
    if (!await _confirmReplaceActivePlan() || !mounted) return;
    setState(() => _creatingStarter = true);
    try {
      final plan = await widget.training
          .createPlan(
            name: _starterName(l10n, picked.id),
            goalEvent: picked.goalEvent,
            goalDistanceM: generated.goalDistanceM,
            startDate: _startDate,
            daysPerWeek: picked.daysPerWeek,
            generated: generated,
          )
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              PlanDetailScreen(training: widget.training, planId: plan.id),
        ),
      );
    } catch (e) {
      debugPrint('Starter plan create failed: $e');
      if (mounted) {
        setState(() => _creatingStarter = false);
        showTopBanner(context, l10n.planNewStarterCreateFailed);
      }
    }
  }

  int? get _goalTimeSec {
    if (_goalHours == null && _goalMinutes == null && _goalSeconds == null) {
      return null;
    }
    return (_goalHours ?? 0) * 3600 +
        (_goalMinutes ?? 0) * 60 +
        (_goalSeconds ?? 0);
  }

  int? get _recent5kTotal {
    if (_recent5kMin == null && _recent5kSec == null) return null;
    return (_recent5kMin ?? 0) * 60 + (_recent5kSec ?? 0);
  }

  // Only anchor paces on the entered time once the runner confirms it's
  // current; an entered-but-unconfirmed time is treated as absent.
  int? get _recent5kApplied => _recent5kConfirmed ? _recent5kTotal : null;
  bool get _recent5kNeedsConfirm => _recent5kTotal != null && !_recent5kConfirmed;

  GeneratedPlan? _preview() {
    try {
      return generatePlan(GeneratePlanInput(
        goalEvent: _goal,
        startDate: _startDate,
        daysPerWeek: _daysPerWeek,
        goalTimeSec: _goalTimeSec,
        recent5kSec: _recent5kApplied,
        weeks: _weekOverride,
        gender: _viewerGender,
        age: _viewerAge,
        beginnerWalkRun: _beginnerWalkRun,
      ));
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _busy) return;
    final preview = _preview();
    if (preview == null) return;
    if (!await _confirmReplaceActivePlan() || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plan = await widget.training.createPlan(
        name: name,
        goalEvent: _goal,
        goalDistanceM: preview.goalDistanceM,
        goalTimeSec: _goalTimeSec,
        recent5kSec: _recent5kApplied,
        startDate: _startDate,
        daysPerWeek: _daysPerWeek,
        generated: preview,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              PlanDetailScreen(training: widget.training, planId: plan.id),
        ),
      );
    } catch (e) {
      debugPrint('PlanNewScreen._submit failed: $e');
      if (mounted) {
        setState(() => _error = friendlyError(AppLocalizations.of(context), e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _goalHoursCtrl.dispose();
    _goalMinutesCtrl.dispose();
    _goalSecondsCtrl.dispose();
    _recent5kMinCtrl.dispose();
    _recent5kSecCtrl.dispose();
    _weekOverrideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final preview = _preview();
    // See plans_screen.dart — Samsung's 3-button nav bar isn't auto-padded
    // on screens without a bottom nav. Include it in the ListView bottom
    // padding so the Cancel/Create row sits above the system buttons.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.planNewTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 32 + bottomInset),
        children: [
          _starterCard(theme, l10n),
          const SizedBox(height: 20),
          if (_templates.isNotEmpty) ...[
            _templateCard(theme, l10n),
            const SizedBox(height: 20),
          ],
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: l10n.planNewNameLabel,
              hintText: l10n.planNewNameHint,
            ),
            maxLength: 80,
            // Re-evaluate the Create button's enabled state as the name is
            // typed — without this the button (which gates on a non-empty
            // name) only un-disables on the next unrelated rebuild.
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<GoalEvent>(
            initialValue: _goal,
            decoration: InputDecoration(labelText: l10n.planNewGoalRace),
            items: const [
              GoalEvent.distance5k,
              GoalEvent.distance10k,
              GoalEvent.distanceHalf,
              GoalEvent.distanceFull,
            ]
                .map((g) =>
                    DropdownMenuItem(value: g, child: Text(goalEventLabel(g))))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _goal = v);
            },
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today),
            title: Text(l10n.planNewStartDate),
            subtitle: Text(toIsoDate(_startDate)),
            trailing: const Icon(Icons.edit),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _startDate,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _startDate = picked);
            },
          ),
          DropdownButtonFormField<int>(
            initialValue: _daysPerWeek,
            decoration: InputDecoration(labelText: l10n.planNewDaysPerWeek),
            items: [3, 4, 5, 6, 7]
                .map((n) => DropdownMenuItem(
                    value: n, child: Text(l10n.planNewDaysOption(n))))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _daysPerWeek = v);
            },
          ),
          const SizedBox(height: 12),
          _SectionLabel(l10n.planNewGoalTimeSection),
          Row(
            children: [
              Expanded(
                child: _numField(
                  _goalHoursCtrl, 'h',
                  (v) => setState(() => _goalHours = v), 0, 9),
              ),
              const Text(' : '),
              Expanded(
                child: _numField(
                  _goalMinutesCtrl, 'm',
                  (v) => setState(() => _goalMinutes = v), 0, 59),
              ),
              const Text(' : '),
              Expanded(
                child: _numField(
                  _goalSecondsCtrl, 's',
                  (v) => setState(() => _goalSeconds = v), 0, 59),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _beginnerWalkRun,
            onChanged: (v) => setState(() => _beginnerWalkRun = v ?? false),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l10n.planNewBeginnerTitle),
            subtitle: Text(l10n.planNewBeginnerSubtitle),
          ),
          const SizedBox(height: 12),
          _SectionLabel(l10n.planNewRecent5kSection),
          Row(
            children: [
              Expanded(
                child: _numField(
                  _recent5kMinCtrl, 'min',
                  (v) => setState(() => _recent5kMin = v), 0, 59),
              ),
              const Text(' : '),
              Expanded(
                child: _numField(
                  _recent5kSecCtrl, 'sec',
                  (v) => setState(() => _recent5kSec = v), 0, 59),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.planNewRecent5kHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          if (_recent5kTotal != null)
            CheckboxListTile(
              value: _recent5kConfirmed,
              onChanged: (v) => setState(() => _recent5kConfirmed = v ?? false),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.planNewRecent5kConfirm),
            ),
          if (_recent5kNeedsConfirm)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.planNewRecent5kWarning,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 16),
          _numField(
            _weekOverrideCtrl,
            l10n.planNewOverrideHint,
            (v) => setState(() => _weekOverride = v),
            4,
            24,
            labelText: l10n.planNewOverrideLabel(defaultPlanWeeks(_goal)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (preview != null) _buildPreview(theme, l10n, preview),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.planNewCancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed:
                      (_nameCtrl.text.trim().isEmpty || _busy || preview == null)
                          ? null
                          : _submit,
                  child: Text(
                      _busy ? l10n.planNewCreating : l10n.planNewCreate),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _starterCard(ThemeData theme, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.4),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fitness_center,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(l10n.planNewStarterTitle,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(l10n.planNewStarterSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _creatingStarter ? null : _pickStarter,
            icon: _creatingStarter
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add, size: 18),
            label: Text(_creatingStarter
                ? l10n.planNewStarterCreating
                : l10n.planNewStarterButton),
          ),
        ],
      ),
    );
  }

  Widget _templateCard(ThemeData theme, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.4),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.library_books,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(l10n.planNewTemplateTitle,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(l10n.planNewTemplateSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _cloning ? null : _pickTemplate,
            icon: _cloning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add, size: 18),
            label: Text(_cloning
                ? l10n.planNewTemplateCloning
                : l10n.planNewTemplateButton),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(
      ThemeData theme, AppLocalizations l10n, GeneratedPlan p) {
    // A beginner walk-run plan is duration-based intervals, not pace-based —
    // the VDOT badge + the five Daniels pace zones are jargon the runner who
    // ticked "New to running?" can't parse. Detect it from the plan itself
    // (every session is a walk_run workout) and hide the pace panel for it.
    final isWalkRun = p.weeks
        .any((w) => w.workouts.any((wo) => wo.kind == WorkoutKind.walkRun));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.planNewPreviewTitle,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (!isWalkRun) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                _pacePill(theme, l10n.planNewPaceEasy, p.paces.easy),
                _pacePill(theme, l10n.planNewPaceMarathon, p.paces.marathon),
                _pacePill(theme, l10n.planNewPaceTempo, p.paces.tempo),
                _pacePill(theme, l10n.planNewPaceInterval, p.paces.interval),
                _pacePill(theme, l10n.planNewPaceRep, p.paces.repetition),
              ],
            ),
            if (p.pacesAreFallback) ...[
              const SizedBox(height: 6),
              Text(
                l10n.planNewPacesFallback,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (p.vdot != null) ...[
              const SizedBox(height: 8),
              Text(l10n.planNewVdot(formatFixed(p.vdot!, 1, activeLocaleTag)),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ],
          const SizedBox(height: 10),
          Text(l10n.planNewWeekOutline,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                letterSpacing: 0.6,
              )),
          const SizedBox(height: 4),
          for (final w in p.weeks.take(6)) _previewRow(theme, l10n, w),
          if (p.weeks.length > 6)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.planNewMoreWeeks(p.weeks.length - 6),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pacePill(ThemeData theme, String label, int sec) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              )),
          const SizedBox(width: 4),
          Text(fmtPace(sec),
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _previewRow(
      ThemeData theme, AppLocalizations l10n, GeneratedWeek w) {
    final active = w.workouts.where((x) => x.kind != WorkoutKind.rest).length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text('#${w.weekIndex + 1}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary)),
          ),
          SizedBox(
            width: 70,
            child: Text(planPhaseLabel(l10n, w.phase),
                style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(fmtKm(w.targetVolumeM, 0),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ),
          Text(l10n.planNewSessions(active),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              )),
        ],
      ),
    );
  }

  Widget _numField(
    TextEditingController controller,
    String hint,
    void Function(int?) onChanged,
    int min,
    int max, {
    String? labelText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hint,
        isDense: true,
      ),
      onChanged: (s) {
        if (s.isEmpty) {
          onChanged(null);
          return;
        }
        final n = int.tryParse(s);
        if (n != null && n >= min && n <= max) onChanged(n);
      },
    );
  }
}

/// Modal that lists the built-in starter plans and pops the chosen
/// [StarterPlan] (or `null` on cancel). Pure presentation — the parent
/// instantiates + creates so cancel doesn't leave a half-state.
class _StarterPicker extends StatelessWidget {
  final List<StarterPlan> plans;
  final String Function(String id) nameFor;
  const _StarterPicker({required this.plans, required this.nameFor});

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
            Text(l10n.planNewStarterPickerTitle,
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: plans.length,
                itemBuilder: (_, i) {
                  final p = plans[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_note),
                    title: Text(nameFor(p.id)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, p),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.planNewStarterPickerCancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal that lists the viewer's adoptable club templates and pops the
/// chosen option (or `null` on cancel). Pure presentation — the parent
/// does the clone so cancel doesn't leave a half-state.
class _TemplatePicker extends StatelessWidget {
  final List<_TemplateOption> options;
  const _TemplatePicker({required this.options});

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
            Text(l10n.planNewTemplatePickerTitle,
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final o = options[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_note),
                    title: Text(o.template.name),
                    subtitle: Text(o.clubName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, o),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.planNewTemplatePickerCancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
          letterSpacing: 0.7,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

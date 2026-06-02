import 'package:flutter/material.dart';

import '../goals.dart';
import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';
import '../settings_sync.dart';

/// Open the goal editor as a full-screen modal dialog. Pass an
/// existing goal to edit it in-place; omit for a new goal.
///
/// Was previously a `showModalBottomSheet` — the user surface was
/// inconsistent with the rest of the dashboard's drill-ins
/// (PeriodSummaryScreen for Week / Month opens as a full-screen
/// page). Field report: "Note the Mileage modal looks less wide
/// (thinner) than the other modals on the dashboard. … I like the
/// week modal compared to the goal modal." Promoting goal-edit to
/// a fullscreen dialog matches the period-summary shape and reads
/// as a "drill-in" the same way.
///
/// The function name is kept (`showGoalEditorSheet`) so call sites
/// don't churn; the surface inside is unchanged.
///
/// Resolves to a short screen-reader status message (`Goal saved` /
/// `Goal deleted`) when the sheet committed a change, or null when the
/// user backed out — the dashboard pushes it through
/// `SemanticsService.announce` so a TalkBack user hears the result
/// (WCAG 4.1.3).
Future<String?> showGoalEditorSheet(
  BuildContext context, {
  required Preferences preferences,
  SettingsSyncService? settingsSync,
  RunGoal? existing,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        appBar: AppBar(
          title: Text(existing == null
              ? AppLocalizations.of(ctx).goalEditorTitleNew
              : AppLocalizations.of(ctx).goalEditorTitleEdit),
        ),
        body: SafeArea(
          child: _GoalEditorSheet(
            preferences: preferences,
            settingsSync: settingsSync,
            existing: existing,
          ),
        ),
      ),
    ),
  );
}

class _GoalEditorSheet extends StatefulWidget {
  final Preferences preferences;
  final SettingsSyncService? settingsSync;
  final RunGoal? existing;
  const _GoalEditorSheet({
    required this.preferences,
    required this.settingsSync,
    this.existing,
  });

  @override
  State<_GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends State<_GoalEditorSheet> {
  static const _metresPerMile = 1609.344;

  late GoalPeriod _period;
  late final TextEditingController _titleCtl;
  late final TextEditingController _distanceCtl;
  late final TextEditingController _timeCtl;
  late final TextEditingController _paceCtl;
  late final TextEditingController _countCtl;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _period = existing?.period ?? GoalPeriod.week;
    final unit = widget.preferences.unit;

    _titleCtl = TextEditingController(text: existing?.title ?? '');
    _distanceCtl = TextEditingController(
      text: existing?.distanceMetres != null
          ? _distanceToInput(existing!.distanceMetres!, unit)
          : '',
    );
    _timeCtl = TextEditingController(
      text: existing?.timeSeconds != null
          ? (existing!.timeSeconds! / 60).round().toString()
          : '',
    );
    _paceCtl = TextEditingController(
      text: existing?.avgPaceSecPerKm != null
          ? _paceToInput(existing!.avgPaceSecPerKm!, unit)
          : '',
    );
    _countCtl = TextEditingController(
      text: existing?.runCount != null
          ? existing!.runCount!.toInt().toString()
          : '',
    );
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _distanceCtl.dispose();
    _timeCtl.dispose();
    _paceCtl.dispose();
    _countCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final mq = MediaQuery.of(context);
    final unit = widget.preferences.unit;
    final isEditing = widget.existing != null;

    // Bottom spacing must clear whichever system UI is currently showing:
    // the soft keyboard (viewInsets.bottom) when focused, or the Samsung
    // gesture/nav bar (viewPadding.bottom) when not. They never overlap
    // in practice — the keyboard replaces the nav bar when up — so max()
    // picks whichever is active.
    final bottomInset = mq.viewInsets.bottom > 0
        ? mq.viewInsets.bottom
        : mq.viewPadding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title now comes from the host Scaffold's AppBar (set
            // by showGoalEditorSheet's fullscreenDialog wrapper).
            // Drop the inline title so the heading isn't duplicated.
            _sectionLabel(theme, l10n.goalEditorNameLabel),
            const SizedBox(height: 8),
            TextField(
              controller: _titleCtl,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: const OutlineInputBorder(),
                hintText: l10n.goalEditorNameHint,
              ),
            ),
            const SizedBox(height: 24),
            _sectionLabel(theme, l10n.goalEditorPeriod),
            const SizedBox(height: 8),
            SegmentedButton<GoalPeriod>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: GoalPeriod.week,
                  label: Text(l10n.goalEditorThisWeek),
                ),
                ButtonSegment(
                  value: GoalPeriod.month,
                  label: Text(l10n.goalEditorThisMonth),
                ),
              ],
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.first),
            ),
            const SizedBox(height: 24),
            _sectionLabel(theme, l10n.goalEditorTargets),
            const SizedBox(height: 4),
            Text(
              l10n.goalEditorTargetsHelp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            _targetField(
              label: l10n.goalEditorTargetDistance,
              icon: Icons.straighten,
              controller: _distanceCtl,
              hint: '-',
              suffix: UnitFormat.distanceLabel(unit),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            _targetField(
              label: l10n.goalEditorTargetTime,
              icon: Icons.timer_outlined,
              controller: _timeCtl,
              hint: '-',
              suffix: l10n.goalEditorSuffixMin,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            _targetField(
              label: l10n.goalEditorTargetPace,
              icon: Icons.speed,
              controller: _paceCtl,
              hint: '-',
              suffix: UnitFormat.paceLabel(unit),
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 12),
            _targetField(
              label: l10n.goalEditorTargetRuns,
              icon: Icons.directions_run,
              controller: _countCtl,
              hint: '-',
              suffix: l10n.goalEditorSuffixRuns,
              keyboardType: TextInputType.number,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                if (isEditing)
                  TextButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.goalEditorDelete),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.goalEditorCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _save,
                  child: Text(l10n.goalEditorSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _targetField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required String hint,
    required String suffix,
    required TextInputType keyboardType,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.outline),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: const OutlineInputBorder(),
              hintText: hint,
              suffixText: suffix,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final unit = widget.preferences.unit;

    // Distance
    double? distance;
    final distanceText = _distanceCtl.text.trim();
    if (distanceText.isNotEmpty) {
      final n = double.tryParse(distanceText);
      if (n == null || n <= 0) {
        setState(() => _error = l10n.goalEditorErrDistance);
        return;
      }
      distance = unit == DistanceUnit.mi ? n * _metresPerMile : n * 1000;
    }

    // Time
    double? time;
    final timeText = _timeCtl.text.trim();
    if (timeText.isNotEmpty) {
      final n = double.tryParse(timeText);
      if (n == null || n <= 0) {
        setState(() => _error = l10n.goalEditorErrTime);
        return;
      }
      time = n * 60;
    }

    // Pace
    double? pace;
    final paceText = _paceCtl.text.trim();
    if (paceText.isNotEmpty) {
      final secPerUnit = _parsePace(paceText);
      if (secPerUnit == null || secPerUnit <= 0) {
        setState(() => _error = l10n.goalEditorErrPace);
        return;
      }
      pace = unit == DistanceUnit.mi
          ? secPerUnit / (_metresPerMile / 1000)
          : secPerUnit.toDouble();
    }

    // Run count
    double? count;
    final countText = _countCtl.text.trim();
    if (countText.isNotEmpty) {
      final n = int.tryParse(countText);
      if (n == null || n <= 0) {
        setState(() => _error = l10n.goalEditorErrRuns);
        return;
      }
      count = n.toDouble();
    }

    if (distance == null && time == null && pace == null && count == null) {
      setState(() => _error = l10n.goalEditorErrNoTarget);
      return;
    }

    final trimmedTitle = _titleCtl.text.trim();
    final goal = RunGoal(
      id: widget.existing?.id ?? newGoalId(),
      period: _period,
      title: trimmedTitle.isEmpty ? null : trimmedTitle,
      distanceMetres: distance,
      timeSeconds: time,
      avgPaceSecPerKm: pace,
      runCount: count,
    );
    await widget.preferences.upsertGoal(goal);
    // Mirror the *single* weekly distance goal into the universal bag
    // so it roams to web/iOS. Other shapes stay client-only.
    await widget.settingsSync?.pushWeeklyDistanceGoal();
    if (mounted) Navigator.pop(context, l10n.goalEditorSavedAnnounce);
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final id = widget.existing?.id;
    if (id == null) return;
    await widget.preferences.removeGoal(id);
    await widget.settingsSync?.pushWeeklyDistanceGoal();
    if (mounted) Navigator.pop(context, l10n.goalEditorDeletedAnnounce);
  }

  int? _parsePace(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final m = int.tryParse(parts[0]);
    final sec = int.tryParse(parts[1]);
    if (m == null || sec == null) return null;
    if (sec < 0 || sec >= 60 || m < 0) return null;
    return m * 60 + sec;
  }

  static String _distanceToInput(double metres, DistanceUnit unit) {
    if (unit == DistanceUnit.mi) {
      return (metres / _metresPerMile).toStringAsFixed(1);
    }
    return (metres / 1000).toStringAsFixed(1);
  }

  static String _paceToInput(double secPerKm, DistanceUnit unit) {
    final secPerUnit =
        unit == DistanceUnit.mi ? secPerKm * (_metresPerMile / 1000) : secPerKm;
    final m = secPerUnit ~/ 60;
    final s = (secPerUnit % 60).round();
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

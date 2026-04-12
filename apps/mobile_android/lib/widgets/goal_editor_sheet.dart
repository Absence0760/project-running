import 'package:flutter/material.dart';

import '../goals.dart';
import '../preferences.dart';

/// Open the goal editor as a modal bottom sheet. Pass an existing goal to
/// edit it in-place; omit for a new goal.
Future<void> showGoalEditorSheet(
  BuildContext context, {
  required Preferences preferences,
  RunGoal? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _GoalEditorSheet(
      preferences: preferences,
      existing: existing,
    ),
  );
}

class _GoalEditorSheet extends StatefulWidget {
  final Preferences preferences;
  final RunGoal? existing;
  const _GoalEditorSheet({
    required this.preferences,
    this.existing,
  });

  @override
  State<_GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends State<_GoalEditorSheet> {
  static const _metresPerMile = 1609.344;

  late GoalPeriod _period;
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
    _distanceCtl.dispose();
    _timeCtl.dispose();
    _paceCtl.dispose();
    _countCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEditing ? 'Edit goal' : 'New goal',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            _sectionLabel(theme, 'Period'),
            const SizedBox(height: 8),
            SegmentedButton<GoalPeriod>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: GoalPeriod.week,
                  label: Text('This week'),
                ),
                ButtonSegment(
                  value: GoalPeriod.month,
                  label: Text('This month'),
                ),
              ],
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.first),
            ),
            const SizedBox(height: 24),
            _sectionLabel(theme, 'Targets'),
            const SizedBox(height: 4),
            Text(
              'Set any combination. Blank fields are ignored.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            _targetField(
              label: 'Distance',
              icon: Icons.straighten,
              controller: _distanceCtl,
              hint: '-',
              suffix: UnitFormat.distanceLabel(unit),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            _targetField(
              label: 'Time',
              icon: Icons.timer_outlined,
              controller: _timeCtl,
              hint: '-',
              suffix: 'min',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            _targetField(
              label: 'Avg pace',
              icon: Icons.speed,
              controller: _paceCtl,
              hint: '-',
              suffix: UnitFormat.paceLabel(unit),
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 12),
            _targetField(
              label: 'Runs',
              icon: Icons.directions_run,
              controller: _countCtl,
              hint: '-',
              suffix: 'runs',
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
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Save'),
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
    final unit = widget.preferences.unit;

    // Distance
    double? distance;
    final distanceText = _distanceCtl.text.trim();
    if (distanceText.isNotEmpty) {
      final n = double.tryParse(distanceText);
      if (n == null || n <= 0) {
        setState(() => _error = 'Distance: enter a positive number');
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
        setState(() => _error = 'Time: enter a positive number of minutes');
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
        setState(() => _error = 'Pace: use mm:ss (e.g. 5:00)');
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
        setState(() => _error = 'Runs: enter a positive whole number');
        return;
      }
      count = n.toDouble();
    }

    if (distance == null && time == null && pace == null && count == null) {
      setState(() => _error = 'Set at least one target');
      return;
    }

    final goal = RunGoal(
      id: widget.existing?.id ?? newGoalId(),
      period: _period,
      distanceMetres: distance,
      timeSeconds: time,
      avgPaceSecPerKm: pace,
      runCount: count,
    );
    await widget.preferences.upsertGoal(goal);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    await widget.preferences.removeGoal(id);
    if (mounted) Navigator.pop(context);
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

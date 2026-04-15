import 'package:flutter/material.dart';

import '../training.dart';
import '../training_service.dart';
import 'plan_detail_screen.dart';

/// Wizard: goal race + goal time + recent 5K + days/week. Live preview of
/// paces + week outline updates as inputs change. Mirrors the web page.
class PlanNewScreen extends StatefulWidget {
  final TrainingService training;
  const PlanNewScreen({super.key, required this.training});

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
  int? _weekOverride;
  bool _busy = false;
  String? _error;

  static DateTime _nextSunday() {
    var d = DateTime.now().add(const Duration(days: 7));
    while (d.weekday != DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return DateTime(d.year, d.month, d.day);
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

  GeneratedPlan? _preview() {
    try {
      return generatePlan(GeneratePlanInput(
        goalEvent: _goal,
        startDate: _startDate,
        daysPerWeek: _daysPerWeek,
        goalTimeSec: _goalTimeSec,
        recent5kSec: _recent5kTotal,
        weeks: _weekOverride,
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
        recent5kSec: _recent5kTotal,
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
      if (mounted) setState(() => _error = e.toString());
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
    final preview = _preview();
    // See plans_screen.dart — Samsung's 3-button nav bar isn't auto-padded
    // on screens without a bottom nav. Include it in the ListView bottom
    // padding so the Cancel/Create row sits above the system buttons.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: const Text('New plan')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 32 + bottomInset),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Plan name',
              hintText: 'e.g. Autumn half marathon',
            ),
            maxLength: 80,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<GoalEvent>(
            initialValue: _goal,
            decoration: const InputDecoration(labelText: 'Goal race'),
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
            title: const Text('Start date'),
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
            decoration: const InputDecoration(labelText: 'Days per week'),
            items: [3, 4, 5, 6, 7]
                .map((n) =>
                    DropdownMenuItem(value: n, child: Text('$n days')))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _daysPerWeek = v);
            },
          ),
          const SizedBox(height: 12),
          _SectionLabel('Goal time · optional'),
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
          _SectionLabel('Recent 5K time · optional'),
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
            'Anchor paces on a real result instead of the goal. Uses Riegel equivalence to project to the goal distance.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          _numField(
            _weekOverrideCtrl,
            'Override total weeks',
            (v) => setState(() => _weekOverride = v),
            4,
            24,
            labelText: 'Override weeks (${defaultPlanWeeks(_goal)} default)',
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
          if (preview != null) _buildPreview(theme, preview),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed:
                      (_nameCtrl.text.trim().isEmpty || _busy || preview == null)
                          ? null
                          : _submit,
                  child: Text(_busy ? 'Creating…' : 'Create plan'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(ThemeData theme, GeneratedPlan p) {
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
          Text('Preview',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _pacePill(theme, 'Easy', p.paces.easy),
              _pacePill(theme, 'Marathon', p.paces.marathon),
              _pacePill(theme, 'Tempo', p.paces.tempo),
              _pacePill(theme, 'Interval', p.paces.interval),
              _pacePill(theme, 'Rep', p.paces.repetition),
            ],
          ),
          if (p.vdot != null) ...[
            const SizedBox(height: 8),
            Text('Daniels VDOT: ${p.vdot!.toStringAsFixed(1)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
          const SizedBox(height: 10),
          Text('Week outline',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                letterSpacing: 0.6,
              )),
          const SizedBox(height: 4),
          for (final w in p.weeks.take(6)) _previewRow(theme, w),
          if (p.weeks.length > 6)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+ ${p.weeks.length - 6} more weeks',
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

  Widget _previewRow(ThemeData theme, GeneratedWeek w) {
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
            child: Text(planPhaseLabel(w.phase),
                style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(fmtKm(w.targetVolumeM, 0),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ),
          Text('$active sessions',
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

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../training.dart';
import '../training_service.dart';

/// Modal bottom sheet for inline editing of a planned workout's kind,
/// target distance, target pace, and notes. The caller is responsible
/// for refreshing the plan view after the sheet returns.
Future<bool> showWorkoutEditSheet(
  BuildContext context, {
  required PlanWorkoutRow workout,
  required TrainingService training,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _WorkoutEditSheet(
      workout: workout,
      training: training,
    ),
  );
  return ok == true;
}

class _WorkoutEditSheet extends StatefulWidget {
  final PlanWorkoutRow workout;
  final TrainingService training;
  const _WorkoutEditSheet({
    required this.workout,
    required this.training,
  });

  @override
  State<_WorkoutEditSheet> createState() => _WorkoutEditSheetState();
}

class _WorkoutEditSheetState extends State<_WorkoutEditSheet> {
  late WorkoutKind _kind;
  late final TextEditingController _distanceCtl;
  late final TextEditingController _paceCtl;
  late final TextEditingController _notesCtl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final w = widget.workout;
    _kind = workoutKindFromDb(w.kind);
    _distanceCtl = TextEditingController(
      text: w.targetDistanceM == null
          ? ''
          : (w.targetDistanceM! / 1000).toStringAsFixed(1),
    );
    _paceCtl = TextEditingController(
      text: w.targetPaceSecPerKm == null
          ? ''
          : _fmtPaceMmSs(w.targetPaceSecPerKm!),
    );
    _notesCtl = TextEditingController(text: w.notes ?? '');
  }

  @override
  void dispose() {
    _distanceCtl.dispose();
    _paceCtl.dispose();
    _notesCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + mq.viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Edit workout', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<WorkoutKind>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Kind'),
            items: [
              for (final k in WorkoutKind.values)
                DropdownMenuItem(value: k, child: Text(workoutKindLabel(k))),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _kind = v);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _distanceCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Target distance (km)',
              hintText: 'e.g. 8.0',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _paceCtl,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: 'Target pace (mm:ss /km)',
              hintText: 'e.g. 5:30',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final distanceText = _distanceCtl.text.trim();
    double? distanceM;
    if (distanceText.isNotEmpty) {
      final km = double.tryParse(distanceText);
      if (km == null || km <= 0) {
        setState(() => _error = 'Enter a positive distance in km');
        return;
      }
      distanceM = km * 1000;
    }

    final paceText = _paceCtl.text.trim();
    int? paceSecPerKm;
    if (paceText.isNotEmpty) {
      paceSecPerKm = _parsePaceMmSs(paceText);
      if (paceSecPerKm == null) {
        setState(() => _error = "Pace must look like 5:30");
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.training.updateWorkout(
        widget.workout.id,
        kind: workoutKindDbValue(_kind),
        targetDistanceM: distanceM,
        targetPaceSecPerKm: paceSecPerKm,
        notes: _notesCtl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Save failed: $e';
        });
      }
    }
  }

  static String _fmtPaceMmSs(int secPerKm) {
    final m = secPerKm ~/ 60;
    final s = secPerKm % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static int? _parsePaceMmSs(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final m = int.tryParse(parts[0]);
    final sec = int.tryParse(parts[1]);
    if (m == null || sec == null || sec < 0 || sec >= 60 || m < 0) return null;
    final total = m * 60 + sec;
    if (total <= 0) return null;
    return total;
  }
}

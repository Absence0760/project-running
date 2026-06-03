import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../training.dart';
import '../training_labels.dart';
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
          : _paceToEditText(w.targetPaceSecPerKm!),
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
    final l10n = AppLocalizations.of(context);
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + mq.viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.workoutEditTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<WorkoutKind>(
            initialValue: _kind,
            decoration: InputDecoration(labelText: l10n.workoutEditKindLabel),
            items: [
              for (final k in WorkoutKind.values)
                DropdownMenuItem(value: k, child: Text(workoutKindLabel(l10n, k))),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _kind = v);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _distanceCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.workoutEditDistanceLabel,
              hintText: l10n.workoutEditDistanceHint,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _paceCtl,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              labelText: l10n.workoutEditPaceLabel,
              hintText: l10n.workoutEditPaceHint,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtl,
            maxLines: 2,
            decoration: InputDecoration(labelText: l10n.workoutEditNotesLabel),
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
                  child: Text(l10n.workoutEditCancel),
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
                      : Text(l10n.workoutEditSave),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final distanceText = _distanceCtl.text.trim();
    double? distanceM;
    if (distanceText.isNotEmpty) {
      final km = double.tryParse(distanceText);
      if (km == null || km <= 0) {
        setState(() => _error = l10n.workoutEditErrDistance);
        return;
      }
      distanceM = km * 1000;
    }

    final paceText = _paceCtl.text.trim();
    int? paceSecPerKm;
    if (paceText.isNotEmpty) {
      paceSecPerKm = _parsePaceMmSs(paceText);
      if (paceSecPerKm == null) {
        setState(() => _error = l10n.workoutEditErrPace);
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
          _error = l10n.workoutEditSaveError('$e');
        });
      }
    }
  }

  static String _paceToEditText(int secPerKm) {
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

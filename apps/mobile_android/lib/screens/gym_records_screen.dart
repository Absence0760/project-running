import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../exercise_records.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../local_gym_store.dart';
import '../preferences.dart';
import 'gym_exercise_screen.dart';
import 'gym_screen.dart' show gymSetHistory;

/// Per-exercise personal-record roll-up — mobile mirror of web `/gym/records`.
/// Reads the signed-in user's gym set history from [LocalGymStore] and drives
/// the [exerciseRecords] roll-up (est-1RM / heaviest / top-volume + last
/// performed + session count), each row drilling into [GymExerciseScreen].
class GymRecordsScreen extends StatefulWidget {
  final ApiClient? api;
  final LocalGymStore store;

  const GymRecordsScreen({super.key, required this.api, required this.store});

  @override
  State<GymRecordsScreen> createState() => _GymRecordsScreenState();
}

class _GymRecordsScreenState extends State<GymRecordsScreen> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChange);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChange);
    super.dispose();
  }

  void _onStoreChange() {
    if (mounted) setState(() {});
  }

  void _open(ExerciseRecord r) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GymExerciseScreen(
          api: widget.api,
          store: widget.store,
          exerciseName: r.exerciseName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final records = exerciseRecords(gymSetHistory(widget.store.workouts));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.gymRecordsTitle)),
      body: records.isEmpty
          ? _empty(theme, l10n)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: records.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      l10n.gymRecordsSubtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  );
                }
                return _card(records[i - 1], theme, l10n);
              },
            ),
    );
  }

  Widget _card(ExerciseRecord r, ThemeData theme, AppLocalizations l10n) {
    final tag = localeToTag(Localizations.localeOf(context));
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _open(r),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      r.exerciseName,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.chevron_right, color: theme.colorScheme.outline),
                ],
              ),
              const SizedBox(height: 8),
              if (r.bestEst1RmKg != null)
                _metric(
                  l10n.gymPrE1rm,
                  WeightFormat.format(r.bestEst1RmKg, activeWeightUnit),
                  theme,
                  primary: true,
                ),
              _metric(l10n.gymPrWeight, _heaviestLine(r), theme),
              if (r.bestVolumeKg != null)
                _metric(
                  l10n.gymPrVolume,
                  WeightFormat.format(r.bestVolumeKg, activeWeightUnit),
                  theme,
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  if (r.lastPerformedAt.isNotEmpty)
                    Text(
                      l10n.gymRecordsLastDone(
                        _formatLast(r.lastPerformedAt, tag),
                      ),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  Text(
                    l10n.gymRecordsSessions(r.sessionCount),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value, ThemeData theme,
      {bool primary = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              letterSpacing: 0.8,
            ),
          ),
          Text(
            value,
            style: primary
                ? theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.primary)
                : theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _heaviestLine(ExerciseRecord r) {
    final w = WeightFormat.format(r.heaviestWeightKg, activeWeightUnit);
    return r.heaviestWeightReps != null
        ? '$w × ${_numStr(r.heaviestWeightReps!)}'
        : w;
  }

  String _formatLast(String iso, String tag) {
    final dt = DateTime.tryParse(iso);
    return dt == null ? iso : formatDateMed(dt.toLocal(), tag);
  }

  Widget _empty(ThemeData theme, AppLocalizations l10n) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.emoji_events_outlined,
                  size: 56, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                l10n.gymRecordsEmpty,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  static String _numStr(num v) {
    if (v is int) return v.toString();
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }
}

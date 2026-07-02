import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../exercise_history.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../local_gym_store.dart';
import '../preferences.dart';
import 'gym_detail_screen.dart';
import 'gym_screen.dart' show gymSetHistory;

/// Per-exercise progression over time — mobile mirror of web `/gym/exercise`.
/// Headline latest est-1RM + delta vs the first session, then a most-recent
/// -first session list with an e1RM-relative bar and a new-e1RM PR badge.
class GymExerciseScreen extends StatefulWidget {
  final ApiClient? api;
  final LocalGymStore store;
  final String exerciseName;

  const GymExerciseScreen({
    super.key,
    required this.api,
    required this.store,
    required this.exerciseName,
  });

  @override
  State<GymExerciseScreen> createState() => _GymExerciseScreenState();
}

class _GymExerciseScreenState extends State<GymExerciseScreen> {
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

  void _openWorkout(String workoutId) {
    if (widget.store.byId(workoutId) == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GymDetailScreen(
          api: widget.api,
          store: widget.store,
          workoutId: workoutId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final progress =
        exerciseProgress(gymSetHistory(widget.store.workouts), widget.exerciseName);
    return Scaffold(
      appBar: AppBar(
        title: Text(progress?.exerciseName ?? widget.exerciseName),
      ),
      body: progress == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  l10n.gymExerciseEmpty,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _body(progress, theme, l10n),
    );
  }

  Widget _body(ExerciseProgress p, ThemeData theme, AppLocalizations l10n) {
    final tag = localeToTag(Localizations.localeOf(context));
    // Most-recent first (sessions come oldest-first).
    final reversed = p.sessions.reversed.toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _headline(p, theme, l10n),
        const SizedBox(height: 16),
        for (final s in reversed) _sessionRow(s, p, tag, theme, l10n),
      ],
    );
  }

  Widget _headline(ExerciseProgress p, ThemeData theme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            if (p.latestEst1RmKg != null) ...[
              Text(
                WeightFormat.format(p.latestEst1RmKg, activeWeightUnit),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                l10n.gymPrE1rm.toUpperCase(),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline, letterSpacing: 0.8),
              ),
            ],
            if (p.est1RmDeltaKg != null) _deltaChip(p.est1RmDeltaKg!, theme, l10n),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.gymRecordsSessions(p.sessions.length),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }

  Widget _deltaChip(double delta, ThemeData theme, AppLocalizations l10n) {
    final mag = WeightFormat.format(delta.abs(), activeWeightUnit);
    final String text;
    final IconData icon;
    final Color color;
    if (delta == 0) {
      text = l10n.gymSinceFirstFlat;
      icon = Icons.trending_flat;
      color = theme.colorScheme.outline;
    } else if (delta > 0) {
      text = l10n.gymSinceFirstUp(mag);
      icon = Icons.trending_up;
      color = Color.alphaBlend(
        Colors.green.withValues(alpha: 0.5),
        theme.colorScheme.onSurface,
      );
    } else {
      text = l10n.gymSinceFirstDown(mag);
      icon = Icons.trending_down;
      color = theme.colorScheme.outline;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 2),
        Text(
          text,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _sessionRow(
    ExerciseSession s,
    ExerciseProgress p,
    String tag,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final dt = DateTime.tryParse(s.startedAt);
    final dateText = dt == null ? s.startedAt : formatDateMed(dt.toLocal(), tag);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openWorkout(s.workoutId),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          dateText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (s.isWeightPr) _prBadge(theme, l10n.gymPrWeight),
                        if (s.isEst1RmPr) _prBadge(theme, l10n.gymPrE1rm),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _topSetLine(s),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              if (s.bestEst1RmKg != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _barFraction(s, p),
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 16,
                  children: [
                    Text(
                      '${WeightFormat.format(s.bestEst1RmKg, activeWeightUnit)} ${l10n.gymPrE1rm}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (s.volumeKg > 0)
                      Text(
                        '${WeightFormat.format(s.volumeKg, activeWeightUnit)} ${l10n.gymVolumeLabel}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _prBadge(ThemeData theme, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      );

  /// Bar fraction: each session's e1rm relative to the best, so the visual
  /// climbs toward 1 at the PR session. Floors at 0.04 like the web bar.
  double _barFraction(ExerciseSession s, ExerciseProgress p) {
    final best = p.bestEst1RmKg;
    if (best == null || best <= 0 || s.bestEst1RmKg == null) return 0;
    final pct = (s.bestEst1RmKg! / best * 100).round();
    final clamped = pct < 4 ? 4 : pct;
    return clamped / 100;
  }

  String _topSetLine(ExerciseSession s) {
    final w = WeightFormat.format(s.topWeightKg, activeWeightUnit);
    return s.topWeightReps != null ? '$w × ${_numStr(s.topWeightReps!)}' : w;
  }

  static String _numStr(num v) {
    if (v is int) return v.toString();
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }
}

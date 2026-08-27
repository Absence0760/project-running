import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../challenge_progress.dart';
import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';

/// The metric's own name, localised. The vocabulary is `challenges_metric_ck`'s
/// (migrations 20270209_001 + 20270302_001) and lives here beside
/// [challengeValueLabel] so the list, the detail screen and the create form
/// cannot name the same metric three ways.
String challengeMetricLabel(AppLocalizations l10n, String metric) {
  switch (metric) {
    case 'duration':
      return l10n.challengesMetricDuration;
    case 'vert':
      return l10n.challengesMetricVert;
    case 'activity_count':
      return l10n.challengesMetricActivityCount;
    case 'streak_days':
      return l10n.challengesMetricStreak;
    case 'distance':
    default:
      return l10n.challengesMetricDistance;
  }
}

/// One challenge value in the metric's own units, localised + unit-formatted.
String challengeValueLabel(AppLocalizations l10n, String metric, num value) {
  switch (metric) {
    case 'duration':
      final total = value.round();
      final h = total ~/ 3600;
      final m = (total % 3600) ~/ 60;
      return h > 0 ? '${h}h ${m}m' : '${m}m';
    case 'vert':
      return formatElevationForPref(value.toDouble());
    case 'streak_days':
      return l10n.challengesUnitDays(value.round());
    case 'activity_count':
      return l10n.challengesUnitActivities(value.round());
    case 'distance':
    default:
      return formatDistanceForPref(value.toDouble());
  }
}

/// The caller's progress towards a challenge goal: the value (against the goal
/// when there is one), the bar, and the on-pace verdict. Twin of web's
/// `ChallengeProgressBar.svelte`, shared by the challenges list and the
/// challenge detail screen exactly as web shares the component.
///
/// [value] must be a value the caller is entitled to claim — `myProgressView`
/// decides that. A row whose value is unknown renders its own copy instead of
/// this widget; drawing an empty bar would state a zero nobody measured.
class ChallengeProgressBar extends StatelessWidget {
  final String metric;
  final num value;
  final num? goal;
  final DateTime? startsAt;
  final DateTime? endsAt;
  const ChallengeProgressBar({
    super.key,
    required this.metric,
    required this.value,
    required this.goal,
    this.startsAt,
    this.endsAt,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final frac = progressFraction(value, goal);
    final complete = isComplete(value, goal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                goal == null
                    ? challengeValueLabel(l10n, metric, value)
                    : l10n.challengesGoalProgress(
                        challengeValueLabel(l10n, metric, value),
                        challengeValueLabel(l10n, metric, goal!),
                      ),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (complete)
              Text(l10n.challengesProgressComplete,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600)),
          ],
        ),
        if (frac != null) ...[
          const SizedBox(height: 6),
          ProgressBar(value: frac),
        ],
        if (!complete) _paceHint(context, l10n),
      ],
    );
  }

  Widget _paceHint(BuildContext context, AppLocalizations l10n) {
    final start = startsAt;
    final end = endsAt;
    if (goal == null || start == null || end == null) {
      return const SizedBox.shrink();
    }
    final p = challengePace(
      value,
      goal,
      start.millisecondsSinceEpoch,
      end.millisecondsSinceEpoch,
      DateTime.now().millisecondsSinceEpoch,
    );
    if (p.status != ChallengePaceStatus.active || p.verdict == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (p.verdict!) {
      PaceVerdict.ahead => (l10n.challengesPaceAhead, scheme.tertiary),
      PaceVerdict.behind => (l10n.challengesPaceBehind, scheme.error),
      PaceVerdict.onTrack => (l10n.challengesPaceOnTrack, scheme.primary),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Flexible(
            child: Text(label,
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ),
          if (p.verdict == PaceVerdict.behind && p.requiredPerDay != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.challengesPaceNeedPerDay(
                  challengeValueLabel(l10n, metric, p.requiredPerDay!),
                ),
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

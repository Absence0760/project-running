import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../fitness.dart';
import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';
import '../race_predictor.dart';
import '../training.dart'
    show PredictionConfidence, PredictionQuality, PredictionReason;

/// Dashboard "Race-time predictor" card — the 5K / 10K / Half / Marathon
/// ladder predicted from the runner's recent qualifying efforts, each rung
/// carrying a confidence chip. Returns nothing when the same qualifying-run
/// gate the Fitness card uses yields no usable anchor.
///
/// Mirrors the web `RacePredictorCard.svelte` — it feeds `predictRaceLadder`
/// (the Dart twin of `race_predictor.ts`) the qualifying efforts mapped down
/// to the minimal shape, so the same ladder appears on every surface.
class RacePredictorCard extends StatelessWidget {
  final List<Run> runs;
  final DateTime now;
  const RacePredictorCard({super.key, required this.runs, required this.now});

  @override
  Widget build(BuildContext context) {
    final efforts = [
      for (final r in qualifyingRuns(runs))
        EffortForPrediction(
          distanceM: r.distanceMetres,
          durationS: r.duration.inSeconds,
          ageDays: (now.difference(r.startedAt).inMilliseconds / 86400000)
              .clamp(0, double.infinity),
        ),
    ];
    final prediction = predictRaceLadder(efforts);
    if (prediction == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.racePredictorTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.racePredictorAnchoredOn(
                    formatDistanceForPref(prediction.anchor.distanceM),
                    _clock(prediction.anchor.durationS.toDouble()),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _HeadCell(l10n.racePredictorColDistance),
                    ),
                    Expanded(
                      flex: 3,
                      child: _HeadCell(l10n.racePredictorColTime),
                    ),
                    Expanded(
                      flex: 3,
                      child: _HeadCell(l10n.racePredictorColPace),
                    ),
                    Expanded(
                      flex: 3,
                      child: _HeadCell(l10n.racePredictorColConfidence),
                    ),
                  ],
                ),
                for (final rung in prediction.rungs)
                  _LadderRow(rung: rung, l10n: l10n),
                const SizedBox(height: 12),
                Text(
                  l10n.racePredictorFootnote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// MM:SS or H:MM:SS, mirroring web `fmtSplitTime`.
String _clock(double seconds) {
  final total = seconds.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

class _HeadCell extends StatelessWidget {
  final String label;
  const _HeadCell(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.outline,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _LadderRow extends StatelessWidget {
  final LadderPrediction rung;
  final AppLocalizations l10n;
  const _LadderRow({required this.rung, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              formatDistanceForPref(rung.distanceM),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _clock(rung.predictedSec),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              formatPaceForPref(rung.paceSecPerKm),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _ConfidenceChip(quality: rung.quality, l10n: l10n),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  final PredictionQuality quality;
  final AppLocalizations l10n;
  const _ConfidenceChip({required this.quality, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    late final Color bg;
    late final Color fg;
    late final String label;
    switch (quality.confidence) {
      case PredictionConfidence.high:
        bg = dark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5);
        fg = dark ? const Color(0xFFA7F3D0) : const Color(0xFF047857);
        label = l10n.racePredictorConfidenceHigh;
        break;
      case PredictionConfidence.moderate:
        bg = dark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7);
        fg = dark ? const Color(0xFFFDE68A) : const Color(0xFFB45309);
        label = l10n.racePredictorConfidenceModerate;
        break;
      case PredictionConfidence.low:
        bg = dark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2);
        fg = dark ? const Color(0xFFFECACA) : const Color(0xFFB91C1C);
        label = l10n.racePredictorConfidenceLow;
        break;
    }
    return Tooltip(
      message: _reason(l10n, quality.reason),
      triggerMode: TooltipTriggerMode.longPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: fg,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

String _reason(AppLocalizations l10n, PredictionReason reason) {
  switch (reason) {
    case PredictionReason.similar:
      return l10n.racePredictorConfReasonSimilar;
    case PredictionReason.extrapolated:
      return l10n.racePredictorConfReasonExtrapolated;
    case PredictionReason.stale:
      return l10n.racePredictorConfReasonStale;
    case PredictionReason.limited:
      return l10n.racePredictorConfReasonLimited;
  }
}

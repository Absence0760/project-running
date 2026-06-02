/// Pure helper for the crash-resume recovery gate that runs at app
/// start. Separated out of main.dart so the truth table (recover vs
/// discard, with what threshold) is unit-testable.
///
/// Persona-hunt finding Casual #3: pre-fix, a sub-threshold partial
/// was silently `clearInProgress()`-d with zero feedback. A casual
/// runner who tapped Start then was interrupted ~40s later (kid /
/// dog / app-swipe) had no way to know the app saw their attempt and
/// dropped it. "The app ate my run" suspicion.
///
/// This helper decides the outcome and emits a short summary for the
/// caller to surface as a one-shot banner. The caller still owns
/// `store.save` / `store.clearInProgress`; we just classify.

import 'package:core_models/core_models.dart';

import 'l10n/locale_support.dart';
import 'l10n/number_format.dart';

enum InProgressOutcome { none, recovered, discarded }

class InProgressEvaluation {
  final InProgressOutcome outcome;

  /// The partial as a Run ready to save. Null unless outcome=recovered.
  final Run? recovered;

  /// Short human-readable summary used in the post-recovery banner.
  /// Null when nothing happened. Examples:
  ///   "Discarded a 38 m partial recording from a previous session"
  ///   "Discarded a 45 s indoor partial from a previous session"
  ///   "Recovered a 2.3 km partial from a previous session"
  final String? bannerMessage;

  const InProgressEvaluation({
    required this.outcome,
    this.recovered,
    this.bannerMessage,
  });
}

/// Classify an in-progress partial. The thresholds mirror the
/// pre-extraction inline logic in main.dart so the behaviour is
/// unchanged for callers that don't read the banner.
///
/// GPS partial: recover when track.length ≥ 3 AND distance ≥ 50 m.
/// Indoor partial (pedometer-only): recover when duration ≥ 60 s.
/// Below either threshold: discard with a banner.
InProgressEvaluation evaluateInProgressPartial(Run? partial) {
  if (partial == null) {
    return const InProgressEvaluation(outcome: InProgressOutcome.none);
  }

  final indoorEstimated = partial.metadata?['indoor_estimated'] == true;
  final hasEnoughGps = partial.track.length >= 3 &&
      partial.distanceMetres >= 50;
  final hasEnoughIndoor = indoorEstimated &&
      partial.duration.inSeconds >= 60;

  if (hasEnoughGps || hasEnoughIndoor) {
    final metadata = Map<String, dynamic>.from(partial.metadata ?? {});
    metadata['recovered_from_crash'] = true;
    final recovered = Run(
      id: partial.id,
      startedAt: partial.startedAt,
      duration: partial.duration,
      distanceMetres: partial.distanceMetres,
      track: partial.track,
      routeId: partial.routeId,
      source: partial.source,
      externalId: partial.externalId,
      metadata: metadata,
      createdAt: partial.createdAt,
    );
    final summary = indoorEstimated && !hasEnoughGps
        ? _formatDuration(partial.duration)
        : _formatDistance(partial.distanceMetres);
    return InProgressEvaluation(
      outcome: InProgressOutcome.recovered,
      recovered: recovered,
      bannerMessage:
          'Recovered a $summary partial from a previous session.',
    );
  }

  // Discard with a clear summary so the user knows the app saw + dropped
  // it. Below-threshold partials are typically <50 m / <60 s — accidental
  // taps, immediate cancels — but the banner is the difference between
  // "the app ate my run" and "the app noticed I tapped Start and bailed
  // out cleanly".
  final summary = indoorEstimated
      ? _formatDuration(partial.duration)
      : _formatDistance(partial.distanceMetres);
  return InProgressEvaluation(
    outcome: InProgressOutcome.discarded,
    bannerMessage:
        'Discarded a $summary partial recording from a previous session.',
  );
}

String _formatDistance(double m) {
  if (m < 1000) {
    return '${formatFixed(m.round().toDouble(), 0, activeLocaleTag)} m';
  }
  return '${formatFixed(m / 1000, 1, activeLocaleTag)} km';
}

String _formatDuration(Duration d) {
  final secs = d.inSeconds;
  if (secs < 60) return '$secs s';
  final mins = (secs / 60).floor();
  final remSecs = secs % 60;
  if (mins < 60) {
    return remSecs == 0 ? '$mins min' : '$mins min $remSecs s';
  }
  final hours = (mins / 60).floor();
  final remMins = mins % 60;
  return remMins == 0 ? '$hours h' : '$hours h $remMins min';
}

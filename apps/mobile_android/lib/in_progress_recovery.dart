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

enum InProgressOutcome { none, recovered, resumable, discarded }

class InProgressEvaluation {
  final InProgressOutcome outcome;

  /// The partial as a Run ready to save. Null unless outcome=recovered.
  final Run? recovered;

  /// The raw partial to hand back to the run screen so it can RE-HYDRATE the
  /// recorder and continue the SAME run. Null unless outcome=resumable. Carries
  /// the full track / laps / elapsed / id so the resumed run keeps continuity.
  final Run? resumablePartial;

  /// Short human-readable summary used in the post-recovery banner.
  /// Null when nothing happened, and null for [InProgressOutcome.resumable]
  /// (the run screen shows an interactive Resume / Finish / Discard prompt
  /// instead of a passive banner). Examples:
  ///   "Discarded a 38 m partial recording from a previous session"
  ///   "Discarded a 45 s indoor partial from a previous session"
  ///   "Recovered a 2.3 km partial from a previous session"
  final String? bannerMessage;

  const InProgressEvaluation({
    required this.outcome,
    this.recovered,
    this.resumablePartial,
    this.bannerMessage,
  });
}

/// A qualifying partial whose last incremental save is within this window of
/// "now" is offered as RESUMABLE — the recorder re-hydrates and continues the
/// SAME run rather than closing it out. Beyond it (or with no recency signal —
/// no `in_progress_saved_at`), a qualifying partial is finalized as before.
///
/// Wide enough to survive a long process-killed / offline stretch: a 240-mile
/// continuous effort can lose its OS process for 6–30 h in a canyon dead zone,
/// plus a sleep-station nap, and still expect to reopen the app at the next aid
/// station and continue ONE run. Bounded so a genuinely-abandoned partial from
/// days ago still auto-finalizes instead of prompting a stale resume.
const Duration kResumableWindow = Duration(hours: 48);

/// Classify an in-progress partial. The thresholds mirror the
/// pre-extraction inline logic in main.dart so the behaviour is
/// unchanged for callers that don't read the banner.
///
/// GPS partial: recover when track.length ≥ 3 AND distance ≥ 50 m.
/// Indoor partial (pedometer-only): recover when duration ≥ 60 s.
/// Below either threshold: discard with a banner.
InProgressEvaluation evaluateInProgressPartial(Run? partial, {DateTime? now}) {
  if (partial == null) {
    return const InProgressEvaluation(outcome: InProgressOutcome.none);
  }

  final indoorEstimated = partial.metadata?[MetadataKeys.indoorEstimated] == true;
  final hasEnoughGps = partial.track.length >= 3 &&
      partial.distanceMetres >= 50;
  final hasEnoughIndoor = indoorEstimated &&
      partial.duration.inSeconds >= 60;

  if (hasEnoughGps || hasEnoughIndoor) {
    // A recent qualifying partial is RESUMABLE — hand the raw partial back so
    // the run screen can re-hydrate the recorder and continue the SAME run
    // (Resume the primary action, Finish / Discard also offered). This is the
    // fix for the process-kill-splits-one-effort-into-two bug: pre-fix, the
    // only outcomes were finalize (recovered) or discard, never resume.
    if (_isRecent(partial, now ?? DateTime.now())) {
      return InProgressEvaluation(
        outcome: InProgressOutcome.resumable,
        resumablePartial: partial,
      );
    }

    // Stale (or no recency signal): finalize into a completed Run as before so
    // whatever was captured is at least kept.
    final metadata = Map<String, dynamic>.from(partial.metadata ?? {});
    metadata[MetadataKeys.recoveredFromCrash] = true;
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

/// Whether [partial]'s last incremental save is within [kResumableWindow] of
/// [now]. Recency comes from `metadata.in_progress_saved_at`, stamped on every
/// incremental save by `_saveInProgress`. A missing / unparseable stamp is
/// treated as NOT recent — an unknown-age partial finalizes (the pre-existing
/// behaviour) rather than surprising the user with a resume prompt for a run
/// whose age we can't establish. A future-dated stamp (clock skew) counts as
/// recent.
bool _isRecent(Run partial, DateTime now) {
  final raw = partial.metadata?[MetadataKeys.inProgressSavedAt];
  if (raw is! String) return false;
  final savedAt = DateTime.tryParse(raw);
  if (savedAt == null) return false;
  final age = now.toUtc().difference(savedAt.toUtc());
  return age <= kResumableWindow;
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

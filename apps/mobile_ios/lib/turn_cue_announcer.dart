import 'turn_cues.dart';

/// Distances ahead of a turn at which to announce it, far → near. The runner
/// hears the turn at ~300 m, again at ~100 m, and once more right at it.
const List<double> kTurnAnnounceThresholdsM = [300, 100, 0];

/// A single decided cue: the turn to announce plus the threshold band it was
/// fired for (the distance ahead, or 0 for "now").
class TurnAnnouncement {
  const TurnAnnouncement({
    required this.cue,
    required this.thresholdM,
    required this.aheadM,
  });
  final TurnCue cue;

  /// Which announce band fired this (300 / 100 / 0). 0 = "turn now". A slot
  /// identifier for the once-per-band bookkeeping — NOT a distance to speak.
  final double thresholdM;

  /// The runner's REAL distance ahead of the turn when this fired. This is
  /// what a spoken cue must state: the band is a coarse trigger and can be
  /// several times the true distance (a route whose first turn is 120 m out
  /// used to be announced as "in 300 metres").
  final double aheadM;

  /// True when this is the at-the-turn ("now") announcement.
  bool get isNow => thresholdM == 0;
}

/// Pure decision core for turn-by-turn voice cues. Holds the per-turn announce
/// state (which thresholds have already fired) so each band announces once per
/// turn, and decides — given the runner's current distance-along-route — which
/// announcement (if any) to speak on this snapshot.
///
/// Kept pure + Flutter-free so it's unit-testable without the TTS engine; the
/// run-screen wires its output through the best-effort `_ttsCue` wrapper
/// (decisions §169, layered resilience — a TTS failure never disturbs the
/// recording).
class TurnCueAnnouncer {
  TurnCueAnnouncer(List<TurnCue> cues)
      : _cues = List.unmodifiable(cues.where((c) =>
            c.direction != TurnDirection.straight));

  final List<TurnCue> _cues;

  /// Per-cue index → set of already-fired threshold bands.
  final Map<int, Set<double>> _fired = {};

  /// How close (m) the runner must be to a band's distance for it to fire.
  /// A snapshot lands every ~second; at running pace the runner moves a few
  /// metres per snapshot, so a ±25 m window catches each band without
  /// double-firing or missing it on a sparse fix.
  static const double _bandWindowM = 25;

  /// Decide the cue to announce for the runner at [distanceAlongRouteM], or
  /// null when nothing should be said this snapshot. Marks the chosen band as
  /// fired so it won't repeat. Only the NEAREST upcoming turn is considered,
  /// so two close turns don't talk over each other.
  ///
  /// When the runner is inside several unfired bands at once — a route whose
  /// first turn is 120 m from the start, or an along-route value that jumped
  /// a band's width after a GPS gap — only the TIGHTEST of them speaks; the
  /// looser ones are retired silently. Firing them in turn produced three
  /// announcements in three seconds, each stating a distance the runner was
  /// nowhere near.
  TurnAnnouncement? announcementFor(double distanceAlongRouteM) {
    for (var i = 0; i < _cues.length; i++) {
      final cue = _cues[i];
      final aheadM = cue.positionM - distanceAlongRouteM;
      // Past this turn (more than a band-window behind) — never announce it.
      if (aheadM < -_bandWindowM) continue;
      // This is the nearest still-upcoming (or just-reached) turn.
      final firedBands = _fired.putIfAbsent(i, () => <double>{});
      double? tightest;
      for (final band in kTurnAnnounceThresholdsM) {
        if (firedBands.contains(band)) continue;
        // A band applies once the runner is at/inside its distance-ahead.
        // The 0 ("now") band applies within the window of the turn itself.
        if (aheadM > band + _bandWindowM) continue;
        if (tightest != null) firedBands.add(tightest);
        tightest = band;
      }
      if (tightest == null) {
        // Nearest turn has no applicable unfired band this snapshot — stop
        // (don't skip ahead to a farther turn).
        return null;
      }
      firedBands.add(tightest);
      return TurnAnnouncement(cue: cue, thresholdM: tightest, aheadM: aheadM);
    }
    return null;
  }

  /// Forget which bands have already fired. The fired set is per-RECORDING,
  /// not per-route: without this, running the same route a second time (the
  /// backyard-ultra / repeated-loop case, where the recorder is restarted on
  /// the same loop every hour) announced nothing at all, because every band of
  /// the nearest turn was already latched and [announcementFor] returns on the
  /// nearest turn rather than skipping to a farther one.
  void reset() => _fired.clear();

  bool get hasCues => _cues.isNotEmpty;
}

import 'turn_cues.dart';

/// Distances ahead of a turn at which to announce it, far → near. The runner
/// hears the turn at ~300 m, again at ~100 m, and once more right at it.
const List<double> kTurnAnnounceThresholdsM = [300, 100, 0];

/// A single decided cue: the turn to announce plus the threshold band it was
/// fired for (the distance ahead, or 0 for "now").
class TurnAnnouncement {
  const TurnAnnouncement({required this.cue, required this.thresholdM});
  final TurnCue cue;

  /// Which announce band fired this (300 / 100 / 0). 0 = "turn now".
  final double thresholdM;

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
  TurnAnnouncement? announcementFor(double distanceAlongRouteM) {
    for (var i = 0; i < _cues.length; i++) {
      final cue = _cues[i];
      final aheadM = cue.positionM - distanceAlongRouteM;
      // Past this turn (more than a band-window behind) — never announce it.
      if (aheadM < -_bandWindowM) continue;
      // This is the nearest still-upcoming (or just-reached) turn.
      final firedBands = _fired.putIfAbsent(i, () => <double>{});
      for (final band in kTurnAnnounceThresholdsM) {
        if (firedBands.contains(band)) continue;
        // Fire a band once the runner is at/inside its distance-ahead. The
        // 0 ("now") band fires when within the window of the turn itself.
        if (aheadM <= band + _bandWindowM) {
          firedBands.add(band);
          return TurnAnnouncement(cue: cue, thresholdM: band);
        }
      }
      // Nearest turn has no unfired band left this snapshot — stop (don't
      // skip ahead to a farther turn).
      return null;
    }
    return null;
  }

  bool get hasCues => _cues.isNotEmpty;
}

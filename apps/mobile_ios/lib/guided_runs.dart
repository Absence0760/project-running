/// Guided audio runs — scripted coach-voice workouts. Each run is a
/// sequence of timed cues; the recorder fires them via TTS as the
/// runner crosses each second mark.
///
/// Mirrors `apps/web/src/lib/training/guided_runs.ts`. Keep in lockstep — the
/// shared-library-syncer agent watches the pair.
///
/// The cue scripts + titles are localized: the library is built from the
/// gen-l10n catalogue for the active locale via [guidedRunLibrary]. The cue
/// *timing* (atSec / durationSec) is locale-independent and stays inline; only
/// the spoken/displayed text comes from the catalogue.

import 'l10n/gen/app_localizations.dart';

class GuidedCue {
  final int atSec;
  final String text;
  const GuidedCue({required this.atSec, required this.text});
}

class GuidedRun {
  final String id;
  final String title;
  final String subtitle;
  final int durationSec;
  final String description;
  final List<GuidedCue> cues;

  const GuidedRun({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.durationSec,
    required this.description,
    required this.cues,
  });
}

/// Returns the cues whose [GuidedCue.atSec] falls in
/// `(prevElapsedSec, nowElapsedSec]`. The recorder calls this on every
/// tick with the previous and current elapsed seconds; the dispatcher
/// surfaces any cues that should fire between the two.
///
/// Idempotent w.r.t. duplicate ticks — calling with the same range
/// twice in a row returns the cues once on the first call and an
/// empty list on the second.
List<GuidedCue> cuesDue(GuidedRun guided, int prevElapsedSec, int nowElapsedSec) {
  if (nowElapsedSec <= prevElapsedSec) return const [];
  final out = <GuidedCue>[];
  for (final c in guided.cues) {
    if (c.atSec > prevElapsedSec && c.atSec <= nowElapsedSec) out.add(c);
  }
  return out;
}

bool isGuidedRunValid(GuidedRun g) {
  if (g.durationSec <= 0) return false;
  for (var i = 0; i < g.cues.length; i++) {
    final c = g.cues[i];
    if (c.atSec < 0 || c.atSec > g.durationSec) return false;
    if (i > 0 && c.atSec < g.cues[i - 1].atSec) return false;
    if (c.text.trim().isEmpty) return false;
  }
  return true;
}

/// Library of MVP guided runs, localized via [l10n]. The cue scripts are
/// deliberately compact — TTS reads them at ~3 wps so each cue is under a
/// sentence.
List<GuidedRun> guidedRunLibrary(AppLocalizations l10n) => [
      GuidedRun(
        id: 'easy-30',
        title: l10n.guidedEasy30Title,
        subtitle: l10n.guidedEasy30Subtitle,
        durationSec: 30 * 60,
        description: l10n.guidedEasy30Description,
        cues: [
          GuidedCue(atSec: 0, text: l10n.guidedEasy30Cue0),
          GuidedCue(atSec: 5 * 60, text: l10n.guidedEasy30Cue1),
          GuidedCue(atSec: 10 * 60, text: l10n.guidedEasy30Cue2),
          GuidedCue(atSec: 15 * 60, text: l10n.guidedEasy30Cue3),
          GuidedCue(atSec: 20 * 60, text: l10n.guidedEasy30Cue4),
          GuidedCue(atSec: 25 * 60, text: l10n.guidedEasy30Cue5),
          GuidedCue(atSec: 29 * 60, text: l10n.guidedEasy30Cue6),
          GuidedCue(atSec: 30 * 60, text: l10n.guidedEasy30Cue7),
        ],
      ),
      GuidedRun(
        id: 'tempo-builder-25',
        title: l10n.guidedTempo25Title,
        subtitle: l10n.guidedTempo25Subtitle,
        durationSec: 25 * 60,
        description: l10n.guidedTempo25Description,
        cues: [
          GuidedCue(atSec: 0, text: l10n.guidedTempo25Cue0),
          GuidedCue(atSec: 4 * 60, text: l10n.guidedTempo25Cue1),
          GuidedCue(atSec: 5 * 60, text: l10n.guidedTempo25Cue2),
          GuidedCue(atSec: 10 * 60, text: l10n.guidedTempo25Cue3),
          GuidedCue(atSec: 15 * 60, text: l10n.guidedTempo25Cue4),
          GuidedCue(atSec: 18 * 60, text: l10n.guidedTempo25Cue5),
          GuidedCue(atSec: 20 * 60, text: l10n.guidedTempo25Cue6),
          GuidedCue(atSec: 23 * 60, text: l10n.guidedTempo25Cue7),
          GuidedCue(atSec: 25 * 60, text: l10n.guidedTempo25Cue8),
        ],
      ),
      GuidedRun(
        id: 'first-timer-15',
        title: l10n.guidedFirst15Title,
        subtitle: l10n.guidedFirst15Subtitle,
        durationSec: 15 * 60,
        description: l10n.guidedFirst15Description,
        cues: [
          GuidedCue(atSec: 0, text: l10n.guidedFirst15Cue0),
          GuidedCue(atSec: 3 * 60, text: l10n.guidedFirst15Cue1),
          GuidedCue(atSec: 4 * 60, text: l10n.guidedFirst15Cue2),
          GuidedCue(atSec: 5 * 60, text: l10n.guidedFirst15Cue3),
          GuidedCue(atSec: 6 * 60, text: l10n.guidedFirst15Cue4),
          GuidedCue(atSec: 7 * 60, text: l10n.guidedFirst15Cue5),
          GuidedCue(atSec: 8 * 60, text: l10n.guidedFirst15Cue6),
          GuidedCue(atSec: 9 * 60, text: l10n.guidedFirst15Cue7),
          GuidedCue(atSec: 10 * 60, text: l10n.guidedFirst15Cue8),
          GuidedCue(atSec: 14 * 60, text: l10n.guidedFirst15Cue9),
          GuidedCue(atSec: 15 * 60, text: l10n.guidedFirst15Cue10),
        ],
      ),
    ];

GuidedRun? findGuidedRun(AppLocalizations l10n, String id) {
  for (final g in guidedRunLibrary(l10n)) {
    if (g.id == id) return g;
  }
  return null;
}

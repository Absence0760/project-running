/// Guided audio runs — scripted coach-voice workouts. Each run is a
/// sequence of timed cues; the recorder fires them via TTS as the
/// runner crosses each second mark.
///
/// Mirrors `apps/web/src/lib/guided_runs.ts`. Keep in lockstep — the
/// shared-library-syncer agent watches the pair.

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

/// Library of MVP guided runs. The cue scripts are deliberately
/// compact — TTS reads them at ~3 wps so each cue is under a
/// sentence.
const List<GuidedRun> kGuidedRunLibrary = [
  GuidedRun(
    id: 'easy-30',
    title: '30-Minute Easy Run',
    subtitle: 'Coach voice · 30 min · easy effort',
    durationSec: 30 * 60,
    description:
        'A relaxed, conversational-pace run for a recovery day or just clearing your head. Coach checks in every five minutes with a gentle nudge.',
    cues: [
      GuidedCue(atSec: 0, text: 'Let’s go. Start easy — this is your recovery pace.'),
      GuidedCue(atSec: 5 * 60, text: 'Five minutes in. Drop your shoulders. Keep it conversational.'),
      GuidedCue(atSec: 10 * 60, text: 'Ten minutes. Cadence check — quick feet, light landing.'),
      GuidedCue(atSec: 15 * 60, text: 'Halfway. You should still be able to talk through this.'),
      GuidedCue(atSec: 20 * 60, text: 'Twenty minutes. Notice your breathing — slow nasal in, mouth out.'),
      GuidedCue(atSec: 25 * 60, text: 'Five to go. Stay relaxed. Don’t pick it up.'),
      GuidedCue(atSec: 29 * 60, text: 'One minute left. Easy finish.'),
      GuidedCue(atSec: 30 * 60, text: 'Done. Walk it out for a minute. Nice job.'),
    ],
  ),
  GuidedRun(
    id: 'tempo-builder-25',
    title: '25-Minute Tempo Builder',
    subtitle: 'Coach voice · 25 min · 5-15-5',
    durationSec: 25 * 60,
    description:
        'Five-minute easy warm-up, fifteen minutes at tempo (comfortably hard), five-minute cool-down. The bread-and-butter weekly tempo session.',
    cues: [
      GuidedCue(atSec: 0, text: 'Warm-up time. Five minutes easy — wake up the legs.'),
      GuidedCue(atSec: 4 * 60, text: 'One minute left in the warm-up. Pick up the cadence.'),
      GuidedCue(atSec: 5 * 60, text: 'Lift it to tempo. Comfortably hard. Like a 10K race effort.'),
      GuidedCue(atSec: 10 * 60, text: 'Five minutes in tempo. Strong but controlled. Keep the rhythm.'),
      GuidedCue(atSec: 15 * 60, text: 'Ten minutes of tempo done. Hold the pace.'),
      GuidedCue(atSec: 18 * 60, text: 'Two minutes left at tempo. Stay smooth.'),
      GuidedCue(atSec: 20 * 60, text: 'Ease off. Five minutes easy to cool down.'),
      GuidedCue(atSec: 23 * 60, text: 'Two to go. Bring the heart rate back down.'),
      GuidedCue(atSec: 25 * 60, text: 'Done. Walk and stretch. Great work.'),
    ],
  ),
  GuidedRun(
    id: 'first-timer-15',
    title: 'First-Timer 15-Minute Run/Walk',
    subtitle: 'Coach voice · 15 min · run/walk intervals',
    durationSec: 15 * 60,
    description:
        'New to running? Three rounds of one-minute run, one-minute walk, plus a warm-up and cool-down. A gentle on-ramp; everyone starts here.',
    cues: [
      GuidedCue(atSec: 0, text: 'Start with a three-minute brisk walk to warm up.'),
      GuidedCue(atSec: 3 * 60, text: 'Switch to a one-minute easy run. Conversational pace.'),
      GuidedCue(atSec: 4 * 60, text: 'Walk one minute.'),
      GuidedCue(atSec: 5 * 60, text: 'Run one minute.'),
      GuidedCue(atSec: 6 * 60, text: 'Walk one minute.'),
      GuidedCue(atSec: 7 * 60, text: 'Run one minute.'),
      GuidedCue(atSec: 8 * 60, text: 'Walk one minute.'),
      GuidedCue(atSec: 9 * 60, text: 'Run one minute — last one.'),
      GuidedCue(atSec: 10 * 60, text: 'Walk it down. Five-minute cool-down.'),
      GuidedCue(atSec: 14 * 60, text: 'One minute left. Walk easy.'),
      GuidedCue(atSec: 15 * 60, text: 'Done. That was a real run. Get out there again soon.'),
    ],
  ),
];

GuidedRun? findGuidedRun(String id) {
  for (final g in kGuidedRunLibrary) {
    if (g.id == id) return g;
  }
  return null;
}

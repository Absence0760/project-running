/**
 * Guided audio runs — scripted coach-voice workouts. Each run is a
 * sequence of timed cues; the recorder fires them via TTS as the
 * runner crosses each second mark.
 *
 * MVP shape: pure module + a small library of scripted workouts.
 * The cues are speakable strings; the on-device TTS layer
 * (`audio_cues.dart` on mobile) speaks them when the dispatcher
 * surfaces them. Web doesn't record — the library is preview-only
 * on the web surface.
 *
 * Mirrors `apps/mobile_android/lib/guided_runs.dart`. Keep in
 * lockstep — the shared-library-syncer agent watches the pair.
 */

export interface GuidedCue {
	/** Seconds from the start of the run when the cue should fire. */
	at_sec: number;
	/** The line the TTS layer speaks. Also shown on-screen as a tick. */
	text: string;
}

export interface GuidedRun {
	id: string;
	title: string;
	/** Short coach-voice subtitle ("Coach voice · 30 min · easy effort"). */
	subtitle: string;
	/** Target duration in seconds. Used for the library list + countdown. */
	duration_sec: number;
	/** One-paragraph blurb shown on the detail / preview surface. */
	description: string;
	/** Ordered list of cues. Sorted ascending by at_sec. */
	cues: GuidedCue[];
}

/**
 * Returns the cues whose `at_sec` falls inside
 * `(prevElapsedSec, nowElapsedSec]`. The recorder calls this on every
 * tick with the previous and current elapsed seconds; the dispatcher
 * surfaces any cues that should fire between the two.
 *
 * Idempotent w.r.t. duplicate ticks — calling with the same range
 * twice in a row returns the cues once on the first call and an
 * empty array on the second.
 */
export function cuesDue(
	guided: GuidedRun,
	prevElapsedSec: number,
	nowElapsedSec: number,
): GuidedCue[] {
	if (nowElapsedSec <= prevElapsedSec) return [];
	const out: GuidedCue[] = [];
	for (const c of guided.cues) {
		if (c.at_sec > prevElapsedSec && c.at_sec <= nowElapsedSec) out.push(c);
	}
	return out;
}

/** Validate that a guided run's cues are sorted and within duration. */
export function isGuidedRunValid(g: GuidedRun): boolean {
	if (g.duration_sec <= 0) return false;
	for (let i = 0; i < g.cues.length; i++) {
		const c = g.cues[i];
		if (c.at_sec < 0 || c.at_sec > g.duration_sec) return false;
		if (i > 0 && c.at_sec < g.cues[i - 1].at_sec) return false;
		if (c.text.trim().length === 0) return false;
	}
	return true;
}

/**
 * Library of MVP guided runs. The cue scripts are deliberately
 * compact — TTS reads them at ~3 wps so each cue is under a
 * sentence. The library is a constant so the test suite can pin
 * its shape.
 */
export const GUIDED_RUN_LIBRARY: GuidedRun[] = [
	{
		id: 'easy-30',
		title: '30-Minute Easy Run',
		subtitle: 'Coach voice · 30 min · easy effort',
		duration_sec: 30 * 60,
		description:
			'A relaxed, conversational-pace run for a recovery day or just clearing your head. Coach checks in every five minutes with a gentle nudge.',
		cues: [
			{ at_sec: 0, text: 'Let’s go. Start easy — this is your recovery pace.' },
			{ at_sec: 5 * 60, text: 'Five minutes in. Drop your shoulders. Keep it conversational.' },
			{ at_sec: 10 * 60, text: 'Ten minutes. Cadence check — quick feet, light landing.' },
			{ at_sec: 15 * 60, text: 'Halfway. You should still be able to talk through this.' },
			{ at_sec: 20 * 60, text: 'Twenty minutes. Notice your breathing — slow nasal in, mouth out.' },
			{ at_sec: 25 * 60, text: 'Five to go. Stay relaxed. Don’t pick it up.' },
			{ at_sec: 29 * 60, text: 'One minute left. Easy finish.' },
			{ at_sec: 30 * 60, text: 'Done. Walk it out for a minute. Nice job.' },
		],
	},
	{
		id: 'tempo-builder-25',
		title: '25-Minute Tempo Builder',
		subtitle: 'Coach voice · 25 min · 5-15-5',
		duration_sec: 25 * 60,
		description:
			'Five-minute easy warm-up, fifteen minutes at tempo (comfortably hard), five-minute cool-down. The bread-and-butter weekly tempo session.',
		cues: [
			{ at_sec: 0, text: 'Warm-up time. Five minutes easy — wake up the legs.' },
			{ at_sec: 4 * 60, text: 'One minute left in the warm-up. Pick up the cadence.' },
			{ at_sec: 5 * 60, text: 'Lift it to tempo. Comfortably hard. Like a 10K race effort.' },
			{ at_sec: 10 * 60, text: 'Five minutes in tempo. Strong but controlled. Keep the rhythm.' },
			{ at_sec: 15 * 60, text: 'Ten minutes of tempo done. Hold the pace.' },
			{ at_sec: 18 * 60, text: 'Two minutes left at tempo. Stay smooth.' },
			{ at_sec: 20 * 60, text: 'Ease off. Five minutes easy to cool down.' },
			{ at_sec: 23 * 60, text: 'Two to go. Bring the heart rate back down.' },
			{ at_sec: 25 * 60, text: 'Done. Walk and stretch. Great work.' },
		],
	},
	{
		id: 'first-timer-15',
		title: 'First-Timer 15-Minute Run/Walk',
		subtitle: 'Coach voice · 15 min · run/walk intervals',
		duration_sec: 15 * 60,
		description:
			'New to running? Three rounds of one-minute run, one-minute walk, plus a warm-up and cool-down. A gentle on-ramp; everyone starts here.',
		cues: [
			{ at_sec: 0, text: 'Start with a three-minute brisk walk to warm up.' },
			{ at_sec: 3 * 60, text: 'Switch to a one-minute easy run. Conversational pace.' },
			{ at_sec: 4 * 60, text: 'Walk one minute.' },
			{ at_sec: 5 * 60, text: 'Run one minute.' },
			{ at_sec: 6 * 60, text: 'Walk one minute.' },
			{ at_sec: 7 * 60, text: 'Run one minute.' },
			{ at_sec: 8 * 60, text: 'Walk one minute.' },
			{ at_sec: 9 * 60, text: 'Run one minute — last one.' },
			{ at_sec: 10 * 60, text: 'Walk it down. Five-minute cool-down.' },
			{ at_sec: 14 * 60, text: 'One minute left. Walk easy.' },
			{ at_sec: 15 * 60, text: 'Done. That was a real run. Get out there again soon.' },
		],
	},
];

/** Look up a guided run by id. Returns null if not in the library. */
export function findGuidedRun(id: string): GuidedRun | null {
	return GUIDED_RUN_LIBRARY.find((g) => g.id === id) ?? null;
}

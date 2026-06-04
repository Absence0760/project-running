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
 *
 * The cue scripts + titles are localized: the library is built from the
 * message catalogue for the active locale via `guidedRunLibrary(t)` (web
 * twin of the mobile `guidedRunLibrary(AppLocalizations)`). The cue
 * *timing* (at_sec / duration_sec) is locale-independent and stays inline;
 * only the spoken/displayed text comes from the catalogue.
 */

import type { MessageKey } from '$lib/i18n/messages';

/**
 * A catalogue lookup — the runtime `m` from `$lib/i18n/store.svelte`
 * satisfies this. Call sites pass `m` so the library re-renders on a
 * locale switch (build it inside a `$derived`, never a top-level const).
 */
export type GuidedTranslate = (key: MessageKey) => string;

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
 * Library of MVP guided runs, localized via `t`. The cue scripts are
 * deliberately compact — TTS reads them at ~3 wps so each cue is under a
 * sentence. The timing (at_sec / duration_sec) is locale-independent and
 * stays inline; only the spoken/displayed text comes from the catalogue.
 *
 * Build this inside a `$derived(...)` (or call it inline in a template) so
 * the rendered library tracks a locale switch — never assign it to a
 * top-level `const`, which would freeze the strings to the boot locale.
 */
export function guidedRunLibrary(t: GuidedTranslate): GuidedRun[] {
	return [
		{
			id: 'easy-30',
			title: t('guidedRuns.easy30.title'),
			subtitle: t('guidedRuns.easy30.subtitle'),
			duration_sec: 30 * 60,
			description: t('guidedRuns.easy30.description'),
			cues: [
				{ at_sec: 0, text: t('guidedRuns.easy30.cue0') },
				{ at_sec: 5 * 60, text: t('guidedRuns.easy30.cue1') },
				{ at_sec: 10 * 60, text: t('guidedRuns.easy30.cue2') },
				{ at_sec: 15 * 60, text: t('guidedRuns.easy30.cue3') },
				{ at_sec: 20 * 60, text: t('guidedRuns.easy30.cue4') },
				{ at_sec: 25 * 60, text: t('guidedRuns.easy30.cue5') },
				{ at_sec: 29 * 60, text: t('guidedRuns.easy30.cue6') },
				{ at_sec: 30 * 60, text: t('guidedRuns.easy30.cue7') },
			],
		},
		{
			id: 'tempo-builder-25',
			title: t('guidedRuns.tempo25.title'),
			subtitle: t('guidedRuns.tempo25.subtitle'),
			duration_sec: 25 * 60,
			description: t('guidedRuns.tempo25.description'),
			cues: [
				{ at_sec: 0, text: t('guidedRuns.tempo25.cue0') },
				{ at_sec: 4 * 60, text: t('guidedRuns.tempo25.cue1') },
				{ at_sec: 5 * 60, text: t('guidedRuns.tempo25.cue2') },
				{ at_sec: 10 * 60, text: t('guidedRuns.tempo25.cue3') },
				{ at_sec: 15 * 60, text: t('guidedRuns.tempo25.cue4') },
				{ at_sec: 18 * 60, text: t('guidedRuns.tempo25.cue5') },
				{ at_sec: 20 * 60, text: t('guidedRuns.tempo25.cue6') },
				{ at_sec: 23 * 60, text: t('guidedRuns.tempo25.cue7') },
				{ at_sec: 25 * 60, text: t('guidedRuns.tempo25.cue8') },
			],
		},
		{
			id: 'first-timer-15',
			title: t('guidedRuns.first15.title'),
			subtitle: t('guidedRuns.first15.subtitle'),
			duration_sec: 15 * 60,
			description: t('guidedRuns.first15.description'),
			cues: [
				{ at_sec: 0, text: t('guidedRuns.first15.cue0') },
				{ at_sec: 3 * 60, text: t('guidedRuns.first15.cue1') },
				{ at_sec: 4 * 60, text: t('guidedRuns.first15.cue2') },
				{ at_sec: 5 * 60, text: t('guidedRuns.first15.cue3') },
				{ at_sec: 6 * 60, text: t('guidedRuns.first15.cue4') },
				{ at_sec: 7 * 60, text: t('guidedRuns.first15.cue5') },
				{ at_sec: 8 * 60, text: t('guidedRuns.first15.cue6') },
				{ at_sec: 9 * 60, text: t('guidedRuns.first15.cue7') },
				{ at_sec: 10 * 60, text: t('guidedRuns.first15.cue8') },
				{ at_sec: 14 * 60, text: t('guidedRuns.first15.cue9') },
				{ at_sec: 15 * 60, text: t('guidedRuns.first15.cue10') },
			],
		},
	];
}

/** Look up a guided run by id. Returns null if not in the library. */
export function findGuidedRun(t: GuidedTranslate, id: string): GuidedRun | null {
	return guidedRunLibrary(t).find((g) => g.id === id) ?? null;
}

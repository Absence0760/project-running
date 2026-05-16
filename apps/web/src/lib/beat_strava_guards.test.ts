// Source-level guards for the "beat Strava" surfaces shipped in
// commits 8727244..fab0887: readiness card, year recap, /compare,
// race-day panel, guided runs. Each test reads a source file as text
// and asserts a pattern is present, with a reason a future editor
// can read before deciding it's safe to break.
//
// Mirrors the segments_panel_guards.test.ts pattern.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

// ─────────── Readiness card ───────────

test('Dashboard wires the readiness card through computeReadiness()', () => {
	// Reason: the readiness score must come from the pure helper, not
	// an inline reimplementation. Anyone reaching for inline math here
	// would silently disagree with the unit-tested band thresholds.
	const source = read('src/routes/dashboard/+page.svelte');
	assert.match(source, /computeReadiness/, 'dashboard must call the pure helper');
	assert.match(source, /class="readiness-card readiness-\{readiness\.band\}"/, 'band-coded card class missing');
});

test('Dashboard readiness card hides when TSB is null', () => {
	// Reason: showing the card with zero contributors and the
	// "Connect sleep + HR" placeholder is a worse signal than not
	// showing it at all. Hide when there's no real input.
	const source = read('src/routes/dashboard/+page.svelte');
	assert.match(
		source,
		/\{#if liveSnap\.trainingStressBal != null\}/,
		'readiness card must gate on TSB presence',
	);
});

// ─────────── Year recap ───────────

test('/recap/[year] uses the pure buildYearInRunningRecap helper', () => {
	const source = read('src/routes/recap/[year]/+page.svelte');
	assert.match(source, /buildYearInRunningRecap/, 'recap page must call the pure helper');
});

test('/recap/[year] gates on a valid year (2010-2100)', () => {
	// Reason: a stray URL like /recap/banana would otherwise call
	// buildYearInRunningRecap(_, NaN) and silently show empty data.
	const source = read('src/routes/recap/[year]/+page.svelte');
	assert.match(source, /year >= 2010 && year <= 2100/, 'year range guard missing');
});

test('/recap/[year] surfaces a share button that uses navigator.share or clipboard', () => {
	const source = read('src/routes/recap/[year]/+page.svelte');
	assert.match(source, /navigator\.share/, 'share-button should prefer navigator.share');
	assert.match(source, /clipboard\.writeText/, 'share-button must fall back to clipboard');
});

test('Dashboard links to /recap/{current year}', () => {
	const source = read('src/routes/dashboard/+page.svelte');
	assert.match(
		source,
		/href="\/recap\/\{new Date\(\)\.getFullYear\(\)\}"/,
		'dashboard must link to the current-year recap',
	);
});

// ─────────── /compare ───────────

test('/compare reads sections from the shared COMPARE_SECTIONS constant', () => {
	// Reason: hard-coding the table inline would let the page drift
	// from the unit-tested data. The unit tests enforce that no row
	// claims "no" in our column; a drifted inline table sidesteps
	// that contract.
	const source = read('src/routes/compare/+page.svelte');
	assert.match(source, /COMPARE_SECTIONS/, 'page must read the shared constant');
});

test('/compare iterates rows by section in the markup', () => {
	const source = read('src/routes/compare/+page.svelte');
	assert.match(
		source,
		/\{#each COMPARE_SECTIONS as section/,
		'expected an each-block over sections',
	);
	assert.match(
		source,
		/\{#each section\.rows as row/,
		'expected an each-block over rows',
	);
});

// ─────────── Race-day panel ───────────

test('RaceDayPanel routes through evenSplitPacing + negativeSplitPacing', () => {
	const source = read('src/lib/components/RaceDayPanel.svelte');
	assert.match(source, /evenSplitPacing/, 'panel must use the even-split helper');
	assert.match(source, /negativeSplitPacing/, 'panel must use the negative-split helper');
});

test('RaceDayPanel falls back to a Riegel projection when no goal time', () => {
	// Reason: a plan with no goal_time_seconds set must still produce
	// a finish prediction so the pacing grid renders. riegelPredict
	// off the user's best recent run is the documented fallback.
	const source = read('src/lib/components/RaceDayPanel.svelte');
	assert.match(source, /riegelPredict/, 'panel must Riegel-predict when goalTimeSec is null');
});

test('/plans/[id] only mounts the race-day panel within 21 days', () => {
	// Reason: showing race-day prep two months out is noise. The
	// `daysUntilRace` guard caps visibility at the taper window.
	const source = read('src/routes/plans/[id]/+page.svelte');
	assert.match(
		source,
		/days >= 0 && days <= 21/,
		'21-day visibility window missing',
	);
});

// ─────────── Guided runs ───────────

test('/guided lists every run in GUIDED_RUN_LIBRARY', () => {
	const source = read('src/routes/guided/+page.svelte');
	assert.match(source, /GUIDED_RUN_LIBRARY/, 'library page must iterate the shared constant');
	assert.match(source, /\{#each GUIDED_RUN_LIBRARY as g/, 'each-block over the library missing');
});

test('/guided makes clear that recording happens on mobile', () => {
	// Reason: web has no live recording (decisions §24). If the page
	// silently implied otherwise, users would expect a Start button
	// that can't exist here.
	const source = read('src/routes/guided/+page.svelte');
	assert.match(source, /Open these on the mobile app|mobile app/i, 'mobile hand-off note missing');
});

test('/guided/[id] uses findGuidedRun for the lookup', () => {
	const source = read('src/routes/guided/[id]/+page.svelte');
	assert.match(source, /findGuidedRun/, 'detail page must use the lookup helper');
});

test('/coach surfaces the Guided runs library on its page', () => {
	// Reason: the dedicated `/guided` sidebar entry was removed when the
	// nav tightened to 5 items. Guided + Coach are both coach-driven,
	// so the library is reachable from /coach via a side rail / section
	// that iterates GUIDED_RUN_LIBRARY. A regression that drops the
	// reference would leave guided runs only accessible by typing the
	// URL — effectively orphaning the library.
	const source = read('src/routes/coach/+page.svelte');
	assert.match(source, /GUIDED_RUN_LIBRARY/, '/coach must surface the guided-run library');
	assert.match(source, /\{#each GUIDED_RUN_LIBRARY as g/, 'each-block over the library missing on /coach');
});

// ─────────── audio_cues.dart speakGuidedCue ───────────

test('audio_cues.dart exposes speakGuidedCue for the recorder integration', () => {
	// Reason: the recorder side of the guided-runs MVP plumbs each cue
	// through this method. Removing it without a replacement breaks
	// the planned wiring.
	const source = read('../mobile_android/lib/audio_cues.dart');
	assert.match(source, /Future<void> speakGuidedCue\(String text\)/, 'speakGuidedCue method missing');
});

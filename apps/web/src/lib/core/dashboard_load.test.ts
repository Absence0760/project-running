// Source-grep guards on the /dashboard mount sequence. Run with
// `npx tsx --test apps/web/src/lib/core/dashboard_load.test.ts`.
//
// The mount is a Svelte onMount that issues ~15 Supabase reads; it can't be
// unit-tested without a stack. Pin the shape in the source instead, the same
// way coach/context.test.ts pins its no-duplicate-get_my_profile invariant.
//
// The dashboard is the app's highest-traffic page. It used to run six serial
// stages after its opening batch, two of which re-read something an earlier
// stage had already fetched: `loadSettings` (two selects) and `get_my_profile`
// (one) were each called twice. The reads have no dependency on each other, so
// they belong in the opening batch.
//
// The dependency that IS real: `loadTodaysNutrition` reads `runs` and
// `gymWorkouts`, and the fitness-snapshot write reads `runs`. Both must stay
// downstream of the batch that fills them.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SRC = readFileSync(
	resolve(import.meta.dirname, '../../routes/dashboard/+page.svelte'),
	'utf8',
);

/** Occurrences of `re` in the dashboard source. */
function count(re: RegExp): number {
	return SRC.match(new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g'))
		?.length ?? 0;
}

test('dashboard: get_my_profile is read once per mount', () => {
	assert.equal(
		count(/rpc\(\s*['"]get_my_profile['"]/),
		1,
		'the age-grade column and the nutrition targets share one self-read',
	);
});

test('dashboard: loadSettings is called once per mount', () => {
	assert.equal(
		count(/\bloadSettings\(/),
		1,
		'loadTodaysNutrition takes the settings the mount already loaded',
	);
});

test('dashboard: loadTodaysNutrition is handed the settings + profile, not left to re-read them', () => {
	assert.match(
		SRC,
		/async function loadTodaysNutrition\(\s*settings:\s*LoadedSettings\s*\|\s*null,\s*profile:\s*DashboardProfile\s*\|\s*null,?\s*\)/,
	);
});

test('dashboard: the reads with no dependency all share one batch', () => {
	// The opening Promise.all — everything from the runs read through the
	// profile read. A refactor that pulls one back out into its own await
	// costs a serial round trip on every dashboard load.
	const batch = SRC.match(/\]\s*=\s*await Promise\.all\(\[([\s\S]*?)\n\t\t\]\);/);
	assert.ok(batch, 'the mount must open with one Promise.all batch');
	for (const call of [
		'fetchRunsForDashboard(',
		'fetchRunAllTimeStats(',
		'fetchWeeklyMileage(',
		'fetchPersonalRecords(',
		'fetchActivePlanOverview(',
		'fetchNextRsvpedEvent(',
		'fetchFitnessSnapshots(',
		'loadSettings(',
		'fetchGymWorkouts(',
		'fetchGymSetHistory(',
		'fetchDashboardProfile(',
	]) {
		assert.ok(batch![1].includes(call), `${call}) belongs in the opening batch`);
	}
});

test('dashboard: every additive read in the batch is individually guarded', () => {
	// A rejection anywhere in a Promise.all rejects the whole batch. The
	// settings / gym / profile reads are additive — a blip in one must not
	// take the run-derived cards down with it, which is what the per-read
	// try/catch blocks used to guarantee.
	const batch = SRC.match(/\]\s*=\s*await Promise\.all\(\[([\s\S]*?)\n\t\t\]\);/);
	assert.match(batch![1], /loadSettings\(uid\)\.catch\(/);
	assert.match(batch![1], /fetchGymSetHistory\(\{ sinceDays: 180 \}\)\]\)\.catch\(/);
	assert.match(SRC, /async function fetchDashboardProfile\(\)[\s\S]*?catch \(_\) \{\s*return null;/);
});

test('dashboard: the runs-dependent work stays downstream of the batch', () => {
	const batchEnd = SRC.indexOf('] = await Promise.all([');
	assert.ok(batchEnd > 0);
	const nutrition = SRC.indexOf('loadTodaysNutrition(settingsRead, profileRead)');
	const snapshot = SRC.indexOf('insertFitnessSnapshot(computeSnapshot(runs))');
	const gymAssign = SRC.indexOf('[gymWorkouts, gymHistory] = gymRead');
	const runsAssign = SRC.indexOf('runs = runsRead.runs');
	assert.ok(runsAssign > batchEnd, 'runs is assigned from the batch');
	assert.ok(gymAssign > batchEnd, 'gymWorkouts is assigned from the batch');
	// loadTodaysNutrition filters `runs` and `gymWorkouts` by today; the
	// snapshot is computed from `runs`. Both must follow those assignments.
	assert.ok(nutrition > gymAssign, 'loadTodaysNutrition reads gymWorkouts — it must run after it');
	assert.ok(nutrition > runsAssign, 'loadTodaysNutrition reads runs — it must run after it');
	assert.ok(snapshot > runsAssign, 'the fitness snapshot is computed from runs');
});

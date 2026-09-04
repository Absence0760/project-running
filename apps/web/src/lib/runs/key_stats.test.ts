import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { cadenceSpm, elevationSourceTrack, stepCount, MIN_CADENCE_MOVING_S } from './key_stats';
import { stripComments } from '../core/strip_comments';
import type { TrackPoint } from '../types';

function pt(over: Partial<TrackPoint> = {}): TrackPoint {
	return { lat: 0, lng: 0, ...over };
}

test('elevationSourceTrack — no track at all is no altitude reading', () => {
	assert.equal(elevationSourceTrack(null), null);
	assert.equal(elevationSourceTrack(undefined), null);
	assert.equal(elevationSourceTrack([]), null);
});

test('elevationSourceTrack — a track that never recorded altitude is not flat, it is unmeasured', () => {
	// The case the run-detail grid used to report as `0 m`: a Health Connect
	// or parkrun summary import carries positions and no `ele` at all.
	assert.equal(elevationSourceTrack([pt(), pt(), pt()]), null);
	assert.equal(
		elevationSourceTrack([pt({ ele: undefined }), pt({ ele: null as unknown as number })]),
		null,
	);
});

test('elevationSourceTrack — a genuinely flat run still has a reading', () => {
	// The other direction, and the one an over-eager gate would break: 0 m of
	// climb over a track that DID record altitude is a measurement.
	const flat = [pt({ ele: 0 }), pt({ ele: 0 })];
	assert.equal(elevationSourceTrack(flat), flat);
	const seaLevelish = [pt({ ele: 12 }), pt({ ele: 12 })];
	assert.equal(elevationSourceTrack(seaLevelish), seaLevelish);
});

test('elevationSourceTrack — one sample anywhere is enough, and the whole track is returned', () => {
	// `computeElevationGain` carries the last reading across a dropout, so the
	// gate must not narrow the track it hands over.
	const patchy = [pt(), pt({ ele: 100 }), pt()];
	assert.equal(elevationSourceTrack(patchy), patchy);
	assert.equal(elevationSourceTrack(patchy)?.length, 3);
});

test('stepCount — a stored zero is the absence of a count, not a count of zero', () => {
	assert.equal(stepCount(0), null);
	assert.equal(stepCount(-1), null);
	assert.equal(stepCount(0.4), null);
});

test('stepCount — a real count survives, a fractional one truncates like mobile', () => {
	assert.equal(stepCount(1), 1);
	assert.equal(stepCount(8421), 8421);
	assert.equal(stepCount(8421.9), 8421);
});

test('stepCount — the metadata bag has no schema, so anything else is no reading', () => {
	assert.equal(stepCount(undefined), null);
	assert.equal(stepCount(null), null);
	assert.equal(stepCount('8421'), null);
	assert.equal(stepCount(true), null);
	assert.equal(stepCount({ steps: 8421 }), null);
	assert.equal(stepCount(Number.NaN), null);
	assert.equal(stepCount(Number.POSITIVE_INFINITY), null);
});

test('cadenceSpm — a reported value wins and is rounded', () => {
	assert.equal(cadenceSpm(176, null, 0), 176);
	assert.equal(cadenceSpm(176.4, 8000, 3600), 176);
	assert.equal(cadenceSpm(175.5, null, 0), 176);
});

test('cadenceSpm — a reported value that rounds away claims nothing, and does not fall through', () => {
	// Mobile returns the rounded reading and hides the tile on `> 0`; falling
	// through to the pedometer derivation here would make the two disagree.
	assert.equal(cadenceSpm(0.4, 8000, 3600), null);
});

test('cadenceSpm — an unusable reported value falls through to the derivation', () => {
	assert.equal(cadenceSpm(0, 8000, 3600), 133);
	assert.equal(cadenceSpm(-5, 8000, 3600), 133);
	assert.equal(cadenceSpm(Number.NaN, 8000, 3600), 133);
	assert.equal(cadenceSpm(Number.POSITIVE_INFINITY, 8000, 3600), 133);
	assert.equal(cadenceSpm('176', 8000, 3600), 133);
	assert.equal(cadenceSpm(undefined, 8000, 3600), 133);
});

test('cadenceSpm — no steps means no derived cadence', () => {
	assert.equal(cadenceSpm(undefined, null, 3600), null);
});

test('cadenceSpm — under the moving-time floor the quotient is too noisy to state', () => {
	assert.equal(cadenceSpm(undefined, 100, MIN_CADENCE_MOVING_S - 1), null);
	assert.equal(cadenceSpm(undefined, 100, MIN_CADENCE_MOVING_S), 200);
	assert.equal(cadenceSpm(undefined, 100, Number.NaN), null);
});

test('cadenceSpm — a derived cadence that rounds to zero is no cadence', () => {
	assert.equal(cadenceSpm(undefined, 1, 3600), null);
});

// ── Source guard over the grid the helpers gate ────────────────────────────
//
// The three helpers can be right while the page renders the cell anyway —
// which is exactly the state this closed: `realElevationGain` was gated to `0`
// and then rendered with no `{#if}` at all, so a run with no track and a run
// over a summit both read `0 m`. And the count that drives the parity filler
// was a hand-maintained `6 +` whose own comment named a stat the template
// gated. Both are structural claims about the page, so they are pinned here.

const page = stripComments(
	readFileSync(resolve(import.meta.dirname, '../../routes/runs/[id]/+page.svelte'), 'utf-8'),
);

test('the run-detail elevation cell is gated on a track that measured altitude', () => {
	const derived = page
		.split('\n')
		.find((l) => l.includes('realElevationGain') && l.includes('$derived'));
	assert.ok(derived, 'the run-detail page no longer derives realElevationGain');
	assert.match(
		derived,
		/:\s*null\)/,
		'an unmeasured climb must be null — a `: 0` fallback reports "no altitude was ' +
			'recorded" as "this run was flat".',
	);
	assert.match(
		page,
		/import \{[^}]*\belevationSourceTrack\b[^}]*\} from '\$lib\/runs\/key_stats'/,
		'the samples test belongs to the gate helper, not to a second copy on the page',
	);
	assert.match(
		page,
		/if \(realElevationGain != null\) \{/,
		'and the cell has to be gated on it — the render used to be unconditional',
	);
});

test('the key-stats grid renders the derived cell list, and counts itself from it', () => {
	assert.match(
		page,
		/\{#each keyStats as stat\}/,
		'the grid renders the derived list, so a cell exists exactly when its datum does',
	);
	assert.match(
		page,
		/let showActivityFiller = \$derived\(keyStats\.length % 2 === 1/,
		'the parity filler counts the rendered list, not a hand-maintained total',
	);
	assert.doesNotMatch(
		page,
		/keyStatsCount/,
		'the hand-maintained count is gone — it had already drifted from the template',
	);
});

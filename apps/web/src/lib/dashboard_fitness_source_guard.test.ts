// Source-level guard pinning the single training-load source on the
// dashboard. The fitness-card CTL/ATL/TSB numbers, the recovery advice,
// and the readiness ring must all read the SAME training-load series the
// chart renders (`loadNow`, the final point of computeTrainingLoadSeries)
// — not computeSnapshot (fitness.ts), which uses a different EWMA and a
// different stress model. If a future edit re-splits the sources the
// advice can contradict the chart around the TSB threshold (round-5 pro).

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SOURCE = readFileSync(
	resolve('src/routes/dashboard/+page.svelte'),
	'utf-8',
);

test('dashboard derives loadNow from the training-load series', () => {
	assert.match(
		SOURCE,
		/let loadNow = \$derived\.by\(\(\) => \{[\s\S]*trainingLoadSeries/,
		'loadNow must be derived from trainingLoadSeries',
	);
});

test('recovery advice reads the training-load series, not computeSnapshot', () => {
	assert.match(
		SOURCE,
		/recoveryAdvice\(loadNow\?\.tsb/,
		'recoveryAdvice must be fed loadNow.tsb',
	);
	assert.doesNotMatch(
		SOURCE,
		/recoveryAdvice\(liveSnap\./,
		'recoveryAdvice must not read liveSnap (computeSnapshot) any more',
	);
});

test('readiness ring reads the training-load series', () => {
	assert.match(
		SOURCE,
		/computeReadiness\(\{ tsb: loadNow\?\.tsb/,
		'readiness must be fed loadNow.tsb',
	);
});

test('the CTL/ATL/TSB card numbers read loadNow, not liveSnap', () => {
	assert.match(SOURCE, /loadNow\.ctl\.toFixed/, 'CTL must read loadNow');
	assert.match(SOURCE, /loadNow\.atl\.toFixed/, 'ATL must read loadNow');
	assert.match(SOURCE, /loadNow\.tsb\.toFixed/, 'TSB must read loadNow');
	assert.doesNotMatch(
		SOURCE,
		/liveSnap\.(chronicLoad|acuteLoad|trainingStressBal)\.toFixed/,
		'the load numbers must not read liveSnap any more',
	);
});

// --- Cross-modality wiring (multi_modal.md § Lift training-load spec) ---
//
// The training-load series the whole readiness block reads MUST be fed
// real gym lifts, and that feed MUST stay separable so a future
// exclude_gym_from_readiness toggle can drop lifts cleanly and leave the
// run-only curve byte-for-byte recoverable. Pin the three links in that
// chain so a refactor can't silently sever cross-modality (lifts stop
// counting) or its opt-out (lifts can't be dropped).

test('the training-load series is fed real gym lifts (cross-modality is wired)', () => {
	assert.match(
		SOURCE,
		/computeTrainingLoadSeries\([\s\S]*?readinessLifts\s*\)/,
		'computeTrainingLoadSeries must receive readinessLifts as its lifts arg',
	);
	assert.match(
		SOURCE,
		/let lifts = \$derived\(liftsFromSetHistory\(/,
		'lifts must derive from real gym set history via liftsFromSetHistory',
	);
});

test('readinessLifts honours the exclude_gym_from_readiness opt-out', () => {
	assert.match(
		SOURCE,
		/let readinessLifts = \$derived\(\s*excludeGymFromReadiness \? \[\] : lifts\s*\)/,
		'readinessLifts must drop to [] when excludeGymFromReadiness is set',
	);
	assert.match(
		SOURCE,
		/excludeGymFromReadiness = effective<boolean>\(settings, 'exclude_gym_from_readiness'\)/,
		'the opt-out must read the exclude_gym_from_readiness setting',
	);
});

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

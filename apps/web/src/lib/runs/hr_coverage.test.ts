import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { hrCoveragePercent } from './hr_coverage';

test('hrCoveragePercent — rounds a fraction to whole percent', () => {
	assert.equal(hrCoveragePercent(1), 100);
	assert.equal(hrCoveragePercent(0.5), 50);
	assert.equal(hrCoveragePercent(0.12), 12);
	assert.equal(hrCoveragePercent(0.125), 13);
	assert.equal(hrCoveragePercent(0.124), 12);
});

test('hrCoveragePercent — zero is a measurement, not an absence', () => {
	// The Wear recorder writes 0 whenever HR was ENABLED and delivered
	// nothing, which is a different fact from the key being missing.
	assert.equal(hrCoveragePercent(0), 0);
});

test('hrCoveragePercent — a nonzero coverage never renders as 0 %', () => {
	// 0 is reserved for "the sensor was on and delivered nothing". A coverage
	// too small to round to 1 % must not borrow that sentence.
	assert.equal(hrCoveragePercent(0.004), 1);
	assert.equal(hrCoveragePercent(0.0001), 1);
});

test('hrCoveragePercent — 100 is the ceiling, not a rounding artefact', () => {
	assert.equal(hrCoveragePercent(0.999), 100);
	assert.equal(hrCoveragePercent(0.996), 100);
});

test('hrCoveragePercent — an absent or unusable value claims nothing', () => {
	// Absent is UNMEASURED, not zero: a run from a build predating the field
	// must keep the old "no heart-rate data" copy rather than be reported as
	// a sensor that ran for none of it.
	assert.equal(hrCoveragePercent(undefined), null);
	assert.equal(hrCoveragePercent(null), null);
	assert.equal(hrCoveragePercent('0.5'), null);
	assert.equal(hrCoveragePercent(NaN), null);
	assert.equal(hrCoveragePercent(Infinity), null);
	assert.equal(hrCoveragePercent(-Infinity), null);
	assert.equal(hrCoveragePercent({}), null);
});

test('hrCoveragePercent — a value outside the fraction contract is refused', () => {
	// A percentage written into the key by a future non-conforming writer
	// would otherwise render as "covered 8500% of this run".
	assert.equal(hrCoveragePercent(85), null);
	assert.equal(hrCoveragePercent(1.01), null);
	assert.equal(hrCoveragePercent(-0.1), null);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { paceMinutesSeconds, paceParts } from './pace_format';

test('formats whole and exact paces', () => {
	assert.equal(paceMinutesSeconds(330), '5:30');
	assert.equal(paceMinutesSeconds(305), '5:05');
	assert.equal(paceMinutesSeconds(0), '0:00');
	assert.equal(paceMinutesSeconds(59), '0:59');
	assert.equal(paceMinutesSeconds(60), '1:00');
});

test('never emits a ":60" seconds field for a fractional input', () => {
	// The bug this guards: independent floor(min) + round(sec) produced
	// "4:60" for 299.6 instead of rolling over to "5:00".
	assert.equal(paceMinutesSeconds(299.6), '5:00');
	assert.equal(paceMinutesSeconds(359.7), '6:00');
	assert.equal(paceMinutesSeconds(119.6), '2:00');
	for (const x of [59.5, 119.6, 179.8, 299.6, 359.7, 599.9]) {
		const out = paceMinutesSeconds(x);
		assert.ok(!/:60$/.test(out), `${x} produced malformed ${out}`);
	}
});

test('rounds to the nearest whole second', () => {
	assert.equal(paceMinutesSeconds(330.4), '5:30');
	assert.equal(paceMinutesSeconds(330.5), '5:31');
});

test('paceParts keeps seconds in 0-59 after rollover', () => {
	assert.deepEqual(paceParts(330), { minutes: 5, seconds: 30 });
	assert.deepEqual(paceParts(299.6), { minutes: 5, seconds: 0 });
	assert.deepEqual(paceParts(359.7), { minutes: 6, seconds: 0 });
	for (const x of [59.5, 119.6, 299.6, 359.7, 599.9]) {
		assert.ok(paceParts(x).seconds <= 59, `${x} produced seconds > 59`);
	}
});

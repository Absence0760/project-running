import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fundraiserProgress } from './fundraiser_progress';

test('zero raised is starting, empty bar, full remaining', () => {
	const p = fundraiserProgress(0, 100000);
	assert.equal(p.fillPct, 0);
	assert.equal(p.rawPct, 0);
	assert.equal(p.remainingCents, 100000);
	assert.equal(p.state, 'starting');
});

test('below 10% is starting', () => {
	const p = fundraiserProgress(5000, 100000);
	assert.equal(p.rawPct, 5);
	assert.equal(p.state, 'starting');
});

test('at the 10% threshold flips to progressing', () => {
	const p = fundraiserProgress(10000, 100000);
	assert.equal(p.rawPct, 10);
	assert.equal(p.state, 'progressing');
});

test('mid progress reports remaining + progressing', () => {
	const p = fundraiserProgress(60000, 100000);
	assert.equal(p.fillPct, 60);
	assert.equal(p.remainingCents, 40000);
	assert.equal(p.state, 'progressing');
});

test('exactly at goal is met, no remaining, full bar', () => {
	const p = fundraiserProgress(100000, 100000);
	assert.equal(p.fillPct, 100);
	assert.equal(p.rawPct, 100);
	assert.equal(p.remainingCents, 0);
	assert.equal(p.state, 'met');
});

test('over goal is exceeded, fill clamps to 100, rawPct uncapped', () => {
	const p = fundraiserProgress(118000, 100000);
	assert.equal(p.fillPct, 100);
	assert.equal(p.rawPct, 118);
	assert.equal(p.remainingCents, 0);
	assert.equal(p.state, 'exceeded');
});

test('zero goal yields a safe zeroed starting result (no divide-by-zero)', () => {
	const p = fundraiserProgress(5000, 0);
	assert.equal(p.fillPct, 0);
	assert.equal(p.rawPct, 0);
	assert.equal(p.remainingCents, 0);
	assert.equal(p.state, 'starting');
});

test('negative goal is treated as no goal', () => {
	const p = fundraiserProgress(5000, -100);
	assert.equal(p.state, 'starting');
	assert.equal(p.rawPct, 0);
});

test('negative raised floors to zero', () => {
	const p = fundraiserProgress(-500, 100000);
	assert.equal(p.fillPct, 0);
	assert.equal(p.remainingCents, 100000);
	assert.equal(p.state, 'starting');
});

test('non-finite raised is treated as zero', () => {
	const p = fundraiserProgress(Number.NaN, 100000);
	assert.equal(p.rawPct, 0);
	assert.equal(p.state, 'starting');
});

test('fractional percentage is preserved in rawPct', () => {
	const p = fundraiserProgress(12345, 100000);
	assert.equal(p.rawPct, 12.345);
	assert.equal(p.state, 'progressing');
});

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { computeReadiness } from './readiness';

test('neutral inputs → 75 baseline, moderate band', () => {
	const r = computeReadiness({ tsb: 0 });
	assert.equal(r.score, 75);
	assert.equal(r.band, 'high');
	assert.equal(r.contributors.length, 1);
});

test('all inputs null → 75 baseline, no contributors', () => {
	const r = computeReadiness({ tsb: null });
	assert.equal(r.score, 75);
	assert.equal(r.contributors.length, 0);
	// Advice is band-driven when no signals are available — 75 is the
	// "high" band, so we surface the encouraging variant.
	assert.match(r.advice, /good day|push the pace/i);
});

test('heavy fatigue + bad sleep → low band', () => {
	const r = computeReadiness({ tsb: -25, sleepHours: 4 });
	// -20 (TSB) + -25 (sleep) = -45 → 75 - 45 = 30 → low.
	assert.equal(r.score, 30);
	assert.equal(r.band, 'low');
	assert.match(r.advice, /easy|rest/i);
});

test('fresh + great sleep → high band', () => {
	const r = computeReadiness({
		tsb: 10,
		sleepHours: 8.5,
		restingHrBpm: 55,
		baselineRestingHrBpm: 58,
	});
	// 75 + 8 (fresh) + 5 (great sleep) + 3 (HR below baseline) = 91.
	assert.equal(r.score, 91);
	assert.equal(r.band, 'high');
	assert.match(r.advice, /harder effort/);
});

test('clamps to 0..100 on extreme inputs', () => {
	const low = computeReadiness({
		tsb: -50,
		sleepHours: 2,
		restingHrBpm: 100,
		baselineRestingHrBpm: 55,
	});
	assert.equal(low.score, 12);
	assert.equal(low.band, 'low');

	const high = computeReadiness({
		tsb: 10,
		sleepHours: 8,
		restingHrBpm: 50,
		baselineRestingHrBpm: 55,
	});
	assert.ok(high.score >= 75 && high.score <= 100);
});

test('TSB > +25 (over-tapered) → small negative not positive', () => {
	const r = computeReadiness({ tsb: 30 });
	assert.equal(r.score, 75 - 3);
	const tsb = r.contributors.find((c) => c.name === 'Form (TSB)');
	assert.equal(tsb!.delta, -3);
	assert.match(tsb!.note, /Over-tapered/);
});

test('resting HR +10 above baseline → strong negative', () => {
	const r = computeReadiness({
		tsb: 0,
		restingHrBpm: 70,
		baselineRestingHrBpm: 58,
	});
	// 12 above → "Very above baseline" band, -18.
	assert.equal(r.score, 75 - 18);
	assert.equal(r.band, 'moderate');
	assert.match(r.advice, /illness|under-recovery/i);
});

test('contributor ordering: dominant input drives the advice line', () => {
	// Big sleep deficit dominates a mild TSB.
	const r = computeReadiness({ tsb: -3, sleepHours: 4 });
	// Sleep contributor (-25) beats TSB (-6).
	assert.match(r.advice, /Very little sleep|compromised/i);
});

test('partial inputs — only sleep present', () => {
	const r = computeReadiness({ tsb: null, sleepHours: 8.5 });
	// Baseline 75 + sleep +5 = 80, high band.
	assert.equal(r.score, 80);
	assert.equal(r.band, 'high');
	assert.equal(r.contributors.length, 1);
});

test('band thresholds: 40 = moderate boundary, 70 = high boundary', () => {
	// Neutral TSB → 75 → high band.
	assert.equal(computeReadiness({ tsb: 0 }).band, 'high');
	// Slight fatigue → 75-6=69 → moderate.
	assert.equal(computeReadiness({ tsb: -10 }).band, 'moderate');
	// Heavy fatigue → 75-20=55 → still moderate (>= 40).
	assert.equal(computeReadiness({ tsb: -25 }).band, 'moderate');
	// Heavy fatigue + bad sleep → 75-20-25=30 → low.
	assert.equal(computeReadiness({ tsb: -25, sleepHours: 3 }).band, 'low');
});

test('score is deterministic — same inputs → same output', () => {
	const a = computeReadiness({ tsb: 5, sleepHours: 7 });
	const b = computeReadiness({ tsb: 5, sleepHours: 7 });
	assert.equal(a.score, b.score);
	assert.equal(a.band, b.band);
	assert.equal(a.advice, b.advice);
});

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { rotationPick, type RotationMember } from './rotation_pick';

function member(over: Partial<RotationMember> & { id: string }): RotationMember {
	return {
		totalDistanceM: 0,
		targetDistanceM: 800_000,
		retiredAt: null,
		isCurrent: false,
		...over,
	};
}

test('rotationPick: empty rotation picks nothing and claims nothing', () => {
	const p = rotationPick([]);
	assert.deepEqual(p, { ranked: [], pickId: null, pickIsCurrent: false, allWorn: false });
});

test('rotationPick: least-worn pair comes out next', () => {
	const p = rotationPick([
		member({ id: 'a', totalDistanceM: 600_000 }),
		member({ id: 'b', totalDistanceM: 100_000 }),
		member({ id: 'c', totalDistanceM: 350_000 }),
	]);
	assert.equal(p.pickId, 'b');
	assert.deepEqual(
		p.ranked.map((r) => r.id),
		['b', 'c', 'a'],
	);
	assert.equal(p.allWorn, false);
});

test('rotationPick: shares are relative, not absolute — a big-target pair can lead on more km', () => {
	const p = rotationPick([
		member({ id: 'road', totalDistanceM: 300_000, targetDistanceM: 500_000 }),
		member({ id: 'trail', totalDistanceM: 400_000, targetDistanceM: 1_000_000 }),
	]);
	assert.equal(p.pickId, 'trail');
});

test('rotationPick: retired gear is dropped, not ranked last', () => {
	const p = rotationPick([
		member({ id: 'retired', totalDistanceM: 0, retiredAt: '2026-01-01' }),
		member({ id: 'live', totalDistanceM: 500_000 }),
	]);
	assert.deepEqual(
		p.ranked.map((r) => r.id),
		['live'],
	);
	assert.equal(p.pickId, 'live');
});

test('rotationPick: an all-retired rotation picks nothing', () => {
	const p = rotationPick([
		member({ id: 'a', retiredAt: '2026-01-01' }),
		member({ id: 'b', retiredAt: '2026-02-01' }),
	]);
	assert.equal(p.pickId, null);
	assert.equal(p.allWorn, false);
});

test('rotationPick: a worn pair sorts behind every unworn pair even on a lower share', () => {
	// The worn pair carries the LOWER share of the two, because the untracked
	// pair is measured against a reference target far below its mileage.
	// Recommending the worn one anyway would tell the runner to wear a shoe the
	// app itself flags for replacement.
	const p = rotationPick([
		member({ id: 'worn', totalDistanceM: 110_000, targetDistanceM: 100_000 }),
		member({ id: 'untracked', totalDistanceM: 500_000, targetDistanceM: null }),
	]);
	assert.ok(p.ranked[0].share > p.ranked[1].share);
	assert.equal(p.ranked[0].id, 'untracked');
	assert.equal(p.ranked[1].status, 'worn');
	assert.equal(p.pickId, 'untracked');
});

test('rotationPick: a worn pair really does sort last', () => {
	const p = rotationPick([
		member({ id: 'worn', totalDistanceM: 900_000 }),
		member({ id: 'due', totalDistanceM: 700_000 }),
		member({ id: 'ok', totalDistanceM: 200_000 }),
	]);
	assert.deepEqual(
		p.ranked.map((r) => r.id),
		['ok', 'due', 'worn'],
	);
});

test('rotationPick: every pair worn is reported, and the pick is still the least-worn', () => {
	const p = rotationPick([
		member({ id: 'a', totalDistanceM: 1_200_000 }),
		member({ id: 'b', totalDistanceM: 850_000 }),
	]);
	assert.equal(p.allWorn, true);
	assert.equal(p.pickId, 'b');
});

test('rotationPick: an untracked pair is measured against the rotation median, not dropped', () => {
	const p = rotationPick([
		member({ id: 'tracked', totalDistanceM: 400_000, targetDistanceM: 800_000 }),
		member({ id: 'untracked', totalDistanceM: 100_000, targetDistanceM: null }),
	]);
	assert.equal(p.pickId, 'untracked');
	assert.equal(p.ranked.find((r) => r.id === 'untracked')?.status, 'untracked');
	// 100k against the single tracked target of 800k.
	assert.ok(Math.abs((p.ranked[0]?.share ?? 0) - 0.125) < 1e-9);
});

test('rotationPick: an untracked pair is never called worn, however far it has run', () => {
	const p = rotationPick([
		member({ id: 'untracked', totalDistanceM: 5_000_000, targetDistanceM: null }),
		member({ id: 'tracked', totalDistanceM: 10_000, targetDistanceM: 800_000 }),
	]);
	assert.equal(p.ranked.find((r) => r.id === 'untracked')?.status, 'untracked');
	assert.equal(p.allWorn, false);
	assert.equal(p.pickId, 'tracked');
});

test('rotationPick: with no tracked pair at all the ranking falls back to raw distance', () => {
	const p = rotationPick([
		member({ id: 'a', totalDistanceM: 300_000, targetDistanceM: null }),
		member({ id: 'b', totalDistanceM: 90_000, targetDistanceM: null }),
	]);
	assert.equal(p.pickId, 'b');
	assert.equal(p.allWorn, false);
});

test('rotationPick: the reference target is the median, so one outlier target cannot swing it', () => {
	// Medians of [200k, 400k, 5_000k] → 400k. A mean would be ~1_866k and would
	// rank the untracked pair below both tracked ones instead of above them.
	const p = rotationPick([
		member({ id: 'short', totalDistanceM: 100_000, targetDistanceM: 200_000 }),
		member({ id: 'mid', totalDistanceM: 200_000, targetDistanceM: 400_000 }),
		member({ id: 'long', totalDistanceM: 2_500_000, targetDistanceM: 5_000_000 }),
		member({ id: 'untracked', totalDistanceM: 40_000, targetDistanceM: null }),
	]);
	assert.equal(p.pickId, 'untracked');
	assert.ok(Math.abs((p.ranked[0]?.share ?? 0) - 0.1) < 1e-9);
});

test('rotationPick: negative / non-finite distances clamp to zero rather than sorting first by accident', () => {
	const p = rotationPick([
		member({ id: 'bad', totalDistanceM: Number.NaN }),
		member({ id: 'worse', totalDistanceM: -50_000 }),
		member({ id: 'real', totalDistanceM: 10_000 }),
	]);
	assert.deepEqual(
		p.ranked.map((r) => r.id),
		['bad', 'worse', 'real'],
	);
	assert.equal(p.ranked[0].share, 0);
	assert.equal(p.ranked[1].share, 0);
});

test('rotationPick: ties break on id so the same rotation never reorders between renders', () => {
	const first = rotationPick([
		member({ id: 'zebra', totalDistanceM: 200_000 }),
		member({ id: 'alpha', totalDistanceM: 200_000 }),
	]);
	const second = rotationPick([
		member({ id: 'alpha', totalDistanceM: 200_000 }),
		member({ id: 'zebra', totalDistanceM: 200_000 }),
	]);
	assert.equal(first.pickId, 'alpha');
	assert.deepEqual(
		first.ranked.map((r) => r.id),
		second.ranked.map((r) => r.id),
	);
});

test('rotationPick: the current pair is reported when it is also the pick', () => {
	const p = rotationPick([
		member({ id: 'a', totalDistanceM: 100_000, isCurrent: true }),
		member({ id: 'b', totalDistanceM: 400_000 }),
	]);
	assert.equal(p.pickId, 'a');
	assert.equal(p.pickIsCurrent, true);
});

test('rotationPick: the current pair holds no rank advantage', () => {
	const p = rotationPick([
		member({ id: 'a', totalDistanceM: 400_000, isCurrent: true }),
		member({ id: 'b', totalDistanceM: 100_000 }),
	]);
	assert.equal(p.pickId, 'b');
	assert.equal(p.pickIsCurrent, false);
	assert.equal(p.ranked.find((r) => r.id === 'a')?.isCurrent, true);
});

test('rotationPick: ranked.length is the in-service count, so a caller can gate on it', () => {
	// The affordance on /settings/gear renders only when there is a real choice
	// to make. Counting memberships would offer a "wear this next" for a
	// rotation holding one live pair and one retired one; ranked drops the
	// retired member, so it is the count that answers the question.
	const p = rotationPick([
		member({ id: 'live', totalDistanceM: 100_000 }),
		member({ id: 'retired', totalDistanceM: 0, retiredAt: '2026-01-01' }),
	]);
	assert.equal(p.ranked.length, 1);
	assert.equal(p.pickId, 'live');
});

test('rotationPick: a single-member rotation still answers, and answers with that member', () => {
	const p = rotationPick([member({ id: 'only', totalDistanceM: 900_000 })]);
	assert.equal(p.pickId, 'only');
	assert.equal(p.allWorn, true);
});

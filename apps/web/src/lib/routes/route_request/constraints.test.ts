// Unit tests for the AI route-request constraint validator/clamp — the
// single trust boundary between the LLM's raw tool output and the
// deterministic generator. Run via
// `npx tsx --test apps/web/src/lib/routes/route_request/constraints.test.ts`.
//
// The model's numbers are never trusted: these tests pin that a
// malicious / oversized / missing / wrong-typed field collapses to a safe
// default and is recorded in `assumptions`, and that an in-band field
// passes through unchanged.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	clampDistance,
	validateConstraints,
	DEFAULT_REQUEST_DISTANCE_M,
	MIN_REQUEST_DISTANCE_M,
	MAX_REQUEST_DISTANCE_M,
} from './constraints';

test('clampDistance: in-band value passes through (rounded)', () => {
	assert.equal(clampDistance(10000), 10000);
	assert.equal(clampDistance(5234.7), 5235);
});

test('clampDistance: oversized value clamps to the request ceiling', () => {
	assert.equal(clampDistance(500_000), MAX_REQUEST_DISTANCE_M);
	assert.equal(clampDistance(999_999_999), MAX_REQUEST_DISTANCE_M);
});

test('clampDistance: tiny value floors to the request minimum', () => {
	assert.equal(clampDistance(5), MIN_REQUEST_DISTANCE_M);
	assert.equal(clampDistance(1), MIN_REQUEST_DISTANCE_M);
});

test('clampDistance: garbage / non-finite / non-positive returns null', () => {
	assert.equal(clampDistance(undefined), null);
	assert.equal(clampDistance(null), null);
	assert.equal(clampDistance('not a number'), null);
	assert.equal(clampDistance(NaN), null);
	assert.equal(clampDistance(Infinity), null);
	assert.equal(clampDistance(0), null);
	assert.equal(clampDistance(-100), null);
});

test('validateConstraints: a fully-specified, in-band object passes through with no assumptions', () => {
	const c = validateConstraints({
		distance_m: 10000,
		shape: 'out_and_back',
		surface: 'trail',
		avoid_highways: true,
		preference: 'scenic',
	});
	assert.equal(c.distanceM, 10000);
	assert.equal(c.shape, 'out_and_back');
	assert.equal(c.surface, 'trail');
	assert.equal(c.avoidHighways, true);
	assert.equal(c.preference, 'scenic');
	assert.deepEqual(c.assumptions, []);
});

test('validateConstraints: empty object falls back to all documented defaults', () => {
	const c = validateConstraints({});
	assert.equal(c.distanceM, DEFAULT_REQUEST_DISTANCE_M);
	assert.equal(c.shape, 'loop');
	assert.equal(c.surface, 'road');
	assert.equal(c.avoidHighways, false);
	assert.equal(c.preference, null);
	assert.deepEqual(
		c.assumptions.sort(),
		['avoid_highways', 'distance', 'shape', 'surface'],
	);
});

test('validateConstraints: non-object input is treated as empty (never throws)', () => {
	for (const bad of [null, undefined, 'string', 42, []]) {
		const c = validateConstraints(bad as unknown);
		assert.equal(c.distanceM, DEFAULT_REQUEST_DISTANCE_M);
		assert.equal(c.shape, 'loop');
	}
});

test('validateConstraints: hostile enum values are dropped to defaults, not executed', () => {
	const c = validateConstraints({
		shape: 'rm -rf /',
		surface: '"><script>',
		avoid_highways: 'yes please', // not a boolean
		distance_m: '10000; DROP TABLE routes',
	});
	assert.equal(c.shape, 'loop');
	assert.equal(c.surface, 'road');
	assert.equal(c.avoidHighways, false);
	// "10000; DROP TABLE routes" → Number(...) is NaN → distance assumed.
	assert.equal(c.distanceM, DEFAULT_REQUEST_DISTANCE_M);
	assert.ok(c.assumptions.includes('shape'));
	assert.ok(c.assumptions.includes('surface'));
	assert.ok(c.assumptions.includes('avoid_highways'));
	assert.ok(c.assumptions.includes('distance'));
});

test('validateConstraints: oversized distance is clamped, not assumed (no distance assumption)', () => {
	const c = validateConstraints({ distance_m: 9_999_999 });
	assert.equal(c.distanceM, MAX_REQUEST_DISTANCE_M);
	assert.ok(!c.assumptions.includes('distance'));
});

test('validateConstraints: a numeric-string distance coerces and clamps', () => {
	// Number("12000") === 12000 — a clean numeric string is honoured.
	const c = validateConstraints({ distance_m: '12000' });
	assert.equal(c.distanceM, 12000);
	assert.ok(!c.assumptions.includes('distance'));
});

test('validateConstraints: partial object only assumes the missing fields', () => {
	const c = validateConstraints({ distance_m: 8000, avoid_highways: true });
	assert.equal(c.distanceM, 8000);
	assert.equal(c.avoidHighways, true);
	assert.equal(c.shape, 'loop');
	assert.equal(c.surface, 'road');
	// avoid_highways derives the quiet preference, which is itself an assumption.
	assert.deepEqual(c.assumptions.sort(), ['preference', 'shape', 'surface']);
});

test('validateConstraints: every accepted preference passes through unchanged', () => {
	for (const p of ['quiet', 'scenic', 'cul_de_sac']) {
		const c = validateConstraints({ preference: p });
		assert.equal(c.preference, p);
		assert.ok(!c.assumptions.includes('preference'));
	}
});

test('validateConstraints: an unknown preference token is dropped, never forwarded', () => {
	for (const bad of ['hilly', 'QUIET', 'cul-de-sac', '', 42, null, {}]) {
		const c = validateConstraints({ preference: bad });
		assert.equal(c.preference, null);
		assert.ok(!c.assumptions.includes('preference'));
	}
});

test('validateConstraints: avoid_highways derives quiet and records the assumption', () => {
	const c = validateConstraints({ avoid_highways: true });
	assert.equal(c.preference, 'quiet');
	// The existing knob survives beside the derived one — the generate body
	// still carries avoidHighways for the form's own toggle.
	assert.equal(c.avoidHighways, true);
	assert.ok(c.assumptions.includes('preference'));
});

test('validateConstraints: a trail surface derives scenic and records the assumption', () => {
	const c = validateConstraints({ surface: 'trail' });
	assert.equal(c.preference, 'scenic');
	assert.ok(c.assumptions.includes('preference'));
});

test('validateConstraints: an explicit preference beats both derivations', () => {
	const c = validateConstraints({
		preference: 'cul_de_sac',
		avoid_highways: true,
		surface: 'trail',
	});
	assert.equal(c.preference, 'cul_de_sac');
	assert.ok(!c.assumptions.includes('preference'));
});

test('validateConstraints: an unknown preference still falls through to the derivation', () => {
	const c = validateConstraints({ preference: 'hilly', avoid_highways: true });
	assert.equal(c.preference, 'quiet');
	assert.ok(c.assumptions.includes('preference'));
});

test('validateConstraints: the stated road constraint outranks the surface inference', () => {
	const c = validateConstraints({ avoid_highways: true, surface: 'trail' });
	assert.equal(c.preference, 'quiet');
});

test('validateConstraints: cul_de_sac is never derived, only asked for', () => {
	// It inverts part of the loop score — a runner who did not ask for dead-end
	// spurs must never be given a route built out of them.
	for (const raw of [
		{},
		{ avoid_highways: true },
		{ surface: 'trail' },
		{ surface: 'road', avoid_highways: false },
		{ shape: 'out_and_back', distance_m: 5000 },
	]) {
		assert.notEqual(validateConstraints(raw).preference, 'cul_de_sac');
	}
});

test('validateConstraints: a request naming neither road nor trail assumes no preference', () => {
	const c = validateConstraints({ distance_m: 5000, surface: 'mixed', avoid_highways: false });
	assert.equal(c.preference, null);
	assert.ok(!c.assumptions.includes('preference'));
});

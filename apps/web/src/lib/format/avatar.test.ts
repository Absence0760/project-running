import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	initial,
	hashHue,
	seedBackground,
	seedContrast,
	seedForeground,
	seedLightness,
	SEED_INK,
	SEED_ON_LIGHT,
} from './avatar';

test('initial — first non-whitespace char, uppercased', () => {
	assert.equal(initial('jared'), 'J');
	assert.equal(initial('  morgan'), 'M');
	assert.equal(initial('évie'), 'É');
});

test('initial — fallback to ? for empty/whitespace/nullish', () => {
	assert.equal(initial(null), '?');
	assert.equal(initial(undefined), '?');
	assert.equal(initial(''), '?');
	assert.equal(initial('   '), '?');
});

test('hashHue — deterministic and in [0, 360)', () => {
	const h = hashHue('a1b2c3d4-user');
	assert.equal(h, hashHue('a1b2c3d4-user'));
	assert.ok(Number.isInteger(h) && h >= 0 && h < 360);
	assert.ok(hashHue('') >= 0);
});

// The identity-avatar contrast clamp (decisions § 481; ported from mobile's
// identity_avatar.dart). The property that matters is not any single hue but
// that EVERY hue's chosen foreground clears AA, so the suite sweeps all 360
// rather than sampling — which is how the unclamped version passed review while
// failing on 297 of them.
test('seed foreground clears WCAG AA over every hue', () => {
	for (let hue = 0; hue < 360; hue++) {
		assert.ok(
			seedContrast(hue) >= 4.5,
			`hue ${hue}: ${seedForeground(hue)} on ${seedBackground(hue)} is ${seedContrast(hue).toFixed(3)}:1`,
		);
	}
});

test('seed clamp leaves a legible hue at its historical lightness', () => {
	// The clamp only moves a hue stuck in the band where NEITHER foreground
	// reaches AA. Yellow (60) is already 9.7:1 under ink and must not move.
	assert.equal(seedLightness(60), 55, 'yellow is legible under ink and keeps 55%');
	assert.equal(seedLightness(240), 55, 'blue is legible under white and keeps 55%');
	// The band is FOUR arcs, not one — reds/magentas plus a narrow blue-violet
	// notch at 216-222 where the crossover between the two inks lands. Pinning
	// the runs rather than a rough range is what stops a "tidy the range" edit
	// from silently dropping the notch.
	const moved = [...Array(360).keys()].filter((h) => seedLightness(h) !== 55);
	const runs: Array<[number, number]> = [];
	for (const h of moved) {
		const last = runs.at(-1);
		if (last && last[1] === h - 1) last[1] = h;
		else runs.push([h, h]);
	}
	assert.deepEqual(runs, [[0, 9], [216, 222], [284, 298], [306, 359]]);
	assert.equal(moved.length, 86);
});

test('seed foreground is picked by contrast, not fixed', () => {
	// A fixed white was the defect: it fails on the warm half of the wheel.
	assert.equal(seedForeground(240), SEED_ON_LIGHT, 'blue takes white');
	assert.equal(seedForeground(60), SEED_INK, 'yellow takes ink');
	const inked = [...Array(360).keys()].filter((h) => seedForeground(h) === SEED_INK);
	assert.equal(inked.length, 256, 'most of the wheel needs the dark ink');
});

test('seedBackground is a deterministic hsl() string at the house saturation', () => {
	assert.equal(seedBackground(60), 'hsl(60, 50%, 55%)');
	assert.equal(seedBackground(316), `hsl(316, 50%, ${seedLightness(316)}%)`);
	assert.equal(seedBackground(200), seedBackground(200));
});

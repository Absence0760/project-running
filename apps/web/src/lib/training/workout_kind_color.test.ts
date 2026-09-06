// The web half of the `workout_kind_color` parity pair. The Dart mirror is
// `apps/mobile_android/test/workout_kind_color_test.dart`, which additionally
// computes the WCAG floors against the real palette — the colour VALUES are not
// part of the pair (they live in `app.css` and `ChartPalette.kinds`, asserted by
// `contrast_guard.test.ts`). What IS the pair is the GROUPING: nine kinds
// collapse onto six marks, and a kind that moves group on one platform gives
// the same plan two different calendars.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import type { WorkoutKind } from './training';
import { workoutKindMarkIndex, workoutKindMarkVar } from './workout_kind_color';

const KINDS: WorkoutKind[] = [
	'easy',
	'long',
	'recovery',
	'tempo',
	'interval',
	'marathon_pace',
	'walk_run',
	'race',
	'rest'
];

const SCALE = 6;

test('every kind maps into the scale, and the nine collapse to six', () => {
	const indices = new Map(KINDS.map((k) => [k, workoutKindMarkIndex(k)]));
	for (const [kind, index] of indices) {
		assert.ok(index >= 1 && index <= SCALE, `${kind} maps outside the scale at ${index}`);
	}
	assert.equal(new Set(indices.values()).size, SCALE);
});

// The groups are the contract. Mirrors the Dart suite's own assertion, offset
// by one because web indexes a CSS custom-property name and Dart a list.
test('kinds sharing a mark are the documented groups', () => {
	const byIndex = new Map<number, WorkoutKind[]>();
	for (const kind of KINDS) {
		const i = workoutKindMarkIndex(kind);
		byIndex.set(i, [...(byIndex.get(i) ?? []), kind]);
	}
	assert.deepEqual(byIndex.get(1), ['easy', 'recovery']);
	assert.deepEqual(byIndex.get(2), ['long', 'race']);
	assert.deepEqual(byIndex.get(3), ['tempo']);
	assert.deepEqual(byIndex.get(4), ['marathon_pace']);
	assert.deepEqual(byIndex.get(5), ['interval', 'walk_run']);
	assert.deepEqual(byIndex.get(6), ['rest']);
});

// Web takes a `string` where Dart takes an exhaustive enum, so web alone has an
// unknown-kind branch. It falls to the quietest mark rather than to a text
// token, which would reintroduce the tinted label the pair exists to remove.
test('an unknown kind falls to the rest mark, not to a text token', () => {
	assert.equal(workoutKindMarkIndex('not_a_kind'), workoutKindMarkIndex('rest'));
});

test('the mark resolves to a scale custom property', () => {
	for (const kind of KINDS) {
		assert.equal(workoutKindMarkVar(kind), `var(--kind-${workoutKindMarkIndex(kind)})`);
	}
});

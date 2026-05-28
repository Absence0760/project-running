import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	ONBOARDING_TOTAL_STEPS,
	PRIMARY_GOAL_KEY,
	PRIMARY_GOAL_LABELS,
	PRIMARY_GOAL_VALUES,
} from './onboarding';

test('PRIMARY_GOAL_KEY is the universal-prefs bag key the wizard writes', () => {
	// Hard-coded by name across the wizard, the Settings nudge, and
	// (eventually) the post-onboarding plan-suggestion surface. A
	// rename here without grepping every consumer would silently
	// orphan the saved value.
	assert.equal(PRIMARY_GOAL_KEY, 'primary_goal');
});

test('PRIMARY_GOAL_VALUES covers the fixed enum and every value has a label', () => {
	for (const v of PRIMARY_GOAL_VALUES) {
		assert.ok(
			PRIMARY_GOAL_LABELS[v],
			`PRIMARY_GOAL_VALUES contains "${v}" but PRIMARY_GOAL_LABELS has no label`,
		);
	}
	// Reverse direction — the label map can't drift past the enum
	// (a stale label without a value would render nowhere).
	for (const k of Object.keys(PRIMARY_GOAL_LABELS)) {
		assert.ok(
			(PRIMARY_GOAL_VALUES as readonly string[]).includes(k),
			`PRIMARY_GOAL_LABELS has "${k}" but PRIMARY_GOAL_VALUES does not`,
		);
	}
});

test('PRIMARY_GOAL_VALUES includes the four GoalEvent distances + 2 non-distance goals', () => {
	// The four distance goals map 1:1 to `training.ts#GoalEvent` so
	// a future plan-creation flow can translate without a mapping
	// table. Pin the membership explicitly.
	assert.ok((PRIMARY_GOAL_VALUES as readonly string[]).includes('5k'));
	assert.ok((PRIMARY_GOAL_VALUES as readonly string[]).includes('10k'));
	assert.ok((PRIMARY_GOAL_VALUES as readonly string[]).includes('half_marathon'));
	assert.ok((PRIMARY_GOAL_VALUES as readonly string[]).includes('marathon'));
	assert.ok((PRIMARY_GOAL_VALUES as readonly string[]).includes('general_fitness'));
	assert.ok((PRIMARY_GOAL_VALUES as readonly string[]).includes('weight_loss'));
	// And exactly those 6 — guards against a silent addition.
	assert.equal(PRIMARY_GOAL_VALUES.length, 6);
});

test('ONBOARDING_TOTAL_STEPS matches the wizard step count', () => {
	// Drives the progress-dot indicator. Drift would mean the user
	// sees "step 4 of 7" while there are 8 actual steps, or vice
	// versa. Pin the constant; the page-level test counts the
	// rendered <section> blocks.
	assert.equal(ONBOARDING_TOTAL_STEPS, 7);
});

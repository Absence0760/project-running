import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	ONBOARDING_TOTAL_STEPS,
	PRIMARY_GOAL_KEY,
	PRIMARY_GOAL_VALUES,
} from './onboarding';
import { en } from '../i18n/locales/en';

test('PRIMARY_GOAL_KEY is the universal-prefs bag key the wizard writes', () => {
	// Hard-coded by name across the wizard, the Settings nudge, and
	// (eventually) the post-onboarding plan-suggestion surface. A
	// rename here without grepping every consumer would silently
	// orphan the saved value.
	assert.equal(PRIMARY_GOAL_KEY, 'primary_goal');
});

test('every PRIMARY_GOAL_VALUE has a non-empty onboarding.goal i18n label', () => {
	// Labels are localized (key `onboarding.goal.<value>`), not held as
	// English strings in the helper. The wizard renders `m(...)` for
	// each value, so a value without a matching key would render the raw
	// key fallback. Pin the en catalogue (the canonical superset that
	// messages_parity.test.ts forces every other locale to mirror).
	const labels = en as Record<string, string>;
	for (const v of PRIMARY_GOAL_VALUES) {
		const key = `onboarding.goal.${v}`;
		assert.ok(
			labels[key] && labels[key].trim().length > 0,
			`PRIMARY_GOAL_VALUES contains "${v}" but en has no "${key}" label`,
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

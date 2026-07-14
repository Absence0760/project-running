// Source-level guard pinning the fail-closed + Art 9-consent gating on the
// cycle/pregnancy-aware plan-adjust feature (persona runner-woman, §231).
// These inputs are special-category reproductive-health data; two independent
// gates must survive a future edit:
//   1. the feature flag is fail-closed (unset/empty/"false" → off), and
//   2. the /settings/account write path is gated on BOTH the flag AND the
//      existing explicit health-data consent, nulling on withdrawal.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('cycle_plan_flag is fail-closed (defaults off)', () => {
	const source = read('src/lib/training/cycle_plan_flag.ts');
	assert.match(
		source,
		/PUBLIC_CYCLE_PLANS_ENABLED/,
		'flag must read PUBLIC_CYCLE_PLANS_ENABLED',
	);
	// Unset → '' → falsy: only explicit truthy strings enable it.
	assert.match(
		source,
		/raw === '1' \|\| raw === 'true' \|\| raw === 'yes' \|\| raw === 'on'/,
		'flag must enable only on explicit truthy values (fail-closed default)',
	);
});

test('account page gates cycle/pregnancy writes on the flag AND consent', () => {
	const source = read('src/routes/settings/account/+page.svelte');
	// Persistence must require both the flag and consent; the else branch must
	// null the keys when the flag is on but consent is off/withdrawn.
	assert.match(
		source,
		/if\s*\(cyclePlansEnabled\s*&&\s*healthDataConsent\)/,
		'cycle writes must require flag + consent',
	);
	assert.match(
		source,
		/prefs\.cycle_tracking_mode\s*=\s*null/,
		'cycle keys must be nulled on consent withdrawal / flag-off',
	);
});

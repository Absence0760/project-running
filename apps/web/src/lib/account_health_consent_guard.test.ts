// Source-level guard pinning the Art 9 health-data consent gate on the
// /settings/account page. The account page persists date_of_birth into
// user_settings.prefs (read by coach/context.ts). Before this gate it was
// an unguarded second write path that bypassed the consent flow enforced
// on /settings/preferences. If a future edit removes the gate, DOB starts
// persisting again without explicit consent — a GDPR Art 9 regression.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

const SOURCE = 'src/routes/settings/account/+page.svelte';

test('account page refuses to save DOB without health-data consent', () => {
	const source = read(SOURCE);
	assert.match(
		source,
		/if\s*\(dateOfBirth\s*&&\s*!healthDataConsent\)/,
		'DOB-without-consent guard missing',
	);
});

test('account page stamps consent via the SECURITY DEFINER RPC, not a direct write', () => {
	const source = read(SOURCE);
	assert.match(
		source,
		/supabase\.rpc\('grant_health_data_consent'\)/,
		'consent must be stamped through grant_health_data_consent',
	);
	// A direct client write of the timestamp is rejected by the lock
	// trigger — only the null (withdrawal) write is permitted directly.
	assert.doesNotMatch(
		source,
		/health_data_consent_at:\s*new Date\(/,
		'consent timestamp must not be client-stamped',
	);
});

test('account page only persists DOB to prefs when consented', () => {
	const source = read(SOURCE);
	assert.match(
		source,
		/prefs\.date_of_birth\s*=\s*healthDataConsent\s*&&\s*dateOfBirth\s*\?\s*dateOfBirth\s*:\s*null/,
		'DOB writeback to prefs must be consent-gated (null on withdrawal)',
	);
});

test('account page hydrates consent state from user_profiles on load', () => {
	const source = read(SOURCE);
	assert.match(
		source,
		/\.select\('health_data_consent_at'\)/,
		'page must read health_data_consent_at to pre-tick the box',
	);
});

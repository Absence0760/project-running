// Source-level guard pinning the Art 9 health-data consent gate on the
// /settings/account page. The account page persists date_of_birth into
// user_settings.prefs (read by coach/context.ts). Before this gate it was
// an unguarded second write path that bypassed the consent flow enforced
// on /settings/preferences. If a future edit removes the gate, DOB starts
// persisting again without explicit consent — a GDPR Art 9 regression.
//
// The gate is on the MIRROR, not on the field. `user_profiles.date_of_birth`
// is the age record behind the under-18 discoverability floor — a
// child-protection purpose written whenever the runner supplies a date
// (decisions § 718). The page used to abort the entire save on
// `dateOfBirth && !healthDataConsent`, which denied a non-consenting minor
// that record and deadlocked every other field on the page behind a DOB
// input the same condition disabled.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

const SOURCE = 'src/routes/settings/account/+page.svelte';

test('account page writes the DOB age record without a consent term', () => {
	const source = read(SOURCE);
	assert.match(
		source,
		/date_of_birth:\s*dateOfBirth\s*\|\|\s*null/,
		'ungated age-record writeback to user_profiles missing',
	);
	assert.doesNotMatch(
		source,
		/if\s*\(dateOfBirth\s*&&\s*!healthDataConsent\)/,
		'the whole-save abort is the deadlock § 718 removed — gate the mirror instead',
	);
});

test('account page re-asserts the age record after the withdrawal RPC', () => {
	// withdraw_health_data_consent() nulls user_profiles.date_of_birth
	// server-side. Ending the Art 9 processing does not end the child-safety
	// floor, so the profile write must run AFTER the RPC or a withdrawal
	// silently makes a declared minor name-searchable again.
	const source = read(SOURCE);
	const withdrawAt = source.indexOf("supabase.rpc(\n\t\t\t\t'withdraw_health_data_consent',");
	assert.ok(withdrawAt > 0, 'withdrawal RPC call not found');
	const profileWriteAt = source.indexOf('date_of_birth: dateOfBirth || null');
	assert.ok(profileWriteAt > 0, 'age-record writeback not found');
	assert.ok(
		profileWriteAt > withdrawAt,
		'the age-record write must follow the withdrawal RPC that nulls the column',
	);
});

test('account page does not consent-disable the DOB input', () => {
	// The field is the way into the age record. Disabling it on a withdrawn
	// consent leaves a runner unable to enter — or correct — a DOB at all.
	const source = read(SOURCE);
	const dobInput = source
		.split('\n')
		.find((l) => l.includes('bind:value={dateOfBirth}'));
	assert.ok(dobInput, 'DOB input not found');
	assert.doesNotMatch(dobInput!, /disabled=\{!healthDataConsent\}/, 'DOB input is consent-disabled');
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
	// health_data_consent_at is a deny-by-default column for direct
	// authenticated SELECTs (column lockdown, 20260707_001) — a direct
	// .select('health_data_consent_at') 403s, so the self-read goes through
	// the get_my_profile() RPC. Pin that path + the consent-state read.
	assert.match(
		source,
		/get_my_profile/,
		'page must self-read the profile via get_my_profile() (direct column select 403s)',
	);
	assert.match(
		source,
		/health_data_consent_at/,
		'page must read health_data_consent_at to pre-tick the box',
	);
});

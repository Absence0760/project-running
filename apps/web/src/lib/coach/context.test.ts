// Source-grep guards on context.ts. Run with
// `npx tsx --test apps/web/src/lib/coach/context.test.ts`.
//
// `buildContext` makes 5 Supabase RPC + table queries and can't be
// usefully unit-tested without spinning up a stack. Instead, pin the
// load-bearing audit-compliance invariants in the source so a future
// refactor that silently drops one fails CI rather than slipping
// through to production.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SRC = readFileSync(
	resolve(import.meta.dirname ?? '.', 'context.ts'),
	'utf8',
);

test('subscription_tier is NOT projected into the Anthropic context', () => {
	// audit/coach May 2026 Medium #9 — Art 5(1)(c) data minimisation.
	// The handler knows tier and adjusts limits server-side; sending
	// billing-tier metadata to a sub-processor has no functional
	// purpose. The profile projection must include display_name +
	// preferred_unit only (plus internal consent flags read off the
	// row but not emitted).
	const profileObj = SRC.match(/const profile = profileRowTyped[\s\S]*?\{([\s\S]*?)\}[\s\S]*?:\s*null;/);
	assert.ok(
		profileObj,
		'context.ts must expose a `profile` projection object',
	);
	assert.equal(
		profileObj![1].includes('subscription_tier'),
		false,
		'subscription_tier MUST NOT appear in the Anthropic-bound profile projection',
	);
});

test('DOB + HR metrics gated on health_data_consent_at', () => {
	// audit/coach May 2026 High #1 — GDPR Art 9(2)(a) explicit consent
	// for special-category health data. When `health_data_consent_at`
	// is null (or revoked), DOB / resting_hr_bpm / max_hr_bpm /
	// hr_zones MUST emit as null. The two-gate design is documented
	// in migration 20260921_001_user_profiles_gdpr_consent_timestamps.
	assert.match(
		SRC,
		/healthConsentGranted\s*=\s*profileRowTyped\?\.health_data_consent_at\s*!=\s*null/,
		'context.ts must derive healthConsentGranted from profile.health_data_consent_at',
	);
	for (const field of ['date_of_birth', 'resting_hr_bpm', 'max_hr_bpm', 'hr_zones']) {
		// Each health field must be wrapped in the conditional.
		const re = new RegExp(`${field}:\\s*healthConsentGranted\\s*\\?`);
		assert.match(
			SRC,
			re,
			`context.ts must gate \`${field}\` on healthConsentGranted (Art 9(2)(a))`,
		);
	}
});

test('runner_context never emits raw secrets (defence-in-depth)', () => {
	// Sentinel check: the prefs bag could grow to include sensitive
	// keys later (e.g. an OAuth token, a third-party API key). Any
	// known-secret name should never appear in the runner_context
	// payload. Add new names to this list if the prefs schema grows.
	const FORBIDDEN_PREFS = ['access_token', 'refresh_token', 'api_key', 'password'];
	for (const k of FORBIDDEN_PREFS) {
		assert.equal(
			new RegExp(`prefs\\.${k}`).test(SRC),
			false,
			`context.ts must NEVER project \`prefs.${k}\` into runner_context`,
		);
	}
});

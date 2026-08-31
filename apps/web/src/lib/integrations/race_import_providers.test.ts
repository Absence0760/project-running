import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
	RACE_IMPORT_LEGS,
	RACE_IMPORT_LEG_NAMES,
	raceImportLegFor
} from './race_import_providers';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, '..', '..', '..', '..', '..');

test('a listing provider resolves to its own leg', () => {
	for (const leg of RACE_IMPORT_LEG_NAMES) {
		assert.equal(raceImportLegFor(leg), leg);
	}
});

test('a listing provider with no import leg falls through to manual paste', () => {
	// parkrun / manual / raceresult listings are real `race_listings.provider`
	// values the Edge Function has no leg for. Answering with a leg would offer
	// an import that 400s; answering null is what leaves the paste form as the
	// only affordance, which is correct for them.
	for (const p of ['parkrun', 'manual', 'raceresult']) {
		assert.equal(raceImportLegFor(p), null);
	}
});

test('paste is an import leg but never a listing provider', () => {
	// The two vocabularies overlap without matching: `paste` is how the manual
	// form reaches the same function, not a race anyone can be listed under.
	assert.equal(raceImportLegFor('paste'), null);
});

test('a provider name that is only an object property resolves to nothing', () => {
	for (const p of ['', 'toString', 'constructor', '__proto__', 'hasOwnProperty']) {
		assert.equal(raceImportLegFor(p), null);
	}
});

test('every leg carries its own explainer and its own test ids', () => {
	const seen = new Map<string, string>();
	for (const [leg, spec] of Object.entries(RACE_IMPORT_LEGS)) {
		for (const field of ['unavailableKey', 'inputTestId', 'submitTestId', 'unavailableTestId'] as const) {
			const value = spec[field];
			assert.ok(value.length > 0, `${leg}.${field} is empty`);
			const owner = seen.get(`${field}:${value}`);
			assert.equal(
				owner,
				undefined,
				`${leg} shares ${field} "${value}" with ${owner} — a runner told a ` +
					'different provider is unavailable learns nothing true.'
			);
			seen.set(`${field}:${value}`, leg);
		}
	}
});

test('a leg the function refuses unscoped is a bib leg', () => {
	// `runSignUpScopeGate` and `chronoTrackScopeGate` both reject an unscoped
	// call 400 before any upstream fetch, so those two must disable their submit
	// until the field is filled. UltraSignup reads one athlete's own history and
	// falls back to the listing's id, so it has no such gate to mirror.
	for (const [leg, spec] of Object.entries(RACE_IMPORT_LEGS)) {
		if (!spec.scopeRequired) continue;
		assert.equal(spec.scopeField, 'bib', `${leg} requires a scope that is not a bib`);
	}
});

test('every credential-gated leg the Edge Function ships has a row here', () => {
	// The defect this module exists for: the function grew ultrasignup and
	// chronotrack legs while the calendar's import modal still branched on
	// runsignup alone, so provisioning either credential lit up a Settings card
	// linking to a page where the built leg could not be reached.
	const source = readFileSync(
		join(REPO_ROOT, 'apps/backend/supabase/functions/race-results-import/index.ts'),
		'utf-8'
	);
	// The bare local, not `body.provider` — `typeof body.provider === 'string'`
	// is a shape check, not a dispatch.
	const named = new Set(
		[...source.matchAll(/(?<![.\w])provider === '([a-z]+)'/g)].map((match) => match[1])
	);
	assert.ok(named.size > 0, 'read no provider dispatch out of race-results-import/index.ts');
	named.delete('paste');
	assert.deepEqual(
		[...named].sort(),
		[...RACE_IMPORT_LEG_NAMES].sort(),
		'race-results-import dispatches on a provider the race calendar cannot reach ' +
			'(or offers one the function does not have).'
	);
});

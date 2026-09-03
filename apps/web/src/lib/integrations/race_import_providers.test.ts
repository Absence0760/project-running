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

test('every leg has a pre-fetch scope gate, and the record says it is required', () => {
	// A leg with no gate fetches an unscoped upstream page and then stamps the
	// CALLER's user_id onto whatever comes back. UltraSignup shipped without one
	// for exactly as long as nothing populated its listings: its branch fell back
	// to the listing's `provider_race_id`, which is a RACE id by name and by every
	// other provider's use of it, read as an athlete account id.
	//
	// The scope FIELD differs by leg (a bib narrows a race's results; UltraSignup
	// reads one athlete's history, so its scope is an account id) — that is not
	// the invariant. The invariant is that every leg has a gate and the UI knows
	// to demand the field before submitting.
	const lib = readFileSync(
		join(REPO_ROOT, 'apps/backend/supabase/functions/race-results-import/lib.ts'),
		'utf-8'
	);
	const gated = new Set(
		[...lib.matchAll(/export function ([a-zA-Z]+)ScopeGate\b/g)].map((match) =>
			match[1].toLowerCase()
		)
	);
	assert.ok(gated.size >= 3, 'found no scope gates — the parser stopped matching');
	for (const [leg, spec] of Object.entries(RACE_IMPORT_LEGS)) {
		assert.ok(gated.has(leg), `${leg} has no ${leg}ScopeGate in the Edge Function`);
		assert.equal(spec.scopeRequired, true, `${leg} is gated server-side but not in the UI`);
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

test('the leg with a refusal beyond its credential is probed on its own leg', () => {
	// `race-listings-sync` gates UltraSignup on ULTRASIGNUP_API_KEY alone.
	// `race-results-import` refuses the same provider unconditionally (decisions
	// § 975): an athlete feed carries no race identifier, so nothing it returns
	// can be attributed to the listing a caller names. The two legs no longer
	// agree, and the card is about the results one — probing the sync
	// advertises an import whose very next call 503s once the key is
	// provisioned.
	const index = readFileSync(
		join(REPO_ROOT, 'apps/backend/supabase/functions/race-results-import/index.ts'),
		'utf8'
	);
	const probeAt = index.indexOf('body.probe === true');
	assert.ok(
		probeAt > -1,
		'race-results-import no longer has a probe branch — reread it and re-anchor this guard'
	);
	const branch = index.slice(probeAt, index.indexOf('listingId required', probeAt));
	assert.ok(
		branch.includes('ultraSignUpAttributionGate()'),
		'the probe branch no longer refuses UltraSignup independently of its credential. ' +
			'If § 975 was lifted, this guard has lost its premise — re-decide which function ' +
			'the card should probe rather than deleting the assertion below'
	);

	const data = readFileSync(join(REPO_ROOT, 'apps/web/src/lib/core/data.ts'), 'utf8');
	const fn = data.slice(
		data.indexOf('export async function isUltraSignUpConfigured'),
		data.indexOf('export async function isChronoTrackConfigured')
	);
	assert.ok(fn.length > 0, 'isUltraSignUpConfigured moved — re-anchor this guard');
	assert.ok(
		fn.includes("invoke('race-results-import'"),
		'the UltraSignup card must ask the leg that would actually run'
	);
	assert.ok(
		fn.includes('probe: true'),
		'race-results-import only reports configuration in probe mode; without the flag ' +
			'this becomes a real import with no listing'
	);
});

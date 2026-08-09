// A paid event place must never be offered for sale twice because a read
// failed. `fetchEventRsvpSummary` used to drop its `error` and return an
// all-zero summary, and `viewerStatus: null` is exactly what the event
// page reads as "this viewer has no slot" — so a transient RLS/network
// failure re-showed "Register for £X" to a runner who had already paid.
//
// Source-level, because both files reach the `supabase` singleton and the
// page is a .svelte component (see data.test.ts's header for the same
// reasoning). cwd is apps/web.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { SUPPORTED_LOCALES } from '../i18n/locale';
import { CATALOGUE_LOADERS } from '../i18n/catalogues';

const PAGE = 'src/routes/clubs/[slug]/events/[id]/+page.svelte';

function read(path: string): string {
	return readFileSync(resolve(path), 'utf-8');
}

test('fetchEventRsvpSummary fails the read instead of returning a zeroed summary', () => {
	const source = read('src/lib/core/data.ts');
	const start = source.indexOf('export async function fetchEventRsvpSummary');
	assert.ok(start >= 0, 'Could not locate fetchEventRsvpSummary — rename?');
	const next = source.indexOf('\nexport ', start + 1);
	const body = source.slice(start, next > start ? next : undefined);
	assert.match(
		body,
		/if \(error\) throw error;/,
		'a dropped error hands back going/maybe/declined/waitlisted = 0 and viewerStatus = null, which the page reads as "not registered"',
	);
});

test('the event page keeps a failed instance read apart from a loaded one', () => {
	const page = read(PAGE);
	assert.match(page, /let instanceError = \$state<string \| null>\(null\)/);
	assert.match(
		page,
		/if \(instanceError\) return 'unknown';/,
		'regState must not fall through to registrationOpen with an unknown RSVP state',
	);
	const unknownAt = page.indexOf("regState === 'unknown'");
	const registerCtaAt = page.indexOf('data-testid="register-cta"');
	assert.ok(unknownAt > 0, 'the register box needs an explicit unknown branch');
	assert.ok(
		unknownAt < registerCtaAt,
		'the unknown branch must be ordered before the Register fallback, or the fallback wins',
	);
	assert.match(page, /data-testid="club-event-instance-retry"/, 'the failure needs a retry');
});

test('reloadInstance reports its own failure rather than rethrowing into an action handler', () => {
	const page = read(PAGE);
	const start = page.indexOf('async function reloadInstance()');
	assert.ok(start >= 0, 'Could not locate reloadInstance — rename?');
	const body = page.slice(start, page.indexOf('async function readInstance()', start));
	assert.match(body, /catch \(e\)/);
	assert.match(body, /instanceError =/);
});

for (const loc of SUPPORTED_LOCALES) {
	test(`${loc} carries the unknown-registration copy`, async () => {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		for (const key of ['clubEvent.registrationUnknown', 'clubEvent.instanceLoadError']) {
			assert.ok(dict[key] && dict[key].trim().length > 0, `${loc}.${key} is present`);
		}
	});
}

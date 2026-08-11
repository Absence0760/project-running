// Architecture guard for the Edge Function ↔ web-caller response contract.
//
// An Edge Function's success payload and the `data.<key>` its only caller
// destructures are written in two different languages, in two different
// directories, with nothing between them. `events-checkout` returned
// `{ checkout_url, order_id }` while `startEventCheckout` read `data.url`,
// so paid event registration could never complete: the function had already
// created a live Stripe Checkout session and inserted a capacity-holding
// `pending` order by the time the caller threw "No checkout URL returned".
// Its `startDonationCheckout` sibling read `checkout_url` correctly, so the
// two halves of one feature disagreed with no signal.
//
// Follows the `schema.test.ts` file-as-text pattern: read both sides as
// source and assert they name the same key. A rename on either side now
// fails here instead of at a buyer's card.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, '../../../../..');
const dataTs = resolve(__dirname, 'data.ts');

/// Each pair: the Edge Function whose success response carries a URL, and
/// the exported `data.ts` function that invokes it.
const CHECKOUT_PAIRS = [
	{ fn: 'events-checkout', caller: 'startEventCheckout' },
	{ fn: 'donations-checkout', caller: 'startDonationCheckout' },
];

/// The keys of the last `Response.json({ ... })` in an Edge Function that is
/// NOT an error branch — i.e. its success payload.
function successPayloadKeys(source: string): string[] {
	const calls = [...source.matchAll(/Response\.json\(\s*\{([^}]*)\}/g)].map((m) => m[1]);
	const successes = calls.filter((body) => !/\berror\s*:/.test(body));
	assert.ok(successes.length > 0, 'expected at least one non-error Response.json');
	const last = successes[successes.length - 1];
	return [...last.matchAll(/(\w+)\s*:/g)].map((m) => m[1]);
}

/// The body of an exported function in data.ts, up to the next top-level
/// `export ` — enough to see which `data.<key>` it reads.
function callerBody(source: string, name: string): string {
	const start = source.indexOf(`export async function ${name}(`);
	assert.notEqual(start, -1, `${name} not found in data.ts`);
	const next = source.indexOf('\nexport ', start + 1);
	return source.slice(start, next === -1 ? source.length : next);
}

for (const { fn, caller } of CHECKOUT_PAIRS) {
	test(`${caller} reads the key ${fn} actually returns`, () => {
		const efSource = readFileSync(
			resolve(repoRoot, 'apps/backend/supabase/functions', fn, 'index.ts'),
			'utf8',
		);
		const keys = successPayloadKeys(efSource);
		const urlKey = keys.find((k) => k.endsWith('url'));
		assert.ok(urlKey, `${fn} success payload has no *url key (keys: ${keys.join(', ')})`);

		const body = callerBody(readFileSync(dataTs, 'utf8'), caller);
		// The caller must destructure the exact key the function emits.
		assert.match(
			body,
			new RegExp(`\\?\\.${urlKey}\\b`),
			`${caller} must read data.${urlKey} — the key ${fn} returns`,
		);
	});
}

test('the two checkout functions agree on one URL key name', () => {
	// They are the same feature shape; a divergence here is how the events
	// caller drifted while the donations one stayed correct.
	const urlKeys = CHECKOUT_PAIRS.map(({ fn }) => {
		const source = readFileSync(
			resolve(repoRoot, 'apps/backend/supabase/functions', fn, 'index.ts'),
			'utf8',
		);
		return successPayloadKeys(source).find((k) => k.endsWith('url'));
	});
	assert.equal(new Set(urlKeys).size, 1, `checkout URL keys diverged: ${urlKeys.join(' vs ')}`);
});

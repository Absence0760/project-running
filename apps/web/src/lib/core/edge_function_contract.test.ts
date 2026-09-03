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

/// ── the refusal vocabulary, not just the success key (decisions § 982) ──
///
/// `startDonationCheckout` now unwraps the envelope and the fundraiser page
/// maps the codes to copy, which puts a second cross-language contract in the
/// same position as the one above: the page compares string literals written
/// in TypeScript against codes written in Deno, with nothing between them. A
/// mapped code the function cannot send is dead copy that reads as coverage —
/// the followup that asked for this work named `host_cannot_take_payment`,
/// which the function has never returned (it is `owner_cannot_take_payment`),
/// and a map written from that filing would have silently never matched.

const donatePageSource = () =>
	readFileSync(
		resolve(repoRoot, 'apps/web/src/routes/fundraisers/[id]/+page.svelte'),
		'utf8',
	);

/// Every `error:` code the function can answer with — plain literals, plus
/// the prefixes of the two it builds by template.
function refusalVocabulary(source: string): { codes: Set<string>; prefixes: Set<string> } {
	const codes = new Set([...source.matchAll(/\berror:\s*'([a-z0-9_]+)'/g)].map((m) => m[1]));
	const prefixes = new Set(
		[...source.matchAll(/\berror:\s*`([a-z0-9_]+?)_\$\{/g)].map((m) => `${m[1]}_`),
	);
	return { codes, prefixes };
}

/// The donate handler's catch block — where the code→copy map lives.
function donateCatchBlock(source: string): string {
	const from = source.indexOf('async function submitDonation()');
	assert.notEqual(from, -1, 'submitDonation not found — did it move?');
	const to = source.indexOf('function onEdited(', from);
	assert.notEqual(to, -1, 'the handler no longer ends where this guard expects');
	return source.slice(from, to);
}

test('every donation refusal the page maps is one donations-checkout can send', () => {
	const ef = readFileSync(
		resolve(repoRoot, 'apps/backend/supabase/functions/donations-checkout/index.ts'),
		'utf8',
	);
	const { codes, prefixes } = refusalVocabulary(ef);
	assert.ok(codes.size >= 8, `expected the EF refusal codes to be found; got ${codes.size}`);
	assert.ok(prefixes.size >= 2, `expected the templated prefixes to be found; got ${prefixes.size}`);

	const block = donateCatchBlock(donatePageSource());
	const mapped = [...block.matchAll(/code === '([a-z0-9_]+)'/g)].map((m) => m[1]);
	const mappedPrefixes = [...block.matchAll(/code\.startsWith\('([a-z0-9_]+)'\)/g)].map((m) => m[1]);
	assert.ok(mapped.length > 0, 'the donate handler maps no codes at all');

	assert.deepEqual(
		mapped.filter((c) => !codes.has(c)),
		[],
		'These codes are compared on the fundraiser page but donations-checkout never sends them, ' +
			'so the copy behind them is unreachable',
	);
	assert.deepEqual(
		mappedPrefixes.filter((c) => !prefixes.has(c)),
		[],
		'These prefixes are compared on the fundraiser page but no templated code uses them',
	);
});

test('the refusals a donor can act on do not collapse into one line', () => {
	// A fundraiser that has ENDED, one whose owner cannot take money, and a
	// transient failure are three different things to do next. Collapsing
	// them into the generic line makes a donor retry a checkout that can
	// never open, which is what this map exists to stop.
	const block = donateCatchBlock(donatePageSource());
	const keyFor = (code: string): string | null => {
		const m = new RegExp(`code === '${code}'[\\s\\S]{0,120}?\\?\\s*'([a-zA-Z.]+)'`).exec(block);
		return m ? m[1] : null;
	};
	const closed = keyFor('fundraiser_closed');
	const missing = keyFor('fundraiser_not_found');
	const hostless = keyFor('owner_cannot_take_payment');
	for (const [code, key] of [
		['fundraiser_closed', closed],
		['fundraiser_not_found', missing],
		['owner_cannot_take_payment', hostless],
	] as const) {
		assert.ok(key, `${code} is not mapped to copy of its own`);
		assert.notEqual(key, 'fundraiser.donateFailed', `${code} still shows the generic line`);
	}
	assert.equal(new Set([closed, missing, hostless]).size, 3, 'two refusals share one sentence');
});

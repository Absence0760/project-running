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
/// Both checkout callers now unwrap the envelope and rethrow the function's own
/// code, and both pages map those codes to copy. That puts a second
/// cross-language contract in the same position as the one above: a page
/// compares string literals written in TypeScript against codes written in
/// Deno, with nothing between them. A mapped code the function cannot send is
/// dead copy that reads as coverage.
///
/// The two vocabularies are close enough to swap by accident and are NOT the
/// same: donations refuse with `owner_cannot_take_payment`, events with
/// `host_cannot_take_payment`. The followup that asked for the donations guard
/// named the events spelling, and a map written from that filing would have
/// compiled and silently never matched. Which is why both pairs are covered
/// here rather than one (decisions § 1003).

const REFUSAL_PAIRS = [
	{
		fn: 'donations-checkout',
		page: 'apps/web/src/routes/fundraisers/[id]/+page.svelte',
		handlerStart: 'async function submitDonation()',
		handlerEnd: 'function onEdited(',
		minCodes: 8,
		minPrefixes: 2,
		generic: 'fundraiser.donateFailed',
		// One refusal a donor can act on from each class: ended, unpayable,
		// gone. Collapsing them into the generic line makes a donor retry a
		// checkout that can never open.
		distinct: ['fundraiser_closed', 'fundraiser_not_found', 'owner_cannot_take_payment'],
		// How far past a compared code its copy key may sit. The event page
		// groups several codes into one branch, so its chain is longer.
		keyWindow: 120,
	},
	{
		fn: 'events-checkout',
		page: 'apps/web/src/routes/clubs/[slug]/events/[id]/+page.svelte',
		handlerStart: 'async function register()',
		handlerEnd: 'async function pollForPaidOrder(',
		minCodes: 12,
		// This function templates none of its codes.
		minPrefixes: 0,
		generic: 'clubEvent.registerFailed',
		distinct: ['event_full', 'sales_closed', 'host_cannot_take_payment'],
		keyWindow: 240,
	},
];

/// Every `error:` code a function can answer with — plain literals, plus the
/// prefixes of any it builds by template.
function refusalVocabulary(source: string): { codes: Set<string>; prefixes: Set<string> } {
	const codes = new Set([...source.matchAll(/\berror:\s*'([a-z0-9_]+)'/g)].map((m) => m[1]));
	const prefixes = new Set(
		[...source.matchAll(/\berror:\s*`([a-z0-9_]+?)_\$\{/g)].map((m) => `${m[1]}_`),
	);
	return { codes, prefixes };
}

/// The handler whose catch block holds the code→copy map.
function handlerBlock(source: string, from: string, to: string): string {
	const start = source.indexOf(from);
	assert.notEqual(start, -1, `${from} not found — did it move?`);
	const end = source.indexOf(to, start);
	assert.notEqual(end, -1, `the handler no longer ends where this guard expects (${to})`);
	return source.slice(start, end);
}

for (const pair of REFUSAL_PAIRS) {
	const efSource = () =>
		readFileSync(
			resolve(repoRoot, 'apps/backend/supabase/functions', pair.fn, 'index.ts'),
			'utf8',
		);
	const block = () =>
		handlerBlock(
			readFileSync(resolve(repoRoot, pair.page), 'utf8'),
			pair.handlerStart,
			pair.handlerEnd,
		);

	test(`every refusal the ${pair.fn} caller's page maps is one that function can send`, () => {
		const { codes, prefixes } = refusalVocabulary(efSource());
		assert.ok(
			codes.size >= pair.minCodes,
			`expected the EF refusal codes to be found; got ${codes.size}`,
		);
		assert.ok(
			prefixes.size >= pair.minPrefixes,
			`expected the templated prefixes to be found; got ${prefixes.size}`,
		);

		const source = block();
		const mapped = [...source.matchAll(/code === '([a-z0-9_]+)'/g)].map((m) => m[1]);
		const mappedPrefixes = [...source.matchAll(/code\.startsWith\('([a-z0-9_]+)'\)/g)].map(
			(m) => m[1],
		);
		assert.ok(mapped.length > 0, `the ${pair.fn} handler maps no codes at all`);

		assert.deepEqual(
			mapped.filter((c) => !codes.has(c)),
			[],
			`These codes are compared on ${pair.page} but ${pair.fn} never sends them, ` +
				'so the copy behind them is unreachable',
		);
		assert.deepEqual(
			mappedPrefixes.filter((c) => !prefixes.has(c)),
			[],
			`These prefixes are compared on ${pair.page} but no templated code uses them`,
		);
	});

	test(`the ${pair.fn} refusals a buyer can act on do not collapse into one line`, () => {
		const source = block();
		const keyFor = (code: string): string | null => {
			const m = new RegExp(
				`code === '${code}'[\\s\\S]{0,${pair.keyWindow}}?\\?\\s*'([a-zA-Z.]+)'`,
			).exec(source);
			return m ? m[1] : null;
		};
		const keys = pair.distinct.map((code) => [code, keyFor(code)] as const);
		for (const [code, key] of keys) {
			assert.ok(key, `${code} is not mapped to copy of its own`);
			assert.notEqual(key, pair.generic, `${code} still shows the generic line`);
		}
		assert.equal(
			new Set(keys.map(([, key]) => key)).size,
			pair.distinct.length,
			'two refusals share one sentence',
		);
	});
}

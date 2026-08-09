// Source-level guards for the detail pages that used to render a failed
// read as "not found". A headstone is a claim about the world — that the
// row is gone — and a page may only make it when the read actually came
// back empty. A transport or permission failure gets its own branch and a
// retry.
//
// Each test reads a source file as text and asserts the shape is still
// there, with the reason a future editor should weigh before removing it.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('fetchRouteById throws on a failed read instead of returning null', () => {
	// Reason: `.maybeSingle()` already separates "no row" (data null,
	// error null) from "the read failed". Dropping the error check hands
	// both back as null and every caller then has to guess which happened
	// — which is how /routes/[id] came to tell owners their route was
	// deleted whenever postgrest hiccuped.
	const source = read('src/lib/core/data.ts');
	const fn = source.match(/export async function fetchRouteById[\s\S]*?\n}/);
	assert.ok(fn, 'fetchRouteById body missing — rename?');
	assert.match(
		fn![0],
		/if \(ownerRead\.error\) throw ownerRead\.error;/,
		'the owner read must surface its error rather than falling through to the public branch',
	);
	assert.match(
		fn![0],
		/if \(read\.error\) throw read\.error;/,
		'the public_routes read must surface its error, not collapse it into a null row',
	);
});

test('fetchFundraiserById throws on a failed read instead of returning null', () => {
	// Reason: an anonymous donor arriving on a campaign link is the worst
	// possible audience for "this fundraiser isn't available" when the
	// truth is that the read failed.
	const source = read('src/lib/core/data.ts');
	const fn = source.match(/export async function fetchFundraiserById[\s\S]*?\n}/);
	assert.ok(fn, 'fetchFundraiserById body missing — rename?');
	assert.match(fn![0], /if \(error\) throw error;/, 'a failed read must throw');
	assert.doesNotMatch(
		fn![0],
		/if \(error \|\| !data\) return null;/,
		'error and empty must not be collapsed into one null return',
	);
});

test('/routes/[id] renders a retry for a failed read, not the not-found card', () => {
	const source = read('src/routes/routes/[id]/+page.svelte');
	assert.match(
		source,
		/\{:else if loadFailed\}[\s\S]*?\{:else if !route\}/,
		'the failure branch must be tested before the not-found branch',
	);
	assert.match(
		source,
		/onclick=\{\(\) => void loadRoute\(\)\}/,
		'the failure branch must offer a retry that re-reads',
	);
	const loader = source.match(/async function loadRoute[\s\S]*?\n\t\}/);
	assert.ok(loader, 'loadRoute body missing — rename?');
	assert.match(
		loader![0],
		/finally \{\s*loading = false;/,
		'loading must clear on the failure path too, not only on success',
	);
});

test('/challenges/[id] keeps not-found and could-not-load apart', () => {
	// Reason: the catch set `notFound = true`, and notFound is tested
	// first, so ANY throw — including a failed leaderboard read on a
	// challenge that had already loaded — claimed the challenge does not
	// exist.
	const source = read('src/routes/challenges/[id]/+page.svelte');
	const loader = source.match(/async function load\(\)[\s\S]*?\n\t\}/);
	assert.ok(loader, 'load body missing — rename?');
	assert.match(loader![0], /loadFailed = true;/, 'the catch must set loadFailed');
	assert.doesNotMatch(
		loader![0],
		/catch[\s\S]*?notFound = true;/,
		'the catch must not claim the challenge is missing',
	);
	assert.match(
		source,
		/\{#if notFound\}[\s\S]*?\{:else if loadFailed\}/,
		'the failure branch must sit between not-found and the body',
	);
});

test('/fundraisers/[id] renders a retry for a failed read', () => {
	const source = read('src/routes/fundraisers/[id]/+page.svelte');
	assert.match(
		source,
		/\{:else if loadFailed\}[\s\S]*?\{:else if !fundraiser\}/,
		'the failure branch must be tested before the not-found branch',
	);
	const loader = source.match(/async function load\(\)[\s\S]*?\n\t\}/);
	assert.ok(loader, 'load body missing — rename?');
	assert.match(
		loader![0],
		/finally \{\s*loading = false;/,
		'a throw anywhere in the load must not strand the page on "Loading fundraiser…"',
	);
	// The fundraising kill switch is a deliberate not-found, not a failure.
	assert.match(
		loader![0],
		/if \(!fundraisingEnabled\(\)\) \{[\s\S]*?fundraiser = null;/,
		'the fail-closed flag branch must keep rendering not-found',
	);
});

test('the read-failure copy is localized in all six catalogues', () => {
	// Reason: an error state added in English only is the same bug in five
	// locales. `satisfies Messages` catches an omission at build time, but
	// only once the key exists in en — assert every catalogue carries it.
	const keys = [
		'routeDetail.loadFailedTitle',
		'routeDetail.loadFailedBody',
		'routeDetail.retry',
		'challenges.detailLoadFailed',
		'challenges.retry',
		'fundraiser.loadFailed',
		'fundraiser.retry',
	];
	for (const locale of ['en', 'de', 'es', 'fr', 'ja', 'pt-BR']) {
		const source = read(`src/lib/i18n/locales/${locale}.ts`);
		for (const key of keys) {
			assert.ok(source.includes(`"${key}":`), `${key} missing from ${locale}.ts`);
		}
	}
});

test('the auxiliary route-line overlay swallows the new throw itself', () => {
	// Reason: fetchRouteById now rejects on a failed read, and the heatmap
	// hover preview is fired-and-forgotten. Without its own catch a
	// transient failure escapes as an unhandled rejection on a map that is
	// otherwise working fine (L4 must not break L2).
	const source = read('src/lib/components/RouteHeatmap.svelte');
	const matches = source.match(/fetchRouteById\(id\)\.catch\(/g) ?? [];
	assert.equal(matches.length, 2, 'both overlay call sites must handle a rejected read');
});

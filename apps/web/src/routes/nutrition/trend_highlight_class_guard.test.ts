import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

// The nutrition surface draws the same widget twice: a trailing-7-day column
// chart on the day view (/nutrition) and again, per meal slot, on the detail
// route (/nutrition/[date]/[slot]). Each marks ONE column with a `class:`
// modifier, and the Playwright specs bind to that modifier by name.
//
// Renaming it on one surface is a silent break: the specs still compile, still
// find `.trend-col`, and fail only in CI. That happened — the day view's
// modifier became `trend-viewed` (it marks the day being VIEWED, which is only
// today on the default URL — decisions § 591) while two specs still asserted
// `trend-today`, and the detail route went on emitting the old name, so a
// "does any nutrition surface still emit this token" check would have returned
// green on the very regression it was meant to catch. That is why this guard
// pins ONE token across both surfaces AND the specs, rather than checking each
// name against a union.
//
// It stays deliberately narrow: the highlight modifier only. The rest of the
// `trend-*` vocabulary legitimately differs between the two charts (the day
// view carries a metric toggle, an average line and a goal line the detail
// route has no use for), so asserting set equality would fail on a difference
// that is not a bug.

const DAY_VIEW = new URL('./+page.svelte', import.meta.url);
const MEAL_DETAIL = new URL('./[date]/[slot]/+page.svelte', import.meta.url);
const SPEC_DIR = new URL('../../../tests-e2e/nutrition/', import.meta.url);

/// The `class:` modifier applied to the chart's column element — the one token
/// a spec can bind to in order to say "this is the highlighted column".
function highlightModifier(url: URL): string {
	const src = readFileSync(url, 'utf8');
	const match = /class="trend-col"\s+class:([\w-]+)=/.exec(src);
	assert.ok(match, `no \`class="trend-col" class:…\` column found in ${url.pathname}`);
	return match[1];
}

test('both nutrition trend charts mark the highlighted column with the same class', () => {
	assert.equal(
		highlightModifier(MEAL_DETAIL),
		highlightModifier(DAY_VIEW),
		'the day view and the per-meal detail route highlight their column with ' +
			'different class names — a spec written against one silently stops ' +
			'matching the other',
	);
});

test('the highlight class names the viewed day, not today', () => {
	// Both charts end on the day their route is showing, which is today only on
	// the default `/nutrition`. A `trend-today` here is a claim the DOM cannot
	// keep once a date is in the URL.
	const token = highlightModifier(DAY_VIEW);
	assert.doesNotMatch(
		token,
		/today/,
		`the highlighted column is the VIEWED day, so \`${token}\` misnames it`,
	);
});

test('every nutrition spec asserting a trend highlight uses the class the charts emit', () => {
	const token = highlightModifier(DAY_VIEW);
	const asserted = new Map<string, Set<string>>();
	for (const name of readdirSync(SPEC_DIR).filter((f) => f.endsWith('.spec.ts'))) {
		const src = readFileSync(new URL(name, SPEC_DIR), 'utf8');
		for (const m of src.matchAll(/toHaveClass\(\s*\/(trend-[\w-]+)\//g)) {
			if (!asserted.has(m[1])) asserted.set(m[1], new Set());
			asserted.get(m[1])!.add(name);
		}
	}
	assert.ok(asserted.size > 0, 'no spec asserts a trend highlight class — did the selector change?');
	for (const [found, specs] of asserted) {
		assert.equal(
			found,
			token,
			`${[...specs].sort().join(', ')} assert(s) \`${found}\` but the charts emit \`${token}\``,
		);
	}
});

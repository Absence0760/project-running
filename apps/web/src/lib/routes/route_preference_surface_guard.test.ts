// The route-design preference, as the runner meets it (decisions.md § 795-798).
//
// The wire carries at most ONE preference, so the control has to be
// single-choice: three checkboxes would let a runner express a state the
// request cannot represent and leave the page to discard two of them
// silently. And a preference is an enhancement the generator may decline, so
// the page must report the preference the SERVER applied rather than the one
// the runner asked for — fail-closed, because a deployment predating the
// field sends nothing and reading nothing as success makes the disclosure
// vanish exactly where it is needed.
//
// None of that is visible to a unit test of the generator: the handler tests
// pin what the 200 body says, and these pin what the page does with it.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ROUTE_PREFERENCES } from './generate/graphhopper';
import { en } from '../i18n/locales/en';

const PAGE = 'src/routes/routes/new/+page.svelte';
const BUILDER = 'src/lib/components/RouteBuilder.svelte';

function read(rel: string): string {
	return readFileSync(resolve(rel), 'utf-8');
}

test('the preference control is one radio group, so two preferences cannot be sent', () => {
	const src = read(PAGE);
	assert.match(
		src,
		/role="radiogroup"/,
		'the three preferences plus "no preference" are mutually exclusive on the wire',
	);
	const radios = [...src.matchAll(/type="radio"\s*\n?\s*name="route-preference"/g)];
	assert.equal(
		radios.length,
		ROUTE_PREFERENCES.length + 1,
		`expected one radio per preference plus an explicit "no preference"; found ${radios.length}`,
	);
	// A checkbox bound to the preference is the shape this replaced: two of
	// them ticked is a request the body cannot carry.
	assert.doesNotMatch(
		src,
		/type="checkbox"[^>]*name="route-preference"/,
		'the preference must not be expressed as checkboxes',
	);
});

test('every preference in the generator vocabulary has an option a runner can pick', () => {
	const src = read(PAGE);
	for (const pref of ROUTE_PREFERENCES) {
		assert.match(
			src,
			new RegExp(`preference = '${pref}'`),
			`no control sets preference='${pref}' — a value the generator accepts and ` +
				'nothing on the page can ask for is a vocabulary that drifted',
		);
	}
	// And the explicit opt-out, which sends no field at all rather than a token.
	assert.match(src, /preference = null/, 'the "no preference" option must clear the field');
	assert.match(
		read(BUILDER),
		/preference \? \{ start, targetDistanceM, preference \} : \{ start, targetDistanceM \}/,
		'no preference must omit the field rather than send a null token',
	);
});

test('each option states its hint in visible text, not in a tooltip', () => {
	// § 797: a `title=` tooltip is not reachable by keyboard and is not
	// announced, so every reader gets the hint or none does.
	const src = read(PAGE);
	const group = src.match(/<div class="pref-group"[\s\S]*?<\/div>\s*\n/)?.[0] ?? '';
	assert.ok(group.length > 0, 'preference group markup not found');
	assert.doesNotMatch(group, /title=/, 'a preference hint must not live in a tooltip');
	assert.equal(
		(group.match(/class="pref-hint"/g) ?? []).length,
		ROUTE_PREFERENCES.length,
		'every preference (not the opt-out) carries a visible hint',
	);
});

test('the applied verdict is graded against the ask, never re-listed as a union', () => {
	const src = read(BUILDER);
	assert.match(
		src,
		/preference !== undefined && data\.preferenceApplied === preference \? preference : null/,
		'an absent field, an unknown token and a heuristic fallback must all resolve ' +
			'identically to "not applied" — comparing against the ask is what makes them do so',
	);
	// The three preference tokens must not be enumerated at the grading site:
	// a second copy of the vocabulary is what would let an unknown token pass.
	const grading = src.match(/const appliedPreference =[\s\S]{0,200}?;/)?.[0] ?? '';
	for (const pref of ROUTE_PREFERENCES) {
		assert.ok(!grading.includes(`'${pref}'`), `the grading site re-lists '${pref}'`);
	}
});

test('the page compares the applied value to the ask it captured at call time', () => {
	const src = read(PAGE);
	// Not to the live control: the runner may have changed the radio while the
	// generation was in flight, and grading against the new value would
	// announce a mismatch that never happened (or hide one that did).
	assert.match(src, /preferenceAsked = preference/, 'the ask is captured before the call');
	assert.match(
		src,
		/preferenceOutcome = preferenceAsked \? \{ asked: preferenceAsked, applied \} : null/,
		'the outcome pairs the applied value with the captured ask',
	);
	assert.match(
		src,
		/preferenceOutcome\.applied !== preferenceOutcome\.asked/,
		'the note fires on a mismatch between the applied value and the captured ask',
	);
});

test('the not-applied note is a permanently mounted live region', () => {
	// § 797 shipped this as a `{#if}`-mounted `role="status"` and corrected it
	// before merge — the § 736 shape, on the one message whose entire job is
	// disclosure. `live_region_mount_guard.test.ts` scans the class; this pins
	// the instance, because the scan spares a region mounted with a
	// surrounding panel and this one is.
	const src = read(PAGE);
	const note = src.match(/<p class="pref-not-applied"[\s\S]*?<\/p>/)?.[0] ?? '';
	assert.ok(note.length > 0, 'the not-applied note was not found');
	assert.match(note, /aria-live="polite"/, 'the note announces');
	assert.doesNotMatch(
		note,
		/\{#if/,
		'the region must be permanently mounted with only its text changing — a ' +
			'region that arrives with its message announces nothing',
	);
	assert.match(note, /preferenceNotApplied/, 'the region carries the disclosure copy');
	assert.match(note, /:\s*''/, 'the empty state is empty text, not an unmounted region');
});

test('the AI summary names a preference from a Record keyed by the union', () => {
	const src = read(PAGE);
	assert.match(
		src,
		/PREFERENCE_LABEL_KEYS: Record<RoutePreference, MessageKey>/,
		'an if-chain ending in a fall-through renders a fourth preference under the ' +
			'last branch\'s label, stating as fact a preference nobody asked for',
	);
	for (const pref of ROUTE_PREFERENCES) {
		assert.match(src, new RegExp(`\\b${pref}: '`), `PREFERENCE_LABEL_KEYS is missing ${pref}`);
	}
});

test('every message key the preference surface names exists in the catalogue', () => {
	const src = read(PAGE);
	const dict = en as unknown as Record<string, string>;
	const keys = new Set(
		[...src.matchAll(/m\('(routeNew\.(?:preference|quietRoads)[A-Za-z]*)'/g)].map((mm) => mm[1]),
	);
	// The label Record's values are keys too, and they are not spelled inside
	// an `m(...)` call.
	for (const k of ['routeNew.quietRoads', 'routeNew.preferenceScenic', 'routeNew.preferenceCulDeSac']) {
		keys.add(k);
	}
	assert.ok(keys.size >= 8, `expected the preference copy to name >=8 keys, saw ${keys.size}`);
	for (const key of keys) {
		assert.ok(dict[key], `missing English copy for ${key}`);
		assert.ok(dict[key].trim().length > 0, `empty English copy for ${key}`);
	}
	// § 797's second correction: the note names a ROUTE, not a loop — the first
	// case it exists for is point-to-point, where no loop was ever asked for.
	assert.ok(dict['routeNew.preferenceNotApplied']);
	assert.doesNotMatch(
		dict['routeNew.preferenceNotApplied'],
		/\bloop\b/i,
		'the note fires on point-to-point too, where the button itself says "route"',
	);
});

// Source-level guards that pin in place the segments v2 wiring on
// the web side. Each test reads a source file as text and asserts a
// pattern is present, with a reason a future editor can read before
// deciding it's safe to break.
//
// Mirrors the segments v2 guards in
// `apps/mobile_android/test/architecture_guards_test.dart`.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('SegmentsPanel.svelte calls the v2 tiered RPC, not the v1 fetcher', () => {
	// Reason: the panel switched to fetchSegmentLeaderboardTiered when
	// v2 shipped. If a future refactor reaches for the v1 helper it
	// silently drops gender + age-band filtering even when the dropdowns
	// are populated — bug class: filtered UI, unfiltered data.
	const source = read('src/lib/components/SegmentsPanel.svelte');
	assert.match(
		source,
		/fetchSegmentLeaderboardTiered/,
		'panel must route through the v2 RPC',
	);
});

test('SegmentsPanel.svelte renders the tier-filter dropdowns', () => {
	const source = read('src/lib/components/SegmentsPanel.svelte');
	assert.match(source, /class="tier-filters"/, 'tier-filter block missing');
	assert.match(
		source,
		/bind:value=\{genderFilter\}/,
		'gender dropdown not two-way bound',
	);
	assert.match(
		source,
		/bind:value=\{ageFilter\}/,
		'age-band dropdown not two-way bound',
	);
});

test('SegmentsPanel.svelte populates the age dropdown from SEGMENT_AGE_BANDS', () => {
	// Reason: hard-coding the bands inline would let the panel drift
	// from the RPC's age-band parser. Reading them from the shared
	// constant is the only way the unit tests can keep both ends in
	// lockstep.
	const source = read('src/lib/components/SegmentsPanel.svelte');
	assert.match(source, /SEGMENT_AGE_BANDS/, 'panel must read the shared constant');
	assert.match(
		source,
		/\{#each SEGMENT_AGE_BANDS as band\}/,
		'dropdown must iterate the shared constant',
	);
});

test('SegmentsPanel.svelte exposes a Reset chip while a filter is set', () => {
	// Reason: a user who narrows by gender + age (+ the persona #50 club-only
	// toggle) has no other affordance to clear the filter — closing and
	// re-opening the same segment would lose context. The Reset chip lives
	// behind `genderFilter || ageFilter` (plus the optional `|| clubOnly`
	// term when a club leaderboard is in play) so it appears only when
	// relevant.
	const source = read('src/lib/components/SegmentsPanel.svelte');
	assert.match(
		source,
		/\{#if genderFilter \|\| ageFilter(?: \|\| clubOnly)?\}/,
		'Reset chip visibility gate missing',
	);
	assert.match(source, /class="clear-btn"/, 'Reset chip class missing');
});

test('SegmentsPanel.svelte toggle does not double-fire the leaderboard fetch', () => {
	// Reason: a previous version called refreshLeaderboard explicitly
	// inside toggleLeaderboard AND let the $effect re-fire on the same
	// state changes — two concurrent RPCs per toggle. The fix is to
	// drop the explicit call and trust the effect. Pin it so the next
	// editor can't silently reintroduce the race.
	const source = read('src/lib/components/SegmentsPanel.svelte');
	const toggleBody = source.match(/function toggleLeaderboard[\s\S]*?\n\t\}/);
	assert.ok(toggleBody, 'toggleLeaderboard body missing');
	assert.doesNotMatch(
		toggleBody![0],
		/await\s+refreshLeaderboard/,
		'toggleLeaderboard must not await refreshLeaderboard — the $effect handles it',
	);
});

test('Settings → preferences writes gender + date_of_birth to user_profiles', () => {
	// Reason: tiered leaderboards depend on user_profiles.gender +
	// date_of_birth. If the settings page stops persisting them the
	// filter dropdowns silently return empty for every user.
	// GDPR Art 9 gates both writes behind healthDataConsent — without
	// consent the page null-writes, with consent it writes the user
	// input. Both branches are valid writebacks, so the guard accepts
	// either shape.
	const source = read('src/routes/settings/preferences/+page.svelte');
	assert.match(source, /user_profiles/, 'page must talk to user_profiles');
	assert.match(
		source,
		/gender:\s*\(?healthDataConsent\s*&&\s*gender\)?\s*\?\s*gender\s*:\s*null/,
		'gender writeback missing (consent-gated form)',
	);
	assert.match(
		source,
		/date_of_birth:\s*\(?healthDataConsent\s*&&\s*dateOfBirth\)?\s*\?\s*dateOfBirth\s*:\s*null/,
		'date_of_birth writeback missing (consent-gated form)',
	);
});

test('Settings → preferences hydrates gender + dob from user_profiles on load', () => {
	const source = read('src/routes/settings/preferences/+page.svelte');
	// gender / date_of_birth / health_data_consent_at are deny-by-default
	// columns for direct authenticated SELECTs (column lockdown,
	// 20260707_001) — a direct .select() 403s, so the self-read goes through
	// the get_my_profile() RPC, then the form reads each field off the row.
	assert.match(
		source,
		/get_my_profile/,
		'preferences must self-read the profile via get_my_profile() (direct column select 403s)',
	);
	assert.match(source, /prof\.gender/, 'preferences must read gender to populate the form');
	assert.match(source, /prof\.date_of_birth/, 'preferences must read DOB to populate the form');
});

test('SegmentsPanel.svelte renders a KOM/QOM crown on the rank-1 row', () => {
	// Reason: the crown badge is the visual marker for the tier leader.
	// It lives behind `entry.rank === 1` so it only appears once per
	// leaderboard view. Stripping the badge silently turns segments
	// into a plain top-N list — bug class: lost product surface.
	const source = read('src/lib/components/SegmentsPanel.svelte');
	assert.match(source, /\{#if entry\.rank === 1\}/, 'crown gate missing');
	assert.match(source, /class="material-symbols crown-icon"/, 'crown icon class missing');
	assert.match(source, /emoji_events/, 'crown glyph missing');
});

test('SegmentsPanel.svelte tooltips the crown with the active tier', () => {
	// Reason: a generic "King" badge would be ambiguous on a filtered
	// view. crownLabel() composes "Fastest woman 30-34" / "Fastest
	// overall" / etc. so the tooltip is honest about which tier the
	// crown represents.
	const source = read('src/lib/components/SegmentsPanel.svelte');
	assert.match(source, /crownLabel\(genderFilter, ageFilter\)/, 'crown label not piped to title/aria');
});

test('SegmentsPanel.svelte announces a self-held crown above the list', () => {
	// Reason: the per-row crown is small. The "You hold this crown"
	// banner gives the viewer an obvious confirmation when they're the
	// rank-1 holder under the current filter.
	const source = read('src/lib/components/SegmentsPanel.svelte');
	assert.match(source, /class="crown-banner"/, 'crown banner class missing');
	// Copy was extracted into the i18n catalogue (segments.youHoldCrown);
	// assert the banner renders that key and the English copy still
	// confirms self-ownership.
	assert.match(source, /t\('segments\.youHoldCrown'/, 'crown banner must render the youHoldCrown key');
	const en = read('src/lib/i18n/locales/en.ts');
	assert.match(
		en,
		/"segments\.youHoldCrown":\s*"You hold this crown/,
		'segments.youHoldCrown copy must confirm the viewer holds the crown',
	);
});

test('/segments/[id] cannot strand the page on a failed segment fetch', () => {
	// Reason: `loading` starts true and the only thing that clears it used
	// to be the line after an unguarded `await fetchGlobalSegment`. A
	// rejected fetch (offline, RPC 5xx) therefore left the page rendering
	// its blank `<p class="loading">&nbsp;</p>` forever, with no message
	// and no way back. SegmentsPanel already learned this; the standalone
	// page is the same fetch and owes the same error state.
	const source = read('src/routes/segments/[id]/+page.svelte');
	const loader = source.match(/async function loadSegment[\s\S]*?\n\t\}/);
	assert.ok(loader, 'loadSegment body missing');
	assert.match(loader![0], /try \{/, 'the segment fetch must be guarded');
	assert.match(loader![0], /loadFailed = true/, 'a failed fetch must set loadFailed');
	assert.match(
		loader![0],
		/finally \{\s*loading = false;/,
		'loading must clear on the failure path too, not only on success',
	);
	assert.match(
		source,
		/\{:else if loadFailed\}/,
		'the page needs a failure branch between loading and not-found',
	);
	assert.match(
		source,
		/onclick=\{\(\) => void loadSegment\(\)\}/,
		'the failure branch must offer a retry',
	);
});

test('/segments/[id] cannot strand the leaderboard on a failed board fetch', () => {
	// Reason: `board == null` IS the loading state, so a rejected
	// leaderboard fetch renders "Loading…" indefinitely — and the filter
	// dropdowns re-null it, so one failed filter change wedges the board.
	const source = read('src/routes/segments/[id]/+page.svelte');
	const refresh = source.match(/async function refreshBoard[\s\S]*?\n\t\}/);
	assert.ok(refresh, 'refreshBoard body missing');
	assert.match(refresh![0], /boardFailed = true/, 'a failed board fetch must set boardFailed');
	assert.match(
		source,
		/\{#if boardFailed\}[\s\S]*?\{:else if board == null\}/,
		'boardFailed must be tested before the null-is-loading branch',
	);
});

test('the segment-detail error copy is localized in all six catalogues', () => {
	// Reason: an error state added in English only is the same bug in five
	// locales. `satisfies Messages` catches an omission at build time, but
	// only once the key exists in en — assert every catalogue carries it.
	const keys = [
		'segments.leaderboardFailed',
		'segmentDetail.loadFailedTitle',
		'segmentDetail.loadFailedBody',
		'segmentDetail.retry',
	];
	for (const locale of ['en', 'de', 'es', 'fr', 'ja', 'pt-BR']) {
		const source = read(`src/lib/i18n/locales/${locale}.ts`);
		for (const key of keys) {
			assert.match(
				source,
				new RegExp(`"${key.replace('.', '\\.')}":`),
				`${key} missing from ${locale}.ts`,
			);
		}
	}
});

test('/segments shapes the catalogue through the pure browse helpers', () => {
	// Reason: filter + sort semantics (accent folding, nulls-last on the
	// numeric orders, the canonical surface order) are unit-tested in
	// catalogue_browse.test.ts. An inline `.filter()` in the page would put
	// them back out of reach of every test — bug class: logic that only a
	// browser can exercise.
	const source = read('src/routes/segments/+page.svelte');
	assert.match(source, /from '\$lib\/segments\/catalogue_browse'/, 'page must import the helpers');
	assert.match(source, /filterCatalogue\(/, 'page must filter through filterCatalogue');
	assert.match(source, /sortCatalogue\(/, 'page must sort through sortCatalogue');
});

test('/segments cannot strand the browse page on a failed catalogue fetch', () => {
	// Reason: the same defect /segments/[id] shipped with. `loading` starts
	// true and `segments` starts empty, so an unguarded rejection renders the
	// empty-catalogue copy — telling a runner the catalogue is empty when the
	// network is simply down. fetchGlobalSegmentsWithError exists precisely to
	// make that distinguishable; the page owes it a branch and a retry.
	const source = read('src/routes/segments/+page.svelte');
	const loader = source.match(/async function load[\s\S]*?\n\t\}/);
	assert.ok(loader, 'load body missing');
	assert.match(loader![0], /loadError = /, 'a failed fetch must set loadError');
	assert.match(
		loader![0],
		/finally \{\s*loading = false;/,
		'loading must clear on the failure path too, not only on success',
	);
	assert.match(source, /\{:else if loadError\}/, 'the page needs a failure branch');
	assert.match(source, /onclick=\{load\}/, 'the failure branch must offer a retry');
});

test('/segments distinguishes an empty catalogue from an empty filter result', () => {
	// Reason: collapsing the two states tells a runner who narrowed to
	// "trail in Sydney" that no famous segments exist at all, and offers no
	// hint that widening the filter is the fix. Same distinction
	// SegmentsPanel already draws between noEffortsYet and noEffortsFiltered.
	const source = read('src/routes/segments/+page.svelte');
	assert.match(source, /segments\.browseEmpty/, 'empty-catalogue copy missing');
	assert.match(source, /segments\.browseNoMatches/, 'filtered-empty copy missing');
});

test('the catalogue-browse copy is localized in all six catalogues', () => {
	const keys = [
		'segments.browseTitle',
		'segments.browseIntro',
		'segments.browseSearchPlaceholder',
		'segments.browseAllRegions',
		'segments.browseAllSurfaces',
		'segments.browseSortClimb',
		'segments.browseCount',
		'segments.browseFailed',
		'segments.browseEmpty',
		'segments.browseNoMatches',
		'segments.browseAll',
	];
	for (const locale of ['en', 'de', 'es', 'fr', 'ja', 'pt-BR']) {
		const source = read(`src/lib/i18n/locales/${locale}.ts`);
		for (const key of keys) {
			assert.match(
				source,
				new RegExp(`"${key.replace('.', '\\.')}":`),
				`${key} missing from ${locale}.ts`,
			);
		}
	}
});

test('data.ts re-exports the moved constants from segments.ts', () => {
	// Reason: SEGMENT_AGE_BANDS / SegmentAgeBand / SegmentGenderFilter
	// moved out of data.ts into the pure segments module so unit tests
	// can import them without dragging in $env. Existing callers still
	// reach for the data.ts path — keep the re-export so they compile.
	const source = read('src/lib/core/data.ts');
	assert.match(
		source,
		/export \{[^}]*SEGMENT_AGE_BANDS[^}]*\}\s*from\s*'\.\.\/segments\/segments'/,
		'data.ts must re-export SEGMENT_AGE_BANDS from segments',
	);
});

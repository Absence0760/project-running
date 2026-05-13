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
	// Reason: a user who narrows by gender + age has no other affordance
	// to clear the filter — closing and re-opening the same segment
	// would lose context. The Reset chip lives behind `genderFilter ||
	// ageFilter` so it appears only when relevant.
	const source = read('src/lib/components/SegmentsPanel.svelte');
	assert.match(
		source,
		/\{#if genderFilter \|\| ageFilter\}/,
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
	const source = read('src/routes/settings/preferences/+page.svelte');
	assert.match(source, /user_profiles/, 'page must talk to user_profiles');
	assert.match(
		source,
		/gender:\s*gender\s*\|\|\s*null/,
		'gender writeback missing',
	);
	assert.match(
		source,
		/date_of_birth:\s*dateOfBirth\s*\|\|\s*null/,
		'date_of_birth writeback missing',
	);
});

test('Settings → preferences hydrates gender + dob from user_profiles on load', () => {
	const source = read('src/routes/settings/preferences/+page.svelte');
	assert.match(
		source,
		/\.select\('gender,\s*date_of_birth'\)/,
		'preferences page must select gender + DOB to populate the form',
	);
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
	assert.match(source, /You hold this crown/, 'crown banner copy missing');
});

test('data.ts re-exports the moved constants from segments.ts', () => {
	// Reason: SEGMENT_AGE_BANDS / SegmentAgeBand / SegmentGenderFilter
	// moved out of data.ts into the pure segments module so unit tests
	// can import them without dragging in $env. Existing callers still
	// reach for the data.ts path — keep the re-export so they compile.
	const source = read('src/lib/data.ts');
	assert.match(
		source,
		/export \{[^}]*SEGMENT_AGE_BANDS[^}]*\}\s*from\s*'\.\/segments'/,
		'data.ts must re-export SEGMENT_AGE_BANDS from segments',
	);
});

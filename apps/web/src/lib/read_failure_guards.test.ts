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
import { SUPPORTED_LOCALES } from './i18n/locale';
import { stripComments } from './core/strip_comments';

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
	// conventions.md: the error branch is ordered before the empty and
	// not-found branches.
	assert.match(
		source,
		/\{#if loadFailed\}[\s\S]*?\{:else if notFound\}/,
		'the failure branch must be tested before the not-found branch',
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

test('the fundraiser totals + feed reads throw instead of reporting an empty campaign', () => {
	// Reason: both swallowed their error — `if (error || !data) return null/[]`
	// — so a failed read rendered a thermometer at "0 raised · 0 supporters"
	// over "Be the first to donate". That is not this page's own emptiness to
	// report: it tells a donor, on someone else's campaign, that nobody has
	// given. The genuine miss (the RPC answering with no rows) still returns
	// null / [].
	const source = read('src/lib/core/data.ts');
	for (const name of ['fetchFundraiserTotals', 'fetchFundraiserFeed']) {
		const fn = source.match(new RegExp(`export async function ${name}[\\s\\S]*?\\n}`));
		assert.ok(fn, `${name} body missing — rename?`);
		assert.match(fn![0], /if \(error\) throw error;/, `${name} must surface a failed read`);
		assert.doesNotMatch(
			fn![0],
			/if \(error \|\|/,
			`${name} must not collapse a failure into the empty result`,
		);
	}
});

test('fetchChallengeById fails the whole read when the participants read fails', () => {
	// Reason: the second read discarded its error, so a failure reported
	// `participant_count: 0` and `joined: false` — a challenge the caller had
	// already joined offered them "Join" again, over a board it said was
	// empty. conventions.md: a partial read failure fails the whole read.
	const source = read('src/lib/core/data.ts');
	const fn = source.match(/export async function fetchChallengeById[\s\S]*?\n}/);
	assert.ok(fn, 'fetchChallengeById body missing — rename?');
	assert.match(
		fn![0],
		/if \(partsError\) throw partsError;/,
		'the participants read must surface its error',
	);
	assert.doesNotMatch(
		fn![0],
		/const \{ data: parts \} =/,
		'destructuring only `data` is how the error came to be dropped',
	);
});

test('/fundraisers/[id] reports a panel failure without blanking the page', () => {
	// Reason: the two panels are separate reads from the campaign row. A
	// failure in either must say so and offer a retry — and must be tested
	// BEFORE the panel's own empty state, or "Be the first to donate" wins.
	const source = read('src/routes/fundraisers/[id]/+page.svelte');
	assert.match(
		source,
		/\{#if totalsFailed\}[\s\S]*?<GoalThermometer/,
		'the totals failure branch must be tested before the thermometer renders zeros',
	);
	assert.match(
		source,
		/\{#if feedFailed\}[\s\S]*?<DonationFeed/,
		'the feed failure branch must be tested before the feed renders its empty state',
	);
	for (const fn of ['refreshTotals', 'refreshFeed']) {
		const body = source.match(new RegExp(`async function ${fn}\\(\\)[\\s\\S]*?\\n\\t\\}`));
		assert.ok(body, `${fn} body missing — rename?`);
		assert.match(body![0], /catch \(e\)/, `${fn} must catch so one panel cannot blank the page`);
	}
	assert.match(
		source,
		/onclick=\{\(\) => void refreshTotals\(\)\}/,
		'the totals failure must offer a retry that re-reads only that panel',
	);
	assert.match(source, /onclick=\{\(\) => void refreshFeed\(\)\}/);
});

test('FundraiserSection keeps a totals failure from erasing the campaign', () => {
	// Reason: one try block held both reads, so a totals failure set
	// `fundraiser = null` and the whole card vanished — a live campaign
	// replaced by the owner's "Raise money for a charity" CTA.
	const source = read('src/lib/components/FundraiserSection.svelte');
	const loader = source.match(/async function load\(\)[\s\S]*?\n\t\}/);
	assert.ok(loader, 'load body missing — rename?');
	assert.doesNotMatch(
		loader![0],
		/fetchFundraiserTotals[\s\S]*?\} catch \(e\) \{[\s\S]*?fundraiser = null;/,
		'the totals read must not share a catch that clears the campaign',
	);
	assert.match(source, /totalsFailed = true;/, 'a totals failure must be reported, not defaulted');
	assert.match(
		read('src/lib/components/FundraiserCard.svelte'),
		/\{#if totalsFailed\}[\s\S]*?<GoalThermometer/,
		'the card must say the total is unknown rather than draw it at zero',
	);
});

test('the read-failure copy is localized in every catalogue', () => {
	// Reason: an error state added in English only is the same bug in every
	// other locale. `satisfies Messages` catches an omission at build time, but
	// only once the key exists in en — assert every catalogue carries it.
	const keys = [
		'routeDetail.loadFailedTitle',
		'routeDetail.loadFailedBody',
		'routeDetail.retry',
		'challenges.detailLoadFailed',
		'challenges.retry',
		'fundraiser.loadFailed',
		'fundraiser.retry',
		'fundraiser.totalsFailed',
		'fundraiser.feedFailed',
	];
	for (const locale of SUPPORTED_LOCALES) {
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

test('/gym/routines/[id] re-enters the loading state when Retry runs', () => {
	// Reason: the retry cleared `loadError` without setting `loading` back
	// to true, so the re-read rendered through the `!detail` branch —
	// "Routine not found" — for the whole round trip. Pressing Retry on a
	// page whose entire point is not to claim the routine is gone said
	// exactly that.
	const source = read('src/routes/gym/routines/[id]/+page.svelte');
	const loader = source.match(/async function load\(\)[\s\S]*?\n\t\}/);
	assert.ok(loader, 'load body missing — rename?');
	assert.match(
		loader![0],
		/loading = true;\s*\n\s*loadError = null;/,
		'load must raise `loading` before it clears the error',
	);
	assert.match(
		loader![0],
		/finally \{\s*loading = false;/,
		'loading must clear on both paths, from one place',
	);
	assert.match(
		source,
		/\{:else if loadError\}[\s\S]*?\{:else if !detail\}/,
		'the failure branch must be tested before the not-found branch',
	);
});

test('/clubs/[slug] surfaces a failed post reply instead of swallowing it', () => {
	// Reason: sendReply had try/finally and no catch. A rejected insert
	// left no reply, no message, and a re-enabled button — which reads as
	// an invitation to click again, and that is how one reply becomes two
	// the moment the write starts landing.
	const source = read('src/routes/clubs/[slug]/+page.svelte');
	const send = source.match(/async function sendReply[\s\S]*?\n\t\}/);
	assert.ok(send, 'sendReply body missing — rename?');
	assert.match(
		send![0],
		/catch \(e\) \{[\s\S]*?clubHome\.replyFailed/,
		'a rejected reply must be surfaced the way the rest of the page surfaces failures',
	);
	const toggle = source.match(/async function toggleReplies[\s\S]*?\n\t\}/);
	assert.ok(toggle, 'toggleReplies body missing — rename?');
	assert.match(
		toggle![0],
		/clubHome\.repliesLoadFailed/,
		'opening a thread that fails to load must say so, not stay silently collapsed',
	);
	for (const locale of SUPPORTED_LOCALES) {
		const catalogue = read(`src/lib/i18n/locales/${locale}.ts`);
		for (const key of ['clubHome.replyFailed', 'clubHome.repliesLoadFailed']) {
			assert.ok(catalogue.includes(`"${key}":`), `${key} missing from ${locale}.ts`);
		}
	}
});

test('FundraiserSection tells a non-owner the campaign read failed', () => {
	// Reason: the load catch deliberately leaves `fundraiser = null` so a
	// transient failure cannot hide the owner's "Create fundraiser" CTA — and
	// that is right as far as it goes. For everyone else it rendered NOTHING,
	// which is exactly what a run with no campaign renders, so a donor
	// following a shared link could not tell a failed read from "no campaign".
	// The component already models the sibling failure precisely (totalsFailed,
	// so a totals blip is not drawn as "0 raised"); this is the same treatment
	// one read up.
	const source = read('src/lib/components/FundraiserSection.svelte');
	const loader = source.match(/async function load\(\)[\s\S]*?\n\t\}/);
	assert.ok(loader, 'load body missing — rename?');
	assert.match(
		loader![0],
		/loadFailed = true;/,
		'a failed campaign read must be reported, not collapsed into "no campaign"',
	);
	assert.match(
		loader![0],
		/loadFailed = false;/,
		'the flag must reset on each attempt, or a retry that succeeds still shows the error',
	);
	assert.match(
		source,
		/\{#if loadFailed\}[\s\S]{0,400}?fundraiser\.loadFailed[\s\S]{0,300}?fundraiser\.retry/,
		'the failure branch must render the localized message and a retry',
	);
	assert.match(
		source,
		/onclick=\{\(\) => void load\(\)\}/,
		'the retry must re-run the load, matching /fundraisers/[id]',
	);
	// The owner CTA must survive: hiding it on a blip is the regression the
	// original catch was written to prevent.
	assert.match(
		source,
		/data-testid="fundraiser-create-cta"/,
		'the owner Create CTA must still render when the read failed',
	);
});

test('a club list survives a membership blip instead of becoming an error page', () => {
	// Reason: enrichClubs reporting a failed club_members read was the right
	// call (a null role must not be asserted as non-membership), but returning
	// `clubs: []` discarded rows the caller had already read, so every surface
	// rendered "couldn't load clubs" for a list that had loaded fine. Browsing
	// a club list does not require knowing your own role in each one. The
	// single-club reader is deliberately NOT included: an unknown role there
	// silently downgrades an owner to the member view.
	const data = stripComments(read('src/lib/core/data.ts'));
	const start = data.indexOf('async function enrichClubs(');
	assert.ok(start >= 0, 'enrichClubs moved — re-anchor this guard');
	const body = data.slice(start, data.indexOf('\nexport ', start + 1));
	const failure = body.slice(body.indexOf('if (rolesRes.error)'));
	assert.doesNotMatch(
		failure.slice(0, failure.indexOf('}')),
		/clubs: \[\]/,
		'a membership blip must not discard the clubs the caller already read',
	);
	assert.match(
		data,
		/if \(rolesError\) return \{ club: null, error: rolesError \};/,
		'fetchClubBySlug must still fail — an unknown role hides an owner admin controls',
	);

	const panel = read('src/lib/components/SocialClubs.svelte');
	assert.match(
		panel,
		/\{:else if loadError && visible\.length > 0\}/,
		'a list with rows and an error must render the rows plus a notice, not the error card',
	);
	assert.match(
		panel,
		/socialClubs\.membershipUnknown/,
		'the notice must say membership is unknown, not that the clubs failed to load',
	);
	assert.match(
		panel,
		/\{:else if loadError\}[\s\S]{0,200}?socialClubs\.loadErrorTitle/,
		'with no rows to show, the full error card is still the honest answer',
	);
	for (const locale of SUPPORTED_LOCALES) {
		assert.ok(
			read(`src/lib/i18n/locales/${locale}.ts`).includes('"socialClubs.membershipUnknown":'),
			`socialClubs.membershipUnknown missing from ${locale}.ts`,
		);
	}
});

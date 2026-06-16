import { expect, test } from '@playwright/test';

import { COMPARE_HEADLINE, COMPARE_SECTIONS } from '../../src/lib/settings/compare_features';

/**
 * /compare — visitor conversion JOURNEY (long-workflow).
 *
 * IMPORTANT — premise correction. The task that seeded this file
 * assumed /compare is a "pick two of MY runs and compare them
 * side-by-side (pace / splits / elevation)" surface. It is NOT. There
 * is no run-vs-run comparison anywhere in the app:
 *   - src/routes/compare/+page.svelte renders a STATIC marketing table
 *     comparing *Threkir vs Strava Free vs Strava Pro*, driven entirely
 *     by src/lib/settings/compare_features.ts (COMPARE_SECTIONS +
 *     COMPARE_HEADLINE). No run pickers, no /compare?a=&b= params, no
 *     pace/splits/elevation diff of two activities.
 *   - the only "compare*" identifiers in the codebase are unrelated
 *     (compareLeaderboard in runs/race_leaderboard, comparePeopleRank in
 *     social/search_ranking) — neither is a UI surface.
 * So planting two runs with distinct metrics and asserting "the faster
 * one is shown as faster" is impossible here: the page reads no run
 * data and is anon/static. Writing that workflow would mean asserting
 * against UI that doesn't exist.
 *
 * What this spec DOES cover — the uncovered end-to-end ARC of the page
 * that actually exists. page.spec.ts + page-depth.spec.ts pin isolated
 * facts (title/meta, 6 tables, coloured cells, sr-only labels, the
 * `ours` highlight, mobile collapse, verbatim pricing). Neither drives
 * the *reader's path*: land on the marketing page → read the headline
 * pricing → follow a concrete feature row's verdict across all three
 * providers → drill into one of the internal "explore the features"
 * links to the real destination → and follow the donate CTA through to
 * /settings/upgrade. That navigation arc — compare → /coach and
 * compare → /settings/upgrade — is the conversion funnel the page is
 * built to drive, and it is unpinned today.
 *
 * Anon + no auth + no seeded data: the page is publicly readable and
 * mounts no map / third-party SDK (page-depth.spec.ts asserts it needs
 * no consent), so this journey owns nothing to clean up. We still
 * pre-accept the cookie banner per house e2e convention so a floating
 * dialog can never sit over a link we click.
 */

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
	);
}

// A feature row that is unambiguously yes / no / partial across the
// three providers is the most honest one to walk — its three cells must
// render three DIFFERENT glyphs + sr-only labels. Derive it from the
// real data so a content edit that flips a verdict surfaces here, not
// silently. compare_features.ts:79-83 holds the canonical example
// ("Interactive elevation + pace chart": ours yes / free partial / pro
// yes), but we pick it by predicate so this stays honest under edits.
const TRISTATE_ROW = COMPARE_SECTIONS.flatMap((s) => s.rows).find(
	(r) =>
		r.ours === 'yes' &&
		(r.stravaFree === 'partial' || r.stravaFree === 'no') &&
		r.stravaFree !== r.stravaPro,
);

const LABEL: Record<string, string> = { yes: 'Yes', no: 'No', partial: 'Partial' };

test.describe('/compare — visitor conversion journey (anon, static marketing page)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(setConsentAccepted);
	});

	test('a visitor reads the headline, a feature verdict, then converts via the internal + donate links', async ({
		page,
	}) => {
		expect(
			TRISTATE_ROW,
			'compare_features.ts should hold at least one yes/(partial|no, differing from pro) row',
		).toBeTruthy();
		if (!TRISTATE_ROW) return;

		await test.step('land on /compare and see the conversion headline', async () => {
			await page.goto('/compare');
			// Hero heading is the headline that does the converting.
			// compare/+page.svelte:25 → m('compare.heroHeading') =
			// "Everything Strava Pro has — free." (en.ts:1797).
			await expect(
				page.getByRole('heading', { name: /Everything Strava Pro has/ }),
			).toBeVisible();
			// No consent veil / no map gate — the tables are immediately
			// readable to an anon visitor (page-depth.spec.ts pins the
			// no-veil contract; we re-assert it as the journey's entry gate).
			await expect(page.getByRole('button', { name: /Load map/i })).toHaveCount(0);
			await expect(page.locator('table.cmp-table').first()).toBeVisible();
		});

		await test.step('read the three pricing cards — our Free vs Strava Free/Pro', async () => {
			// The three .price-card values come verbatim from
			// COMPARE_HEADLINE (compare/+page.svelte:33/38/43). A reader
			// compares "Free forever" against the Strava Pro $/mo figure;
			// pin all three so a region/currency edit is a visible change.
			const usCard = page.locator('.price-card.us');
			await expect(usCard.locator('.price-label')).toHaveText('Threkir');
			await expect(usCard.locator('.price')).toHaveText(COMPARE_HEADLINE.usPrice);
			await expect(
				page.getByText(COMPARE_HEADLINE.stravaFreePrice, { exact: true }),
			).toBeVisible();
			await expect(
				page.getByText(COMPARE_HEADLINE.stravaProPrice, { exact: true }),
			).toBeVisible();
		});

		await test.step('follow one feature row across all three providers', async () => {
			// Walk a single, concrete row the way a reader does: find the
			// <tr> by its feature name, then confirm each provider column's
			// sr-only verdict matches the source data. The .ours cell is
			// the highlighted "this is us" column (compare/+page.svelte:70),
			// and data-col targets the named provider cells (:77 / :84).
			const tr = page
				.locator('table.cmp-table tr', { hasText: TRISTATE_ROW.name })
				.first();
			await expect(tr).toBeVisible();
			await expect(tr.locator('td.cell.ours .sr-only')).toHaveText(LABEL[TRISTATE_ROW.ours]);
			await expect(tr.locator('td[data-col="Strava Free"] .sr-only')).toHaveText(
				LABEL[TRISTATE_ROW.stravaFree],
			);
			await expect(tr.locator('td[data-col="Strava Pro"] .sr-only')).toHaveText(
				LABEL[TRISTATE_ROW.stravaPro],
			);
			// The highlighted column really is ours (a non-transparent
			// tint), so the comparison's whole point isn't flattened.
			const oursBg = await tr
				.locator('td.cell.ours')
				.first()
				.evaluate((el) => getComputedStyle(el).backgroundColor);
			expect(oursBg).not.toBe('rgba(0, 0, 0, 0)');
			expect(oursBg).not.toBe('transparent');
		});

		await test.step('the AI Coach feature link routes an anon visitor into the sign-in funnel', async () => {
			// The footer "Explore the features" strip links to the real
			// product surfaces (compare/+page.svelte:104 a[href="/coach"]). But
			// /coach is NOT in the +layout.svelte anon-allowed set, so the
			// global auth guard bounces an unauthenticated visitor to /login
			// (with a return_to=/coach so they land on Coach after signing in).
			// The marketing link's job is to route into that funnel — the same
			// auth-wall end the donate CTA hits below.
			const coachLink = page.locator('.cmp-footer a[href="/coach"]');
			await expect(coachLink).toBeVisible();
			await coachLink.click();
			await expect(page).toHaveURL(/\/login/, { timeout: 10_000 });
		});

		await test.step('the donate CTA routes an anon visitor into the sign-in funnel', async () => {
			await page.goto('/compare');
			// The donate link is the page's one conversion CTA
			// (compare/+page.svelte:100 a[href="/settings/upgrade"], copy
			// m('compare.footerDonateLink') = "donate page", en.ts:1804).
			const donate = page.locator('.cmp-footer a[href="/settings/upgrade"]');
			await expect(donate).toBeVisible();
			await expect(donate).toHaveText(/donate page/i);
			await donate.click();
			// /settings/* is a protected subtree — the root +layout.svelte:180
			// auth guard redirects an unauthenticated visitor to /login (the
			// same behaviour auth-walls.spec.ts pins for /settings/account). So
			// the anon end-of-funnel for this CTA is the sign-in wall, not the
			// upgrade page body — converting means signing in first.
			await expect(page).toHaveURL(/\/login/, { timeout: 10_000 });
		});
	});

	test('the external Strava link is a real off-site tab, not an internal nav trap', async ({
		page,
	}) => {
		// A converting visitor may also click out to verify Strava's price
		// themselves. That link must open off-site safely (new tab +
		// noopener/noreferrer) and NOT hijack the compare tab — otherwise
		// the visitor loses the comparison they were reading.
		// compare/+page.svelte:110-114.
		await page.goto('/compare');
		const stravaLink = page.locator('.cmp-footer a[href*="strava.com"]').first();
		await expect(stravaLink).toBeVisible();
		expect(await stravaLink.getAttribute('target')).toBe('_blank');
		const rel = (await stravaLink.getAttribute('rel')) ?? '';
		expect(rel).toContain('noopener');
		expect(rel).toContain('noreferrer');
		// Clicking it must NOT change the compare page's own URL.
		await stravaLink.click();
		await expect(page).toHaveURL(/\/compare$/);
	});
});

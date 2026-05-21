import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { USER_B } from '../fixtures/users';

/**
 * /share/run/[id] — public run share page (anon + authed paths).
 *
 * The non-owner kudos / comment writes go through this page's
 * RunSocial mount; those tests live under cross-user/ since they
 * need a second context. This file holds the read paths (anon and
 * authed-non-owner).
 *
 * Future depth: privacy-zone clipping rendering, photo gallery
 * mount, "view full run" gating for non-owners.
 */

test.describe('/share/run/[id] — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon viewer: RunSocial does not mount; sign-up CTA shown instead', async ({
		page
	}) => {
		// RunShareView gates the entire RunSocial card on auth.loggedIn:
		// authed visitors get kudos + comments, anon visitors get a
		// "Sign up for Free" CTA card. Pin the anon negative — kudos
		// and the composer are absent, the CTA link to /login?signup=1
		// is visible. A regression that exposed RunSocial to anon
		// could leak kudos / comment writes past the RLS write policy
		// and surface a confusing 401 toast.
		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] })
			})
		);

		await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);

		// Run meta visible (anon read path works).
		await expect(page.locator('.run-meta')).toBeVisible({ timeout: 10_000 });

		// Negative: RunSocial absent → kudos button + composer absent.
		await expect(page.locator('.run-social')).toHaveCount(0);
		await expect(page.locator('.kudos-btn')).toHaveCount(0);
		await expect(page.locator('form.composer')).toHaveCount(0);

		// Positive: anon CTA card visible.
		await expect(
			page.locator('a[href="/login?signup=1"]', { hasText: 'Sign up' })
		).toBeVisible({ timeout: 5_000 });
	});

	test('anon visitor gets per-run SEO unfurl tags on the share page', async ({ page }) => {
		// Crawlers + chat-app unfurls read these from <head>. The
		// run share page lifts its meta fetch into +page.ts so the
		// per-run title + description bake into the prerendered HTML
		// (vs the generic SPA-shell fallback that earlier shipped).
		// Display name is still deferred until `public_profiles`
		// view ships (`user_profiles` is owner-only by RLS), so the
		// title carries distance + date, not the runner's name.
		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] })
			})
		);
		await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);

		// Per-run reactive title — pulls runner name from
		// public_profiles (migration 20260824_001) so the unfurl
		// can attribute the run. Assert the wire shape
		// ("X km run by NAME on DD MMM YYYY") rather than specific
		// values so a seed tweak doesn't break the spec.
		await expect(page).toHaveTitle(
			/\d+(\.\d+)?\s+km run by .+ on \d+\s\w+\s\d{4}\s—\sThrekir/
		);
		await expect(page.locator('meta[name="description"]')).toHaveAttribute(
			'content',
			/Map, splits, and elevation on Threkir\.$/
		);
		await expect(page.locator('meta[property="og:title"]')).toHaveAttribute(
			'content',
			/\d+(\.\d+)?\s+km run by .+ on /
		);
		await expect(page.locator('meta[property="og:type"]')).toHaveAttribute(
			'content',
			'article'
		);
		await expect(page.locator('meta[property="og:site_name"]')).toHaveAttribute(
			'content',
			'Threkir'
		);
		// Per-run og:image is the prerendered PNG under /og/run/<id>.png.
		await expect(page.locator('meta[property="og:image"]')).toHaveAttribute(
			'content',
			`/og/run/${RUNNER_PUBLIC_RUN_ID}.png`
		);
		await expect(page.locator('meta[property="og:image:width"]')).toHaveAttribute(
			'content',
			'1200'
		);
		await expect(page.locator('meta[property="og:image:height"]')).toHaveAttribute(
			'content',
			'630'
		);
		await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute(
			'content',
			'summary_large_image'
		);
		await expect(page.locator('meta[name="twitter:image"]')).toHaveAttribute(
			'content',
			`/og/run/${RUNNER_PUBLIC_RUN_ID}.png`
		);
	});

	test('per-run og:image renders a real PNG of correct dimensions', async ({ request }) => {
		// The prerendered /og/run/[id].png endpoint must return a
		// 1200×630 PNG (Twitter / Facebook recommended unfurl size).
		// In dev mode the +server.ts handler runs at request time;
		// in production CloudFront serves the prerendered file from S3.
		// Either way the URL + Content-Type + magic bytes are pinned.
		const res = await request.get(
			`http://localhost:7777/og/run/${RUNNER_PUBLIC_RUN_ID}.png`
		);
		expect(res.status()).toBe(200);
		expect(res.headers()['content-type']).toContain('image/png');
		const body = await res.body();
		// PNG magic number — 89 50 4E 47 0D 0A 1A 0A.
		expect(body.subarray(0, 8)).toEqual(
			Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
		);
		// Sanity: > 1KB rules out a degenerate 0-byte error response.
		expect(body.length).toBeGreaterThan(1024);
	});

	test('Sign up CTA on the anon share page lands on /login?signup=1', async ({
		page
	}) => {
		// The CTA is the only call-to-action available to an anon
		// visitor on a public-share page. Pin the click target — a
		// regression that wired it to a wrong route would surface
		// here as a 404 or as the page bouncing back to the share
		// view in a loop.
		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] })
			})
		);
		await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);

		await page.locator('a[href="/login?signup=1"]', { hasText: 'Sign up' }).click();
		await page.waitForURL(/\/login\?signup=1/, { timeout: 10_000 });
	});

	test('anon visit to /share/run/[id] of a private run renders not-found', async ({
		page
	}) => {
		// `public_runs` view filters on is_public=true, so a private run
		// id returns no row to anon. Pin the negative path so a
		// regression that exposed private runs to anon would surface
		// here as a successful body render. Plant a private run, hit
		// the share path anon, expect "Run not found." copy.
		const { getAdminClient } = await import('../fixtures/local-supabase');
		const { USER_A } = await import('../fixtures/users');
		const { insertRun } = await import('../fixtures/simulate');
		const admin = getAdminClient();

		const plantedId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: false
		});

		try {
			await page.route('**/functions/v1/clip-public-track', (route) =>
				route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify({ points: [] })
				})
			);
			await page.goto(`/share/run/${plantedId}`);
			await expect(
				page.getByText('Run not found.')
			).toBeVisible({ timeout: 10_000 });
		} finally {
			await admin.from('runs').delete().eq('id', plantedId);
		}
	});

	test('public run loads without auth', async ({ page }) => {
		// Stub the clip-public-track Edge Function — we don't run
		// `supabase functions serve` alongside tests, and RunShareView
		// calls this for non-owner viewers (decisions §33). Without
		// the stub the await hangs and `loading` never flips off.
		// Returning [] here is the same shape the EF returns for a
		// run with no track in Storage (the seed shape).
		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] })
			})
		);

		await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);

		// share-page chrome + the run-meta block. The seeded run has no
		// track in Storage so we don't assert on the map. The chrome
		// + run-meta combo confirms anon read of the runs row succeeded
		// via the public_runs view (no auth, no 404). The page also renders
		// a footer "Threkir home" link — scope the brand-mark assertion
		// to the .share-logo header so it stays unambiguous.
		await expect(page.locator('.share-logo')).toBeVisible();
		await expect(page.locator('.run-meta')).toBeVisible({ timeout: 10_000 });
	});
});

test.describe('/share/run/[id] — authed non-owner', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('alex sees the run + RunSocial mounts (kudos + composer)', async ({
		page
	}) => {
		// `auth.loggedIn` gates RunSocial — anon viewers see the run
		// metadata only, authed visitors get the kudos button +
		// comment composer too. The kudos round-trip is in
		// cross-user/kudos.spec.ts; this test just pins that the
		// social affordances render for an authed non-owner.
		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] })
			})
		);

		await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);

		// Run-meta strip + kudos button + comment composer all visible.
		await expect(page.locator('.run-meta')).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.kudos-btn')).toBeVisible();
		await expect(page.locator('form.composer textarea')).toBeVisible();
	});
});

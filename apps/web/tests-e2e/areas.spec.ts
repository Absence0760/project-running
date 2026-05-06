import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from './fixtures/seeded-data';
import { USER_A } from './fixtures/users';

/**
 * Areas spec — broad coverage sweep, one test per uncovered route.
 *
 * Smoke / security / data-flow / happy-paths / interactions / flows
 * cover the high-traffic surfaces in depth. This spec catches the
 * "did this entire area break?" failure mode for the rest of the
 * app — landing, feed, plans, clubs, coach, settings sub-pages,
 * live spectator. Each test is thin: it asserts the page mounts +
 * renders something seed-specific so a 500, a missing fetch, or
 * an empty render fails fast. Future rounds deepen each area.
 *
 * Eight describe blocks, one per uncovered area:
 *   - Landing (/)            — anon hero + CTA links.
 *   - Feed (/feed)           — User A sees seeded follows' runs.
 *   - Plans (/plans)         — Sydney Half 2026 plan card visible.
 *   - Clubs (/clubs)         — Sydney Run Club card visible.
 *   - Coach (/coach)         — chat surface mounts.
 *   - Settings/integrations  — Strava + parkrun rows visible.
 *   - Settings/upgrade       — Pro card pricing visible.
 *   - Live spectator (/live) — anon shell mounts with status badge.
 */

test.describe('Landing page (anon)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('hero + Get Started CTA render for an unauthenticated visitor', async ({
		page
	}) => {
		// `/` runs an $effect that goto's /dashboard for authed users.
		// For anon, `showLanding` is true and the marketing hero
		// renders. The h1 is split across <br/>s; the accessible name
		// is the concatenated text "Plan routes. Track runs. Analyse
		// everything." Match by the leading phrase.
		await page.goto('/');
		await page.waitForLoadState('networkidle');

		await expect(
			page.getByRole('heading', { name: /Plan routes/, level: 1 })
		).toBeVisible();
		await expect(
			page.getByRole('link', { name: 'Get Started' })
		).toBeVisible();
	});
});

test.describe('Feed (/feed)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('User A sees a non-empty feed (seeded follows have public runs)', async ({
		page
	}) => {
		// Runner follows alex (USER_B) + morgan (USER_C_PRO). The seed
		// gives each ~12-13 recent public runs all within the
		// FEED_WINDOW_DAYS=14 window from 2026-04-27, so the feed is
		// expected to render at least a handful of entries — never
		// the empty state. Empty would mean either the follow graph
		// dropped, the public_runs view broke, or the date window
		// regressed.
		await page.goto('/feed');
		await page.waitForLoadState('networkidle');

		// Should NOT see any of the empty-state headings.
		await expect(page.getByRole('heading', { name: 'Your feed is empty' })).toHaveCount(0);
		await expect(page.getByRole('heading', { name: 'No recent activity' })).toHaveCount(0);

		// Should see at least one entry — feed cards are rendered as
		// buttons that open a RunShareView modal. The seeded authors
		// "Alex Chen" + "Morgan Lee" appear inline as the entry author
		// label; assert at least one is visible.
		const authorLabels = page.getByText(/Alex Chen|Morgan Lee/);
		await expect(authorLabels.first()).toBeVisible({ timeout: 10_000 });
	});
});

test.describe('Plans (/plans)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the seeded Sydney Half 2026 plan card renders + links to detail', async ({
		page
	}) => {
		// seed.sql provisions a single active training_plan named
		// "Sydney Half 2026" with id a1a1eada-aaaa-... A regression
		// in the planlist fetch (RLS, query, or rendering) would
		// surface as the empty state instead. The card links to
		// /plans/<id> via an outer <a>, so we can also navigate
		// through it to confirm /plans/[id] mounts.
		await page.goto('/plans');
		await page.waitForLoadState('networkidle');

		await expect(
			page.getByRole('heading', { name: 'No plans yet.' })
		).toHaveCount(0);
		await expect(
			page.getByRole('heading', { name: 'Sydney Half 2026' })
		).toBeVisible({ timeout: 10_000 });

		// Drill into the plan detail to prove /plans/[id] also mounts.
		await page.getByRole('link', { name: /Sydney Half 2026/ }).click();
		await expect(page).toHaveURL(/\/plans\/[0-9a-f-]+$/);
		await page.waitForLoadState('networkidle');
		// /plans/[id] renders the plan name as a heading too.
		await expect(
			page.getByRole('heading', { name: /Sydney Half 2026/ })
		).toBeVisible({ timeout: 10_000 });
	});
});

test.describe('Clubs (/clubs)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('seeded Sydney Run Club card renders + links to detail', async ({
		page
	}) => {
		// Runner owns three seeded clubs (Sydney Run Club / Tempo
		// Tuesday / Friends of Jared). Empty state would mean the
		// browse fetch broke; "Friends of Jared" is private but
		// runner is the owner so it surfaces in their list.
		await page.goto('/clubs');
		await page.waitForLoadState('networkidle');

		await expect(
			page.getByRole('heading', { name: 'Sydney Run Club' })
		).toBeVisible({ timeout: 10_000 });

		// Drill into the slug-routed detail page.
		await page.getByRole('link', { name: /Sydney Run Club/ }).click();
		await expect(page).toHaveURL(/\/clubs\/sydney-run-club/);
		await page.waitForLoadState('networkidle');
	});
});

test.describe('Coach (/coach)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('chat surface mounts (no LLM call)', async ({ page }) => {
		// /coach mounts CoachChat which loads conversation history
		// and binds the input. We don't actually exercise the LLM
		// — that would need a stub for the SSE endpoint — just
		// verify the page mounts past the "Loading…" state and the
		// composer textarea is wired up.
		await page.goto('/coach');
		await page.waitForLoadState('networkidle');

		// CoachChat's input has a placeholder starting with "Ask
		// about today, pace, adherence…" — see CoachChat.svelte.
		const composer = page.getByPlaceholder(/Ask about today/);
		await expect(composer).toBeVisible({ timeout: 10_000 });
	});
});

test.describe('Settings / Integrations', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('integration list renders Strava + parkrun + Garmin rows', async ({
		page
	}) => {
		// The integrations page lists three providers regardless of
		// connection state. Runner's seed has parkrun + strava
		// connected (last_sync_at populated); garmin is unconnected.
		// All three rows must appear — the list is built from a
		// hardcoded array, but the connection state comes from a
		// query, so a regression there could break the page render.
		await page.goto('/settings/integrations');
		await page.waitForLoadState('networkidle');

		await expect(
			page.getByRole('heading', { name: 'Strava', exact: true })
		).toBeVisible();
		await expect(
			page.getByRole('heading', { name: 'parkrun', exact: true })
		).toBeVisible();
		await expect(
			page.getByRole('heading', { name: 'Garmin Connect', exact: true })
		).toBeVisible();
	});
});

test.describe('Settings / Upgrade', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('Pro pricing card renders for a free user', async ({ page }) => {
		// USER_A is on the free tier. The page renders the Pro card
		// with the monthly price. A regression would either crash
		// the page (PRO_PRICE_MONTHLY import broken) or the active
		// state would flip incorrectly (lock_subscription_columns
		// trigger + RPC drift).
		await page.goto('/settings/upgrade');
		await page.waitForLoadState('networkidle');

		// `exact: true` because case-insensitive substring matching
		// otherwise pulls in "Support the project" (contains "pro").
		await expect(
			page.getByRole('heading', { name: 'Pro', exact: true })
		).toBeVisible();
		// Monthly price is rendered as $N / month — assert the
		// "/ month" half is present (PRO_PRICE_MONTHLY is a number
		// constant, so the literal is robust to price changes).
		await expect(page.getByText('/ month')).toBeVisible();
	});
});

test.describe('Live spectator (/live/[id]) — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visit to a public run live page mounts with status badge', async ({
		page
	}) => {
		// /live/[id] is a public path (auth guard's isPublic includes
		// /live/). Without active broadcast pings the badge stays
		// "Connecting..." then transitions to "Demo" after the
		// in-page timer fires. We just assert the shell mounts —
		// the brand label, badge container, and stat tiles all
		// exist regardless of connection state.
		await page.goto(`/live/${RUNNER_PUBLIC_RUN_ID}`);
		await page.waitForLoadState('networkidle');

		await expect(page.locator('.live-logo')).toContainText('Run Onward');
		await expect(page.locator('.live-badge')).toBeVisible();
		// Three stat tiles: Distance / Elapsed / Pace.
		await expect(page.locator('.live-stat-label')).toHaveCount(3);
	});
});

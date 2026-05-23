import { expect, test } from '@playwright/test';

import {
	ALEX_PRIVATE_RUN_ID,
	RUNNER_PUBLIC_RUN_ID,
	RUNNER_PUBLIC_ROUTE_ID
} from '../fixtures/seeded-data';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Surface-level detail tests — small focused checks on individual
 * page chrome, key affordances, and nav round-trips. Each one is
 * cheap and pins one assertion. Together they form a wide net for
 * regressions that don't touch a journey's happy path but do affect
 * "does the page actually look like a working page".
 */

test.describe('detail surface — runs', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/runs/[id] back-link navigates to /runs', async ({ page }) => {
		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);
		await page.getByRole('link', { name: /All runs/ }).first().click();
		await page.waitForURL(/\/runs(\?.*)?$/, { timeout: 10_000 });
	});

	test('/runs/[id] share button is visible for the owner', async ({ page }) => {
		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);
		// Share-as-image icon button.
		await expect(
			page.locator('button[title="Share as image"]')
		).toBeVisible({ timeout: 10_000 });
	});

	test('/runs/[id] delete-trash button is visible for the owner', async ({
		page
	}) => {
		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);
		await expect(page.locator('button[title="Delete"]'))
			.toBeVisible({ timeout: 10_000 });
	});
});

test.describe('detail surface — routes', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/routes/[id] back-link returns to /routes', async ({ page }) => {
		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.getByRole('link', { name: /My routes|Routes|Explore/ })
			.first()
			.click();
		await page.waitForURL(/\/routes(\?.*)?$/, { timeout: 10_000 });
	});

	test('/routes/[id] tag-add input is visible for the owner', async ({ page }) => {
		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);
		await expect(page.locator('.tag-add input[type="text"]'))
			.toBeVisible({ timeout: 10_000 });
	});
});

test.describe('detail surface — plans', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/plans/<seeded> renders the progress ring', async ({ page }) => {
		await page.goto('/plans/a1a1eada-aaaa-0000-0000-000000000001');
		await expect(page.locator('.progress-ring .pct'))
			.toBeVisible({ timeout: 10_000 });
	});

	test('/plans/<seeded> renders the today card OR the multi-week grid', async ({
		page
	}) => {
		await page.goto('/plans/a1a1eada-aaaa-0000-0000-000000000001');
		// Wait for the plan heading to mount before checking the
		// downstream widgets.
		await expect(
			page.getByRole('heading', { level: 1, name: /Richmond Half/ })
		).toBeVisible({ timeout: 10_000 });
		// At least one of: today-link OR a week article.
		await expect(
			page.locator('.today-link, .weeks .week').first()
		).toBeVisible({ timeout: 10_000 });
	});

	test('/plans/<seeded> publish-row is visible to the plan owner', async ({
		page
	}) => {
		// Runner owns the seeded Richmond Half plan and admins three
		// clubs, so the publish-row renders.
		await page.goto('/plans/a1a1eada-aaaa-0000-0000-000000000001');
		await expect(page.locator('.publish-row'))
			.toBeVisible({ timeout: 10_000 });
	});
});

test.describe('detail surface — clubs', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/clubs/richmond-run-club renders the Members tab', async ({ page }) => {
		await page.goto('/clubs/richmond-run-club');
		await expect(page.getByRole('tab', { name: /^Members/ }))
			.toBeVisible({ timeout: 10_000 });
	});

	test('/clubs/richmond-run-club Events tab lists at least one event', async ({
		page
	}) => {
		await page.goto('/clubs/richmond-run-club');
		await page.getByRole('tab', { name: /^Events/ }).click();
		// Seed has 3 upcoming events on Richmond Run Club.
		await expect(page.locator('a[href*="/events/"]').first())
			.toBeVisible({ timeout: 10_000 });
	});

	test('/clubs/richmond-run-club Routes tab is reachable', async ({ page }) => {
		await page.goto('/clubs/richmond-run-club');
		await page.getByRole('tab', { name: /^Routes/ }).click();
		// The routes panel may be empty in seed, but the tab switch
		// shouldn't error — just verify we left the feed view.
		await expect(page.locator('article.post')).toHaveCount(0);
	});

	test('/clubs/richmond-run-club Templates tab is reachable', async ({ page }) => {
		await page.goto('/clubs/richmond-run-club');
		await page.getByRole('tab', { name: /^Templates/ }).click();
		// Same shape — no posts visible after the tab change.
		await expect(page.locator('article.post')).toHaveCount(0);
	});
});

test.describe('detail surface — profile', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/u/[me] runs tab lists at least one recent public run', async ({
		page
	}) => {
		await page.goto(`/u/${USER_A.id}`);
		// Default tab is "runs" — seed has multiple public runs for
		// runner.
		await expect(page.locator('.run-row, .run-card').first())
			.toBeVisible({ timeout: 10_000 });
	});

	test('/u/[other] runs tab shows the other user\'s public runs', async ({
		page
	}) => {
		await page.goto(`/u/${USER_B.id}`);
		// Alex has at least one public run in the seed.
		await expect(page.locator('.run-row, .run-card').first())
			.toBeVisible({ timeout: 10_000 });
	});
});

test.describe('detail surface — feed', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/feed renders at least one feed card from the seeded follow graph', async ({
		page
	}) => {
		await page.goto('/feed');
		// Runner follows alex; alex has public runs in the seed →
		// feed should not be empty.
		await expect(page.locator('.feed-card, .run-card, article').first())
			.toBeVisible({ timeout: 10_000 });
	});
});

test.describe('cross-user run isolation — extra', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('runner cannot read alex\'s private run via direct URL', async ({
		page
	}) => {
		// RLS hides alex's private run from runner — page lands on
		// the not-found branch.
		await page.goto(`/runs/${ALEX_PRIVATE_RUN_ID}`);
		await expect(
			page.getByRole('heading', { name: 'Run not found' })
		).toBeVisible({ timeout: 10_000 });
	});
});

test.describe('navigation — sidebar links wire up', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('clicking sidebar nav links lands on the right URL', async ({
		page
	}) => {
		// Sidebar shape: Dashboard · History · Routes · Coach · Social.
		// Plans moved off the sidebar to be reached from the dashboard
		// today-card. Feed + People + Clubs collapsed under /social.
		// Guided runs surfaces from /coach. Settings is in the profile
		// popover.
		await page.goto('/dashboard');
		const sidebar = page.locator('.sidebar');
		await sidebar.getByRole('link', { name: /History/ }).click();
		await expect(page).toHaveURL(/\/runs(\?.*)?$/, { timeout: 10_000 });
		await sidebar.getByRole('link', { name: /Routes/ }).click();
		await expect(page).toHaveURL(/\/routes(\?.*)?$/, { timeout: 10_000 });
		await sidebar.getByRole('link', { name: /Coach/ }).click();
		await expect(page).toHaveURL(/\/coach(\?.*)?$/, { timeout: 10_000 });
		await sidebar.getByRole('link', { name: /Social/ }).click();
		await expect(page).toHaveURL(/\/social(\?.*)?$/, { timeout: 10_000 });
		// Settings is in the profile popover, not in the main nav.
		await expect(sidebar.getByRole('link', { name: /^Settings$/ })).toHaveCount(0);
		// Feed + Guided runs + the old top-level Clubs link moved off
		// the sidebar.
		await expect(sidebar.getByRole('link', { name: /^Feed$/ })).toHaveCount(0);
		await expect(sidebar.getByRole('link', { name: /^Guided runs$/ })).toHaveCount(0);
		await expect(sidebar.getByRole('link', { name: /^Clubs$/ })).toHaveCount(0);
	});
});

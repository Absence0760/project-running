import { expect, test, type Page } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /runs/new — standalone manual-run wrapper around RunEditor.
 *
 * The same RunEditor is mounted in a modal from /runs (covered by
 * runs/list.spec.ts). This standalone surface is the deep-linkable
 * version — kept as a thin page wrapper so /runs/new opens cleanly
 * from a back-button history or an external link.
 *
 * Source semantics: createManualRun() pins source='app' and stamps
 * metadata.manual_entry=true. The CHECK constraint on runs_source
 * does not accept 'manual'. The metadata flag is the discriminator
 * downstream readers use to distinguish manual entries from recorded
 * ones; the contract pinned here is (source='app' AND
 * metadata.manual_entry === true).
 */

const plantedRunIds: string[] = [];

async function cleanupPlantedRuns(): Promise<void> {
	if (plantedRunIds.length === 0) return;
	const admin = getAdminClient();
	await admin.from('runs').delete().in('id', plantedRunIds);
	plantedRunIds.length = 0;
}

async function captureCreatedRunId(page: Page): Promise<string> {
	await page.waitForURL(/\/runs\/[0-9a-f-]+$/, { timeout: 15_000 });
	const id = page.url().match(/\/runs\/([0-9a-f-]+)$/)![1];
	plantedRunIds.push(id);
	return id;
}

test.describe('/runs/new', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		await cleanupPlantedRuns();
	});

	test('renders page chrome (kicker, h1, tagline, back link)', async ({ page }) => {
		await page.goto('/runs/new');

		await expect(page.getByText('New run', { exact: true })).toBeVisible({
			timeout: 10_000
		});
		await expect(
			page.getByRole('heading', { level: 1, name: 'Add a run' })
		).toBeVisible();
		await expect(
			page.getByText(/Manually log a run the app didn't record/)
		).toBeVisible();
		await expect(
			page.getByRole('link', { name: /Back to runs/ })
		).toHaveAttribute('href', '/runs');
	});

	test('save round-trip: fill form → submit → /runs/[id] with correct shape', async ({
		page
	}) => {
		const admin = getAdminClient();
		await page.goto('/runs/new');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Add a run' })
		).toBeVisible({ timeout: 10_000 });

		await page.getByRole('radio', { name: 'Walk', exact: true }).click();

		const numberInputs = page.locator('input[type="number"]');
		await numberInputs.nth(0).fill('3.14');
		await numberInputs.nth(1).fill('25');

		await page.getByRole('button', { name: /Save/ }).click();

		const newId = await captureCreatedRunId(page);

		const { data: row } = await admin
			.from('runs')
			.select('user_id, distance_m, duration_s, source, metadata')
			.eq('id', newId)
			.single();
		expect(row?.user_id).toBe(USER_A.id);
		expect(Math.round((row?.distance_m as number) ?? 0)).toBe(3140);
		expect(row?.duration_s).toBe(25 * 60);
		expect(row?.source).toBe('app');
		const meta = row?.metadata as Record<string, unknown>;
		expect(meta?.activity_type).toBe('walk');
		expect(meta?.manual_entry).toBe(true);
	});

	test('submit with zero distance is blocked (no row, no navigation)', async ({
		page
	}) => {
		const admin = getAdminClient();
		const beforeCount = await admin
			.from('runs')
			.select('id', { count: 'exact', head: true })
			.eq('user_id', USER_A.id);

		await page.goto('/runs/new');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Add a run' })
		).toBeVisible({ timeout: 10_000 });

		const numberInputs = page.locator('input[type="number"]');
		await numberInputs.nth(0).fill('0');
		await numberInputs.nth(1).fill('25');

		await page.getByRole('button', { name: /Save/ }).click();

		await page.waitForTimeout(500);
		await expect(page).toHaveURL(/\/runs\/new$/);

		const afterCount = await admin
			.from('runs')
			.select('id', { count: 'exact', head: true })
			.eq('user_id', USER_A.id);
		expect(afterCount.count).toBe(beforeCount.count);
	});

	test('submit with zero duration is blocked (no row, no navigation)', async ({
		page
	}) => {
		const admin = getAdminClient();
		const beforeCount = await admin
			.from('runs')
			.select('id', { count: 'exact', head: true })
			.eq('user_id', USER_A.id);

		await page.goto('/runs/new');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Add a run' })
		).toBeVisible({ timeout: 10_000 });

		const numberInputs = page.locator('input[type="number"]');
		await numberInputs.nth(0).fill('5');
		await numberInputs.nth(1).fill('0');
		await numberInputs.nth(2).fill('0');

		await page.getByRole('button', { name: /Save/ }).click();

		await page.waitForTimeout(500);
		await expect(page).toHaveURL(/\/runs\/new$/);

		const afterCount = await admin
			.from('runs')
			.select('id', { count: 'exact', head: true })
			.eq('user_id', USER_A.id);
		expect(afterCount.count).toBe(beforeCount.count);
	});

	test('negative duration is rejected by the min=0 input or clamped to zero', async ({
		page
	}) => {
		const admin = getAdminClient();
		const beforeCount = await admin
			.from('runs')
			.select('id', { count: 'exact', head: true })
			.eq('user_id', USER_A.id);

		await page.goto('/runs/new');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Add a run' })
		).toBeVisible({ timeout: 10_000 });

		const numberInputs = page.locator('input[type="number"]');
		await numberInputs.nth(0).fill('5');
		await numberInputs.nth(1).fill('-10');

		await page.getByRole('button', { name: /Save/ }).click();

		await page.waitForTimeout(500);
		await expect(page).toHaveURL(/\/runs\/new$/);

		const afterCount = await admin
			.from('runs')
			.select('id', { count: 'exact', head: true })
			.eq('user_id', USER_A.id);
		expect(afterCount.count).toBe(beforeCount.count);
	});

	test('distance accepts decimal km values (5.27 km → 5270 m)', async ({
		page
	}) => {
		const admin = getAdminClient();
		await page.goto('/runs/new');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Add a run' })
		).toBeVisible({ timeout: 10_000 });

		const numberInputs = page.locator('input[type="number"]');
		await numberInputs.nth(0).fill('5.27');
		await numberInputs.nth(1).fill('30');

		await page.getByRole('button', { name: /Save/ }).click();
		const newId = await captureCreatedRunId(page);

		const { data: row } = await admin
			.from('runs')
			.select('distance_m')
			.eq('id', newId)
			.single();
		expect(Math.round((row?.distance_m as number) ?? 0)).toBe(5270);
	});

	test('activity defaults to Run and persists to metadata.activity_type', async ({
		page
	}) => {
		const admin = getAdminClient();
		await page.goto('/runs/new');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Add a run' })
		).toBeVisible({ timeout: 10_000 });

		await expect(
			page.getByRole('radio', { name: 'Run', exact: true })
		).toHaveAttribute('aria-checked', 'true');

		const numberInputs = page.locator('input[type="number"]');
		await numberInputs.nth(0).fill('4');
		await numberInputs.nth(1).fill('20');
		await page.getByRole('button', { name: /Save/ }).click();
		const newId = await captureCreatedRunId(page);

		const { data: row } = await admin
			.from('runs')
			.select('metadata')
			.eq('id', newId)
			.single();
		expect((row?.metadata as Record<string, unknown>)?.activity_type).toBe(
			'run'
		);
	});

	for (const activity of ['walk', 'hike', 'cycle'] as const) {
		test(`activity chip "${activity}" persists to metadata.activity_type`, async ({
			page
		}) => {
			const admin = getAdminClient();
			await page.goto('/runs/new');
			await expect(
				page.getByRole('heading', { level: 1, name: 'Add a run' })
			).toBeVisible({ timeout: 10_000 });

			const chipLabel =
				activity.charAt(0).toUpperCase() + activity.slice(1);
			await page.getByRole('radio', { name: chipLabel, exact: true }).click();
			await expect(
				page.getByRole('radio', { name: chipLabel, exact: true })
			).toHaveAttribute('aria-checked', 'true');

			const numberInputs = page.locator('input[type="number"]');
			await numberInputs.nth(0).fill('4');
			await numberInputs.nth(1).fill('20');
			await page.getByRole('button', { name: /Save/ }).click();
			const newId = await captureCreatedRunId(page);

			const { data: row } = await admin
				.from('runs')
				.select('metadata')
				.eq('id', newId)
				.single();
			expect(
				(row?.metadata as Record<string, unknown>)?.activity_type
			).toBe(activity);
		});
	}

	test('source field defaults to "app" (manual_entry flag is the discriminator)', async ({
		page
	}) => {
		// The CHECK constraint runs_source_check does not allow 'manual'.
		// Manual entries land as source='app' with metadata.manual_entry=true
		// — that's the pinned contract.
		const admin = getAdminClient();
		await page.goto('/runs/new');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Add a run' })
		).toBeVisible({ timeout: 10_000 });

		const numberInputs = page.locator('input[type="number"]');
		await numberInputs.nth(0).fill('2.5');
		await numberInputs.nth(1).fill('15');
		await page.getByRole('button', { name: /Save/ }).click();
		const newId = await captureCreatedRunId(page);

		const { data: row } = await admin
			.from('runs')
			.select('source, metadata')
			.eq('id', newId)
			.single();
		expect(row?.source).toBe('app');
		expect((row?.metadata as Record<string, unknown>)?.manual_entry).toBe(
			true
		);
	});

	test('URL query params do not prefill the form (no-prefill contract)', async ({
		page
	}) => {
		// /runs/new does not read URL query for prefill today. Pinning the
		// no-prefill contract here so a future change that adds prefill
		// must update this test deliberately.
		await page.goto('/runs/new?distance=12&activity=hike');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Add a run' })
		).toBeVisible({ timeout: 10_000 });

		const numberInputs = page.locator('input[type="number"]');
		await expect(numberInputs.nth(0)).toHaveValue('5');

		await expect(
			page.getByRole('radio', { name: 'Run', exact: true })
		).toHaveAttribute('aria-checked', 'true');
	});

	test('Started-at defaults to a sensible "now-ish" datetime', async ({
		page
	}) => {
		await page.goto('/runs/new');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Add a run' })
		).toBeVisible({ timeout: 10_000 });

		const startedAt = await page
			.locator('input[type="datetime-local"]')
			.inputValue();
		expect(startedAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/);

		// The browser context's timezone is UTC (playwright config), so
		// the datetime-local value reflects UTC wall-clock. Parse it as
		// UTC explicitly so the comparison doesn't depend on the test
		// runner's TZ.
		const filledTs = new Date(`${startedAt}:00Z`).getTime();
		const now = Date.now();
		expect(Math.abs(now - filledTs)).toBeLessThan(5 * 60 * 1000);
	});

	test('discard mid-form (back-link click) plants no row', async ({ page }) => {
		const admin = getAdminClient();
		const beforeCount = await admin
			.from('runs')
			.select('id', { count: 'exact', head: true })
			.eq('user_id', USER_A.id);

		await page.goto('/runs/new');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Add a run' })
		).toBeVisible({ timeout: 10_000 });

		const numberInputs = page.locator('input[type="number"]');
		await numberInputs.nth(0).fill('7.7');
		await numberInputs.nth(1).fill('45');
		await page.locator('textarea').fill('Should never persist');

		await page.getByRole('link', { name: /Back to runs/ }).click();
		await page.waitForURL(/\/runs(\?.*)?$/, { timeout: 10_000 });

		const afterCount = await admin
			.from('runs')
			.select('id', { count: 'exact', head: true })
			.eq('user_id', USER_A.id);
		expect(afterCount.count).toBe(beforeCount.count);
	});

	test('round-trip → /runs/[id] shows the new run + correct distance', async ({
		page
	}) => {
		const admin = getAdminClient();
		await page.goto('/runs/new');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Add a run' })
		).toBeVisible({ timeout: 10_000 });

		const numberInputs = page.locator('input[type="number"]');
		await numberInputs.nth(0).fill('10');
		await numberInputs.nth(1).fill('50');
		await page.getByRole('button', { name: /Save/ }).click();
		const newId = await captureCreatedRunId(page);

		// Race guard: next read is a service-role SELECT (no Playwright
		// auto-wait). Without the network-idle pause it can fire before
		// the client-side INSERT lands.
		await page.waitForLoadState('networkidle');

		const { data: row } = await admin
			.from('runs')
			.select('distance_m, duration_s, user_id')
			.eq('id', newId)
			.single();
		expect(row?.user_id).toBe(USER_A.id);
		expect(Math.round((row?.distance_m as number) ?? 0)).toBe(10_000);
		expect(row?.duration_s).toBe(50 * 60);
	});
});

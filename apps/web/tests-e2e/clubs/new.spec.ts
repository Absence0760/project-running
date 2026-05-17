import { expect, test, type Page } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/new — standalone wrapper around <ClubEditor>.
 *
 * The same editor is also mounted in a modal from /social?tab=clubs.
 * The slug-routed clubs page (/clubs/[slug]) is where round-trip
 * verification lands. Tests here cover:
 *
 *  - page chrome (kicker / h1 / tagline / back-link to social)
 *  - visibility × join-policy matrix (public/open, public/request,
 *    private/invite — public+invite is auto-coerced back to open)
 *  - slug generation + round-trip to /clubs/[slug]
 *  - viewer auto-enrolled as owner via enroll_club_owner_trigger
 *  - discard mid-form (back-link) plants no row
 */

const plantedClubIds: string[] = [];

async function cleanupPlantedClubs(): Promise<void> {
	if (plantedClubIds.length === 0) return;
	const admin = getAdminClient();
	await admin.from('clubs').delete().in('id', plantedClubIds);
	plantedClubIds.length = 0;
}

const uniqueName = (prefix: string): string =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

async function captureCreatedSlugAndId(page: Page): Promise<{
	slug: string;
	id: string;
}> {
	// Slugs are derived from the uniqueName() format which embeds a
	// timestamp, so the URL is guaranteed to contain a digit. Anchor
	// the regex on that to avoid matching the inflight /clubs/new URL.
	await page.waitForURL(/\/clubs\/[a-z0-9-]*\d[a-z0-9-]*$/, { timeout: 15_000 });
	const slug = page.url().match(/\/clubs\/([a-z0-9-]+)$/)![1];
	expect(slug).not.toBe('new');
	const admin = getAdminClient();
	const { data, error } = await admin
		.from('clubs')
		.select('id')
		.eq('slug', slug)
		.single();
	if (error || !data) {
		throw new Error(
			`captureCreatedSlugAndId: club row for slug "${slug}" not found: ${error?.message}`
		);
	}
	plantedClubIds.push(data.id as string);
	return { slug, id: data.id as string };
}

test.describe('/clubs/new', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		await cleanupPlantedClubs();
	});

	test('renders page chrome (kicker, h1, tagline, back link to /social?tab=clubs)', async ({
		page
	}) => {
		await page.goto('/clubs/new');

		await expect(page.getByText('New club', { exact: true })).toBeVisible({
			timeout: 10_000
		});
		await expect(
			page.getByRole('heading', { level: 1, name: 'Create a club' })
		).toBeVisible();
		await expect(
			page.getByText(/Set up a group for weekly long runs/)
		).toBeVisible();

		const backLink = page.getByRole('link', { name: /Back to clubs/ });
		await expect(backLink).toBeVisible();
		await expect(backLink).toHaveAttribute('href', '/social?tab=clubs');
	});

	test('public + open → joinable immediately (viewer auto-enrolled as owner)', async ({
		page
	}) => {
		const admin = getAdminClient();
		const name = uniqueName('e2e-public-open');

		await page.goto('/clubs/new');
		await page.locator('input[type="text"]').first().fill(name);
		await page.locator('input[type="text"]').nth(1).fill('Sydney, AU');
		await page.locator('textarea').fill('Public + open weekly meetup');

		await page.getByRole('button', { name: 'Create club' }).click();
		const { slug, id } = await captureCreatedSlugAndId(page);

		const { data: row } = await admin
			.from('clubs')
			.select('name, slug, is_public, join_policy, owner_id, description, location_label')
			.eq('id', id)
			.single();
		expect(row?.name).toBe(name);
		expect(row?.slug).toBe(slug);
		expect(row?.is_public).toBe(true);
		expect(row?.join_policy).toBe('open');
		expect(row?.owner_id).toBe(USER_A.id);
		expect(row?.description).toBe('Public + open weekly meetup');
		expect(row?.location_label).toBe('Sydney, AU');

		const { data: member } = await admin
			.from('club_members')
			.select('role, status')
			.eq('club_id', id)
			.eq('user_id', USER_A.id)
			.single();
		expect(member?.role).toBe('owner');
		expect(member?.status).toBe('active');
	});

	test('public + approval (request) round-trip persists join_policy=request', async ({
		page
	}) => {
		const admin = getAdminClient();
		const name = uniqueName('e2e-public-request');

		await page.goto('/clubs/new');
		await page.locator('input[type="text"]').first().fill(name);

		const policyFieldset = page.locator('fieldset', {
			has: page.locator('legend', { hasText: 'Who can join?' })
		});
		await expect(policyFieldset).toBeVisible();
		await policyFieldset.locator('input[name="policy"]').nth(1).check();

		await page.getByRole('button', { name: 'Create club' }).click();
		const { id } = await captureCreatedSlugAndId(page);

		const { data: row } = await admin
			.from('clubs')
			.select('is_public, join_policy, invite_token')
			.eq('id', id)
			.single();
		expect(row?.is_public).toBe(true);
		expect(row?.join_policy).toBe('request');
		expect(row?.invite_token).toBeNull();
	});

	test('private → join_policy auto-coerced to invite + invite_token generated', async ({
		page
	}) => {
		const admin = getAdminClient();
		const name = uniqueName('e2e-private-invite');

		await page.goto('/clubs/new');
		await page.locator('input[type="text"]').first().fill(name);

		const visFieldset = page.locator('fieldset', {
			has: page.locator('legend', { hasText: 'Visibility' })
		});
		await visFieldset.locator('input[name="vis"]').nth(1).check();

		await expect(
			page.locator('legend', { hasText: 'Who can join?' })
		).toHaveCount(0);

		await page.getByRole('button', { name: 'Create club' }).click();
		const { id } = await captureCreatedSlugAndId(page);

		const { data: row } = await admin
			.from('clubs')
			.select('is_public, join_policy, invite_token')
			.eq('id', id)
			.single();
		expect(row?.is_public).toBe(false);
		expect(row?.join_policy).toBe('invite');
		expect(typeof row?.invite_token).toBe('string');
		expect((row?.invite_token as string).length).toBeGreaterThan(16);
	});

	test('toggling Private then Public coerces join_policy back to open', async ({
		page
	}) => {
		const admin = getAdminClient();
		const name = uniqueName('e2e-toggle');

		await page.goto('/clubs/new');
		await page.locator('input[type="text"]').first().fill(name);

		const visFieldset = page.locator('fieldset', {
			has: page.locator('legend', { hasText: 'Visibility' })
		});
		await visFieldset.locator('input[name="vis"]').nth(1).check();
		await expect(
			page.locator('legend', { hasText: 'Who can join?' })
		).toHaveCount(0);

		await visFieldset.locator('input[name="vis"]').nth(0).check();
		await expect(
			page.locator('legend', { hasText: 'Who can join?' })
		).toBeVisible();

		await page.getByRole('button', { name: 'Create club' }).click();
		const { id } = await captureCreatedSlugAndId(page);

		const { data: row } = await admin
			.from('clubs')
			.select('is_public, join_policy, invite_token')
			.eq('id', id)
			.single();
		expect(row?.is_public).toBe(true);
		expect(row?.join_policy).toBe('open');
		expect(row?.invite_token).toBeNull();
	});

	test('slug is derived from the name and visiting /clubs/[slug] resolves', async ({
		page
	}) => {
		const name = `E2E Slug Club ${Date.now()}`;
		await page.goto('/clubs/new');
		await page.locator('input[type="text"]').first().fill(name);
		await page.getByRole('button', { name: 'Create club' }).click();
		const { slug } = await captureCreatedSlugAndId(page);

		expect(slug).toMatch(/^e2e-slug-club-\d/);

		await expect(
			page.getByRole('heading', { level: 1, name })
		).toBeVisible({ timeout: 10_000 });

		await page.goto(`/clubs/${slug}`);
		await expect(
			page.getByRole('heading', { level: 1, name })
		).toBeVisible({ timeout: 10_000 });
	});

	test('Create-club button is disabled until a name is entered', async ({
		page
	}) => {
		await page.goto('/clubs/new');
		const submit = page.getByRole('button', { name: 'Create club' });
		await expect(submit).toBeDisabled();

		await page.locator('input[type="text"]').first().fill(uniqueName('e2e-disabled'));
		await expect(submit).toBeEnabled();
	});

	test('discard mid-form (back-link) plants no club row', async ({ page }) => {
		const admin = getAdminClient();
		const before = await admin
			.from('clubs')
			.select('id', { count: 'exact', head: true })
			.eq('owner_id', USER_A.id);

		await page.goto('/clubs/new');
		await page
			.locator('input[type="text"]')
			.first()
			.fill(uniqueName('e2e-discard'));
		await page.locator('textarea').fill('Should never persist');

		await page.getByRole('link', { name: /Back to clubs/ }).click();
		await page.waitForURL(/\/social/, { timeout: 10_000 });

		const after = await admin
			.from('clubs')
			.select('id', { count: 'exact', head: true })
			.eq('owner_id', USER_A.id);
		expect(after.count).toBe(before.count);
	});

	test('Cancel button returns to /social?tab=clubs without planting a row', async ({
		page
	}) => {
		const admin = getAdminClient();
		const before = await admin
			.from('clubs')
			.select('id', { count: 'exact', head: true })
			.eq('owner_id', USER_A.id);

		await page.goto('/clubs/new');
		await page
			.locator('input[type="text"]')
			.first()
			.fill(uniqueName('e2e-cancel'));
		await page.getByRole('button', { name: 'Cancel' }).click();
		await page.waitForURL(/\/social/, { timeout: 10_000 });

		const after = await admin
			.from('clubs')
			.select('id', { count: 'exact', head: true })
			.eq('owner_id', USER_A.id);
		expect(after.count).toBe(before.count);
	});
});

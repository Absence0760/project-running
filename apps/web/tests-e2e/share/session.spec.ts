import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /share/session/[id] — public session-plan share page (anon + authed).
 *
 * A public session plan is readable logged-out (the "public session plans are
 * readable" RLS policy gates the anon read on is_public, and the blocks/items
 * inherit-visibility policies expose the children when the parent is public),
 * so this page works for a signed-out viewer. A private plan 404s. A session
 * plan carries no author fitness data, so nothing private leaks past what the
 * author made public.
 */

test.describe('/share/session/[id] — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	let publicPlanId: string | null = null;
	let privatePlanId: string | null = null;
	const stamp = Date.now();
	const title = `E2E Share session ${stamp}`;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { data: pub, error } = await admin
			.from('session_plans')
			.insert({
				author_id: USER_A.id,
				title,
				discipline: 'Vinyasa Yoga',
				equipment: 'Mat',
				is_public: true
			})
			.select('id')
			.single();
		if (error) throw error;
		publicPlanId = (pub as { id: string }).id;
		// per_side must be set on EVERY row: PostgREST aligns the column set
		// across a batch insert, so omitting it on one row (while another sets
		// it) sends an explicit null — and per_side is NOT NULL (default only
		// applies when the column is absent from the whole statement). Leaving
		// it off the first row 23502'd the batch and left the plan item-less.
		const { error: itemsErr } = await admin.from('session_plan_items').insert([
			{
				plan_id: publicPlanId,
				position: 0,
				movement_name: 'Downward Dog',
				kind: 'hold',
				duration_s: 60,
				per_side: false
			},
			{
				plan_id: publicPlanId,
				position: 1,
				movement_name: 'Warrior II',
				kind: 'hold',
				duration_s: 45,
				per_side: true
			}
		]);
		if (itemsErr) throw itemsErr;

		const { data: priv } = await admin
			.from('session_plans')
			.insert({
				author_id: USER_A.id,
				title: `${title} (private)`,
				is_public: false
			})
			.select('id')
			.single();
		privatePlanId = (priv as { id: string }).id;
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		for (const id of [publicPlanId, privatePlanId]) {
			if (id) await admin.from('session_plans').delete().eq('id', id);
		}
	});

	test('anon viewer sees the public session + sign-up CTA', async ({ page }) => {
		await page.goto(`/share/session/${publicPlanId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		// The expanded steps surface: Downward Dog + the per-side Warrior II split
		// into Left / Right rows.
		const steps = page.getByTestId('session-steps');
		await expect(steps).toContainText('Downward Dog');
		await expect(steps).toContainText('Warrior II (Left)');
		await expect(steps).toContainText('Warrior II (Right)');
		// Anon visitors get the sign-up CTA.
		await expect(page.locator('a[href="/login?signup=1"]')).toBeVisible({ timeout: 5_000 });
	});

	test('private session 404s to the not-found state', async ({ page }) => {
		await page.goto(`/share/session/${privatePlanId}`);
		await expect(page.getByText('Session plan not found.')).toBeVisible({ timeout: 10_000 });
		// No sequence list for a hidden plan.
		await expect(page.getByTestId('session-steps')).toHaveCount(0);
	});

	test('the public plan head carries the canonical, OG tags, and JSON-LD', async ({ page }) => {
		await page.goto(`/share/session/${publicPlanId}`);
		await expect(page).toHaveTitle(`${title} — Threkir`);
		await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
			'href',
			new RegExp(`/share/session/${publicPlanId}$`)
		);
		await expect(page.locator('meta[property="og:title"]')).toHaveAttribute(
			'content',
			`${title} — Threkir`
		);
		// Discipline · movement count · duration — never a per-item cue or tempo.
		const desc = await page
			.locator('meta[property="og:description"]')
			.getAttribute('content');
		expect(desc).toContain('Vinyasa Yoga');
		expect(desc).toContain('2 movements');
		expect(desc).toContain('Mat');

		const ld = await page.locator('script[type="application/ld+json"]').first().textContent();
		const obj = JSON.parse(ld as string);
		expect(obj['@type']).toBe('WebPage');
		expect(obj.name).toBe(title);
		expect(obj.breadcrumb['@type']).toBe('BreadcrumbList');
	});

	// Deterministic without a seeded plan: a crawler on a stale link must still
	// get a valid head, never the app shell's generic one.
	test('unknown id still renders a valid SEO head', async ({ page }) => {
		await page.goto('/share/session/00000000-0000-0000-0000-000000000000');
		await expect(page).toHaveTitle('Session — Threkir');
		await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
			'href',
			/\/share\/session\/00000000-0000-0000-0000-000000000000$/
		);
		const ld = await page.locator('script[type="application/ld+json"]').first().textContent();
		expect(JSON.parse(ld as string)['@type']).toBe('WebPage');
	});
});

import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Public plan library — publish → browse → clone round-trip.
 *
 * USER_A publishes a copy of their seeded Richmond Half plan to the
 * public library from /plans/[id]. USER_B (a different account, no club
 * tie) then browses /plans/library, opens the preview, and clones it
 * into their own account — landing on the new plan's detail page. Pins:
 *   1. Publish creates exactly one public-library copy and leaves the
 *      source plan untouched.
 *   2. A stranger can see + preview the public template (RLS).
 *   3. The clone is owned by the stranger, active, parent-linked to the
 *      template, and carries no publisher fitness data.
 */

const SOURCE_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';
const PLAN_NAME = 'Richmond Half 2026';

async function sweepLibrary(): Promise<void> {
	const admin = getAdminClient();
	// Public-library copies of the source plan (by name) + any clones
	// USER_B made off them (parent_template_id points back). Delete the
	// templates first so child clones lose their parent link cleanly;
	// plan_weeks/plan_workouts cascade on the training_plans delete.
	const { data: templates } = await admin
		.from('training_plans')
		.select('id')
		.eq('is_public_template', true)
		.eq('name', PLAN_NAME);
	const tmplIds = (templates ?? []).map((t) => (t as { id: string }).id);
	const { data: clones } = await admin
		.from('training_plans')
		.select('id')
		.eq('user_id', USER_B.id)
		.in('parent_template_id', tmplIds.length > 0 ? tmplIds : ['00000000-0000-0000-0000-000000000000']);
	for (const r of clones ?? []) {
		await admin.from('training_plans').delete().eq('id', (r as { id: string }).id);
	}
	for (const id of tmplIds) {
		await admin.from('training_plans').delete().eq('id', id);
	}
}

test.describe('Public plan library — publish → browse → clone', () => {
	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		await sweepLibrary();
	});

	test.afterEach(async () => {
		await sweepLibrary();
	});

	test('USER_A publishes; USER_B browses, previews, and clones', async ({ browser }) => {
		const admin = getAdminClient();

		// ── USER_A publishes ──
		const ctxA = await browser.newContext({ storageState: USER_A.storageStatePath });
		await ctxA.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		const pageA = await ctxA.newPage();
		await pageA.goto(`/plans/${SOURCE_PLAN_ID}`);
		const libraryRow = pageA
			.locator('.publish-row')
			.filter({ hasText: 'Public plan library' });
		await expect(libraryRow).toBeVisible({ timeout: 10_000 });
		await libraryRow.getByRole('button', { name: 'Publish to library' }).click();
		await expect(libraryRow.getByText('This plan is in the public library.')).toBeVisible({
			timeout: 10_000
		});

		// Exactly one public copy exists; source untouched.
		const { data: templates } = await admin
			.from('training_plans')
			.select('id, is_public_template, is_template, user_id, vdot, current_5k_seconds')
			.eq('is_public_template', true)
			.eq('name', PLAN_NAME);
		expect(templates?.length).toBe(1);
		const tmpl = templates![0] as {
			id: string;
			is_public_template: boolean;
			is_template: boolean;
			user_id: string;
			vdot: number | null;
			current_5k_seconds: number | null;
		};
		expect(tmpl.is_template).toBe(true);
		expect(tmpl.user_id).toBe(USER_A.id);
		expect(tmpl.vdot).toBeNull();
		expect(tmpl.current_5k_seconds).toBeNull();

		const { data: source } = await admin
			.from('training_plans')
			.select('is_template, is_public_template')
			.eq('id', SOURCE_PLAN_ID)
			.maybeSingle();
		expect((source as { is_template: boolean }).is_template).toBe(false);
		expect((source as { is_public_template: boolean }).is_public_template).toBe(false);

		await ctxA.close();

		// ── USER_B browses + clones ──
		const ctxB = await browser.newContext({ storageState: USER_B.storageStatePath });
		await ctxB.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		const pageB = await ctxB.newPage();
		await pageB.goto('/plans/library');
		const card = pageB.locator('.plan-card', { hasText: PLAN_NAME });
		await expect(card).toBeVisible({ timeout: 10_000 });
		await card.click();

		// Preview opened.
		await pageB.waitForURL(/\/plans\/library\/[0-9a-f-]+$/, { timeout: 10_000 });
		await expect(pageB.getByRole('heading', { name: PLAN_NAME })).toBeVisible({
			timeout: 10_000
		});

		// Clone → lands on the new plan's detail page.
		await pageB.getByRole('button', { name: 'Clone into my plans' }).click();
		await pageB.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });

		const { data: clones } = await admin
			.from('training_plans')
			.select('user_id, status, is_template, is_public_template, parent_template_id, vdot, current_5k_seconds')
			.eq('user_id', USER_B.id)
			.eq('parent_template_id', tmpl.id);
		expect(clones?.length).toBe(1);
		const clone = clones![0] as {
			user_id: string;
			status: string;
			is_template: boolean;
			is_public_template: boolean;
			parent_template_id: string;
			vdot: number | null;
			current_5k_seconds: number | null;
		};
		expect(clone.user_id).toBe(USER_B.id);
		expect(clone.status).toBe('active');
		expect(clone.is_template).toBe(false);
		expect(clone.is_public_template).toBe(false);
		expect(clone.parent_template_id).toBe(tmpl.id);
		expect(clone.vdot).toBeNull();
		expect(clone.current_5k_seconds).toBeNull();

		await ctxB.close();
	});
});

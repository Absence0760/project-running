import { expect, test } from '@playwright/test';

import { deletePlan, setPlanStatus } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

const SEED_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

/**
 * /plans full create + abandon + delete UI journey.
 *
 *  1. /plans → "+ New plan" → fill PlanEditor → Create plan.
 *  2. Land on /plans/[id], plan h1 + multi-week grid render — proves
 *     the wizard ran the generator (Riegel → VDOT → week phasing),
 *     not just the row insert.
 *  3. Back to /plans → click "Abandon" on the new card → confirm.
 *     Card flips to show the "Delete" affordance (only abandoned /
 *     completed plans expose Delete in the list).
 *  4. Click "Delete" → confirm → card disappears.
 *
 * Service-role afterEach is a safety net, not the canonical cleanup.
 */

test.describe('/plans/new — create wizard', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let plantedPlanId: string | null = null;

	test.afterEach(async () => {
		if (plantedPlanId) {
			try {
				await deletePlan(plantedPlanId);
			} catch (_) {
				/* best-effort */
			}
			plantedPlanId = null;
		}
		// `createTrainingPlan` auto-demotes any existing active plan to
		// 'completed' so the new one can take the per-user "one active
		// plan" slot. The seed has Sydney Half at 'active'; without
		// this, every other test downstream of this file sees Sydney
		// Half as 'completed' and any test that needs an active plan
		// (e.g. /coach defaulting) would behave differently. Restore.
		try {
			await setPlanStatus(SEED_PLAN_ID, 'active');
		} catch (_) {
			/* best-effort */
		}
	});

	test('create → land on detail → abandon → delete via UI', async ({ page }) => {
		const name = `e2e-create-plan ${Date.now()}`;

		// ── Phase 1: create ────────────────────────────────────────
		await test.step('open the wizard, fill, submit', async () => {
			await page.goto('/plans');
			await page.getByRole('button', { name: /New plan/ }).first().click();
			await expect(page.locator('.modal')).toBeVisible({ timeout: 5_000 });

			const modal = page.locator('.modal');
			await modal.getByPlaceholder('Autumn half marathon').fill(name);

			const start = new Date(Date.now() + 7 * 24 * 3600 * 1000);
			const isoDate = start.toISOString().slice(0, 10);
			await modal.locator('input[type="date"]').first().fill(isoDate);

			// "Create plan" enables only after the previewed plan
			// resolves — Riegel / VDOT / week-phasing pipeline has run.
			const submit = modal.getByRole('button', { name: /Create plan/ });
			await expect(submit).toBeEnabled({ timeout: 5_000 });
			await submit.click();
			// Seed has an active plan; the create flow gates on a
			// Replace-plan ConfirmDialog. Wait for the dialog and
			// confirm so we proceed to the actual create.
			const replace = page.locator('.modal.modal-narrow', {
				hasText: /Replace your active plan/
			});
			await expect(replace).toBeVisible({ timeout: 5_000 });
			await replace.getByRole('button', { name: 'Replace plan' }).click();
		});

		// ── Phase 2: land on detail, multi-week grid renders ──────
		await test.step('land on /plans/<new-id> with the multi-week grid', async () => {
			await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });
			plantedPlanId = page.url().match(/\/plans\/([0-9a-f-]+)$/)![1];
			await expect(page.getByRole('heading', { level: 1, name }))
				.toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.weeks .week').first())
				.toBeVisible({ timeout: 10_000 });
		});

		// ── Phase 3: back to /plans, abandon the new active plan ──
		await test.step('abandon the new plan from /plans card', async () => {
			await page.goto('/plans');
			const card = page.locator('.card', { hasText: name });
			await expect(card).toBeVisible({ timeout: 10_000 });
			// Active plans show "Abandon"; clicking it opens a
			// ConfirmDialog with confirmLabel="Abandon".
			await card.getByRole('button', { name: 'Abandon', exact: true }).click();
			const dialog = page.locator('.modal', { hasText: 'Abandon plan' });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.getByRole('button', { name: 'Abandon', exact: true }).click();
			await expect(dialog).toHaveCount(0);
			// Card now shows "Delete" instead of "Abandon" because the
			// status flipped to abandoned.
			await expect(
				card.getByRole('button', { name: 'Delete', exact: true })
			).toBeVisible({ timeout: 5_000 });
		});

		// ── Phase 4: delete the abandoned plan from /plans card ──
		await test.step('delete the abandoned plan', async () => {
			const card = page.locator('.card', { hasText: name });
			await card.getByRole('button', { name: 'Delete', exact: true }).click();
			const dialog = page.locator('.modal', { hasText: 'Delete plan' });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.getByRole('button', { name: 'Delete', exact: true }).click();
			await expect(dialog).toHaveCount(0);
			// Card is gone from the list — no exact-match anchor with
			// the new plan's name.
			await expect(page.locator('.card', { hasText: name })).toHaveCount(0, {
				timeout: 10_000
			});
			plantedPlanId = null; // UI cleanup completed; afterEach skips.
		});
	});

	test('creating a new plan when one is already active shows the Replace-plan confirm dialog; Cancel keeps the current plan active', async ({
		page
	}) => {
		// Real bug surfaced by the user: clicking Create plan on the
		// wizard silently auto-completed the existing active plan.
		// The schema enforces one-active-per-user via a partial unique
		// index, but the data layer's auto-complete-then-insert flow
		// did the swap without telling the user. Fix: ConfirmDialog
		// gates the create when an active plan exists; Cancel keeps
		// the existing plan untouched, Confirm proceeds with the
		// (now intentional) replace.
		await page.goto('/plans');
		await page.waitForLoadState('networkidle');

		// Seed has an active plan ("Sydney Half 2026"); confirm it's
		// active before we start.
		await expect(
			page.locator('.card', { hasText: 'Sydney Half 2026' })
		).toBeVisible({ timeout: 10_000 });

		// Open the New-plan wizard.
		await page.getByRole('button', { name: /New plan/ }).first().click();
		const modal = page.locator('.modal');
		await expect(modal).toBeVisible({ timeout: 5_000 });

		// Fill the minimum to enable Create.
		await modal.getByPlaceholder('Autumn half marathon').fill('e2e replace-confirm');
		const start = new Date(Date.now() + 14 * 24 * 3600 * 1000);
		await modal.locator('input[type="date"]').first().fill(
			start.toISOString().slice(0, 10)
		);
		await expect(modal.locator('.preview')).toBeVisible({ timeout: 5_000 });

		// Click Create plan — confirm dialog should appear, NOT the
		// silent auto-complete. ConfirmDialog renders via narrow Modal,
		// so .modal-narrow disambiguates from the wizard modal that's
		// still open behind it.
		await modal.getByRole('button', { name: 'Create plan' }).click();
		const confirm = page.locator('.modal.modal-narrow', {
			hasText: /Replace your active plan/
		});
		await expect(confirm).toBeVisible({ timeout: 5_000 });
		// Dialog names the plan being replaced so the user can see
		// exactly what they're about to retire.
		await expect(confirm).toContainText('Sydney Half 2026');

		// Cancel: dialog closes, no replace happens, the original plan
		// stays visible on /plans.
		await confirm.getByRole('button', { name: 'Keep current' }).click();
		await expect(confirm).toHaveCount(0, { timeout: 5_000 });

		// Close the wizard.
		await page.locator('.modal-close').first().click();
		await page.waitForLoadState('networkidle');

		// Seed plan is still on /plans + still active (no abandon /
		// complete flip).
		const seedCard = page.locator('.card', { hasText: 'Sydney Half 2026' });
		await expect(seedCard).toBeVisible({ timeout: 10_000 });
		await expect(seedCard).toHaveClass(/card-active/);
	});
});

import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Plan publish-as-template — saga complement.
 *
 * detail.spec.ts already pins the canonical happy path (publish-row
 * select → click Publish → template appears on the club's Templates
 * tab) and the deep-clone invariant (week + workout counts match,
 * completion fields are reset). This file fills two adjacent gaps the
 * existing tests don't:
 *
 *   1. Source-plan-unchanged — a publish is "publish AS a template"
 *      (clone), not "convert to template". The owner's personal
 *      plan must keep its is_template=false, status, name, and
 *      progress fields intact after publishing.
 *   2. Adopt-back round-trip surface — once published, a club member
 *      can `Adopt` the template into their own personal plan (the
 *      template-row exposes /plans/new?from=<id>). We pin the
 *      template-row Adopt link target so a regression that broke the
 *      adopt-link surface in the templates list would surface here.
 */

const SYDNEY_HALF_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';
const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('Plan publish-as-template — round-trip', () => {
	test.use({ storageState: USER_A.storageStatePath });

	async function sweepClones(): Promise<void> {
		// Sweep any cloned templates this club / name pair carries.
		// plan_weeks + plan_workouts cascade off the training_plans
		// delete. Run in beforeEach so leakage from a previous failed
		// run (e.g. detail.spec.ts's parallel publish-as-template
		// test, which can leave a stale row if its post-assertion
		// cleanup never ran) doesn't blow up the "exactly one clone"
		// invariant below.
		const admin = getAdminClient();
		const { data: clones } = await admin
			.from('training_plans')
			.select('id')
			.eq('is_template', true)
			.eq('club_id', SYDNEY_RUN_CLUB_ID)
			.eq('name', 'Richmond Half 2026');
		for (const r of clones ?? []) {
			await admin
				.from('training_plans')
				.delete()
				.eq('id', (r as { id: string }).id);
		}
	}

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		await sweepClones();
	});

	test.afterEach(async () => {
		await sweepClones();
	});

	test('publish from /plans/[id] → source plan is unchanged + template appears on club Templates tab', async ({
		page
	}) => {
		const admin = getAdminClient();
		const { data: before } = await admin
			.from('training_plans')
			.select('name, is_template, status, club_id, parent_template_id')
			.eq('id', SYDNEY_HALF_PLAN_ID)
			.maybeSingle();
		expect(before).not.toBeNull();
		const srcBefore = before as {
			name: string;
			is_template: boolean;
			status: string;
			club_id: string | null;
			parent_template_id: string | null;
		};
		expect(srcBefore.is_template).toBe(false);

		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		const publishRow = page.locator('.publish-row');
		await expect(publishRow).toBeVisible({ timeout: 10_000 });
		await publishRow.locator('select').selectOption(SYDNEY_RUN_CLUB_ID);
		await publishRow.getByRole('button', { name: 'Publish' }).click();
		await expect(publishRow.locator('select')).toHaveValue('', {
			timeout: 10_000
		});

		// Source plan untouched — name, status, is_template, club_id,
		// and parent_template_id are all exactly what they were
		// before the publish.
		const { data: after } = await admin
			.from('training_plans')
			.select('name, is_template, status, club_id, parent_template_id')
			.eq('id', SYDNEY_HALF_PLAN_ID)
			.maybeSingle();
		const srcAfter = after as typeof srcBefore;
		expect(srcAfter.name).toBe(srcBefore.name);
		expect(srcAfter.is_template).toBe(srcBefore.is_template);
		expect(srcAfter.status).toBe(srcBefore.status);
		expect(srcAfter.club_id).toBe(srcBefore.club_id);
		expect(srcAfter.parent_template_id).toBe(srcBefore.parent_template_id);

		// Template surfaces on the club's Templates tab.
		await page.goto('/clubs/richmond-run-club');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
		).toBeVisible({ timeout: 10_000 });
		await page.getByRole('tab', { name: /^Templates/ }).click();
		const templateRow = page.locator('.template-row', {
			hasText: 'Richmond Half 2026'
		});
		await expect(templateRow).toBeVisible({ timeout: 10_000 });

		// Adopt link is wired to /plans/new?from=<template_id>. Pin
		// the href so a regression that broke the adopt surface
		// (template list lost the Adopt button, or the link lost the
		// `from=` query param) is caught here, not silently in prod.
		const { data: clones } = await admin
			.from('training_plans')
			.select('id')
			.eq('is_template', true)
			.eq('club_id', SYDNEY_RUN_CLUB_ID)
			.eq('name', 'Richmond Half 2026');
		expect(clones?.length).toBe(1);
		const cloneId = (clones![0] as { id: string }).id;
		const adoptLink = templateRow.getByRole('link', { name: /Adopt/ });
		await expect(adoptLink).toBeVisible();
		await expect(adoptLink).toHaveAttribute('href', `/plans/new?from=${cloneId}`);
	});

	test('cloned template plan-detail renders the Club-template chip', async ({
		page
	}) => {
		// The plan-detail page renders a "Club template" chip when
		// `is_template && club_id`. Drive the publish, then load
		// the cloned template's plan-detail page and pin the chip.
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		const publishRow = page.locator('.publish-row');
		await expect(publishRow).toBeVisible({ timeout: 10_000 });
		await publishRow.locator('select').selectOption(SYDNEY_RUN_CLUB_ID);
		await publishRow.getByRole('button', { name: 'Publish' }).click();
		await expect(publishRow.locator('select')).toHaveValue('', {
			timeout: 10_000
		});

		const admin = getAdminClient();
		const { data: clones } = await admin
			.from('training_plans')
			.select('id')
			.eq('is_template', true)
			.eq('club_id', SYDNEY_RUN_CLUB_ID)
			.eq('name', 'Richmond Half 2026');
		expect(clones?.length).toBe(1);
		const cloneId = (clones![0] as { id: string }).id;

		await page.goto(`/plans/${cloneId}`);
		await expect(
			page.getByRole('heading', { level: 1, name: /Richmond Half 2026/ })
		).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.chip', { hasText: 'Club template' }))
			.toBeVisible({ timeout: 10_000 });

		// And — the publish-row is HIDDEN on a template's own detail
		// page (re-publishing a template would be a footgun). The
		// gate is `!plan.is_template && adminClubs.length > 0`.
		await expect(page.locator('.publish-row')).toHaveCount(0);
	});
});

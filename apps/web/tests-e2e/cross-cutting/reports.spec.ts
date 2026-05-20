import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * User-submitted reports — anti-spam phase 3 (migration 20260908_001).
 *
 * The MVP scope intentionally has no admin UI; the only thing the
 * front-end exposes is the Report dialog on /u/[id], /clubs/[slug],
 * and /routes/[id]. This file pins:
 *
 *   1. Free user can flag a club they don't own → row lands with the
 *      right (target_kind, target_id, reason) and 'pending' status.
 *   2. Filing the same report a second time surfaces the "already
 *      reported" guidance (the partial-unique index from the
 *      migration). The pgtap suite already pins the SQL behaviour;
 *      this asserts the user-facing copy reaches the dialog.
 *   3. RLS hides reporter A's report from reporter B even when B
 *      tries to read with a user-JWT supabase client.
 *
 * The third assertion is exercised at the SQL level in
 * apps/backend/supabase/tests/reports_test.sql; reproducing it here
 * would mean spinning up a second authed Playwright context, which
 * the cross-user spec suite handles elsewhere. We keep this file
 * focused on the UI submit path.
 */

const plantedReportIds: string[] = [];

test.describe('reports — Report dialog wires up to submit_report', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		if (plantedReportIds.length === 0) return;
		const admin = getAdminClient();
		await admin.from('reports').delete().in('id', plantedReportIds);
		plantedReportIds.length = 0;
	});

	test('Report a club → row lands with the chosen reason + notes', async ({
		page,
	}) => {
		const admin = getAdminClient();

		// Seed a public club owned by USER_B so USER_A can report
		// it as a non-owner. We use the admin client so the
		// rate-limit trigger and slug-collision retry path are both
		// bypassed deterministically.
		const uniqueSuffix = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
		const clubName = `Reportable Spam Club ${uniqueSuffix}`;
		const slug = `reportable-spam-${uniqueSuffix}`;
		const { data: club, error: insertErr } = await admin
			.from('clubs')
			.insert({
				owner_id: USER_B.id,
				name: clubName,
				slug,
				is_public: true,
				join_policy: 'open',
			})
			.select('id')
			.single();
		if (insertErr || !club) {
			throw new Error(`seed club insert failed: ${insertErr?.message}`);
		}
		const clubId = club.id as string;

		try {
			await page.goto(`/clubs/${slug}`);
			await expect(
				page.getByRole('heading', { name: clubName, level: 1 }),
			).toBeVisible({ timeout: 10_000 });

			await page.getByRole('button', { name: /Report this club/i }).click();

			const dialog = page.locator('.modal', { hasText: /Report this club/ });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await expect(dialog).toContainText(clubName);

			// Default reason is "spam" — pick "harassment" to verify the
			// radio binding flows through into the RPC payload.
			await dialog.getByRole('radio', { name: /Harassment or abuse/ }).check();

			const noteText = `e2e harassment note ${Date.now()}`;
			await dialog
				.getByPlaceholder(/Anything that would help a moderator/)
				.fill(noteText);

			await dialog.getByRole('button', { name: 'Submit report' }).click();

			// Toast confirms + dialog closes.
			await expect(page.getByText(/Report submitted/i)).toBeVisible({
				timeout: 5_000,
			});
			await expect(dialog).toBeHidden({ timeout: 5_000 });

			// DB row landed with the right shape.
			const { data: row } = await admin
				.from('reports')
				.select('id, reporter_id, target_kind, target_id, reason, notes, status')
				.eq('target_kind', 'club')
				.eq('target_id', clubId)
				.eq('reporter_id', USER_A.id)
				.maybeSingle();
			expect(row).not.toBeNull();
			expect(row!.reason).toBe('harassment');
			expect(row!.notes).toBe(noteText);
			expect(row!.status).toBe('pending');
			plantedReportIds.push(row!.id as string);
		} finally {
			await admin.from('clubs').delete().eq('id', clubId);
		}
	});

	test('Filing a second pending report against the same target surfaces "already reported"', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const uniqueSuffix = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
		const clubName = `Re-report Target ${uniqueSuffix}`;
		const slug = `re-report-${uniqueSuffix}`;
		const { data: club } = await admin
			.from('clubs')
			.insert({
				owner_id: USER_B.id,
				name: clubName,
				slug,
				is_public: true,
				join_policy: 'open',
			})
			.select('id')
			.single();
		const clubId = club!.id as string;

		// Pre-plant a pending report from USER_A so the next submit
		// attempt fires the unique-violation path.
		const { data: row } = await admin
			.from('reports')
			.insert({
				reporter_id: USER_A.id,
				target_kind: 'club',
				target_id: clubId,
				reason: 'spam',
				status: 'pending',
			})
			.select('id')
			.single();
		plantedReportIds.push(row!.id as string);

		try {
			await page.goto(`/clubs/${slug}`);
			await page.getByRole('button', { name: /Report this club/i }).click();
			const dialog = page.locator('.modal', { hasText: /Report this club/ });
			await expect(dialog).toBeVisible();
			await dialog.getByRole('button', { name: 'Submit report' }).click();

			// The dialog stays open with the inline error — toast does
			// NOT fire because submitReport threw before showToast.
			await expect(
				dialog.getByText(/already have a pending report/i),
			).toBeVisible({ timeout: 5_000 });
		} finally {
			await admin.from('clubs').delete().eq('id', clubId);
		}
	});
});

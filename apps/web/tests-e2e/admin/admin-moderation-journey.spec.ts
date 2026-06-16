import { expect, test } from '@playwright/test';
import type { BrowserContext } from '@playwright/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import {
	createSagaUsers,
	deleteSagaUsers,
	type SagaUser,
} from '../fixtures/saga-users';

/**
 * Content-moderation journey — report → review → action, end to end.
 *
 * The existing admin/reports.spec.ts PLANTS reports via the service-role
 * client (bypassing submit_report's rate-limit + duplicate guard) and
 * triages them as the SEEDED admin (runner@test.com). It pins the
 * triage UX on top of pre-existing rows, but it never walks the full
 * arc that a real moderation incident takes:
 *
 *   reporter files a report through the UI  →
 *   moderator sees it in the /admin/reports queue  →
 *   moderator opens it, reads the reason/notes, takes an action  →
 *   the report's state reflects the resolution, all the way back to
 *   the original reporter's own (RLS-scoped) report history.
 *
 * This spec covers that uncovered journey with three ephemeral saga
 * users — a reporter, a content-author (the report target), and a
 * moderator — so nothing here leans on seeded state.
 *
 * HOW ADMIN AUTH WORKS (migration 20270105_001): admin capability is an
 * `app_admins` allow-list row keyed by user_id. The web client calls
 * `am_i_admin()` only to pick page chrome; the REAL boundary is the
 * per-RPC `private.is_admin(auth.uid())` gate inside
 * fetch_pending_reports / fetch_reports_for_target / resolve_target_reports,
 * each of which raises 42501 for a non-admin. We grant our moderator
 * saga user that capability by inserting an `app_admins` row via the
 * service-role client, and revoke it in teardown.
 *
 * Report creation goes through the genuine `submit_report` SECURITY
 * DEFINER RPC (driven from the profile-page flag dialog), so the
 * rate-limit / duplicate-pending / self-report guards are all live —
 * we don't bypass them the way reports.spec.ts does.
 */

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
	);
}

async function newConsentingContext(
	browser: import('@playwright/test').Browser,
	storageStatePath: string,
): Promise<BrowserContext> {
	const ctx = await browser.newContext({ storageState: storageStatePath });
	await ctx.addInitScript(setConsentAccepted);
	return ctx;
}

async function grantAdmin(userId: string): Promise<void> {
	const admin = getAdminClient();
	const { error } = await admin
		.from('app_admins')
		.upsert({ user_id: userId }, { onConflict: 'user_id' });
	if (error) throw error;
}

async function revokeAdmin(userId: string): Promise<void> {
	const admin = getAdminClient();
	await admin.from('app_admins').delete().eq('user_id', userId);
}

/**
 * Reset the per-reporter `create_report` rate-limit window so the
 * genuine submit_report path (10/hour, shared enforce_create_rate_limit
 * trigger) can't trip across reruns inside the same wall-clock hour.
 * Service-role delete bypasses the trigger.
 */
async function resetReportRateLimit(userId: string): Promise<void> {
	const admin = getAdminClient();
	await admin.from('rate_limits').delete().eq('user_id', userId).eq('bucket', 'create_report');
}

test.describe('content moderation — report → review → action', () => {
	test('reporter files a report, moderator reviews + resolves it, and the reporter sees the resolution', async ({
		browser,
	}) => {
		// reporter, author (target), moderator.
		const users = await createSagaUsers(3, {
			displayNames: ['Saga Reporter', 'Saga Author', 'Saga Moderator'],
		});
		const [reporter, author, moderator] = users as [SagaUser, SagaUser, SagaUser];

		let reporterCtx: BrowserContext | null = null;
		let moderatorCtx: BrowserContext | null = null;

		try {
			await resetReportRateLimit(reporter.id);
			await grantAdmin(moderator.id);

			// ── 1. Reporter files a report against the author's profile ──
			reporterCtx = await newConsentingContext(browser, reporter.storageStatePath);
			const reporterPage = await reporterCtx.newPage();

			await test.step('reporter flags the author profile through the report dialog', async () => {
				await reporterPage.goto(`/u/${author.id}`);

				const flag = reporterPage.getByRole('button', { name: 'Report this profile' });
				await expect(flag).toBeVisible({ timeout: 10_000 });
				await flag.click();

				// The dialog names the target so the reporter can sanity-check.
				const dialog = reporterPage.locator('.modal', { hasText: /Report this profile/ });
				await expect(dialog).toBeVisible({ timeout: 5_000 });
				await expect(dialog).toContainText(author.displayName);

				// Pick a reason + leave notes the moderator will read.
				await dialog.getByRole('radio', { name: /Harassment or abuse/ }).check();
				await dialog
					.locator('textarea')
					.fill('repeated targeted insults in club chat');
				await dialog.getByRole('button', { name: 'Submit report' }).click();

				// Success toast confirms the genuine submit_report RPC landed.
				await expect(reporterPage.getByText('Report submitted. Thanks for flagging.')).toBeVisible({
					timeout: 5_000,
				});
			});

			// The report exists, pending, attributed to the reporter.
			await test.step('the report lands as a pending row attributed to the reporter', async () => {
				const admin = getAdminClient();
				const { data } = await admin
					.from('reports')
					.select('reporter_id, target_kind, target_id, reason, notes, status')
					.eq('target_kind', 'user')
					.eq('target_id', author.id);
				expect(data?.length).toBe(1);
				const row = data![0];
				expect(row.reporter_id).toBe(reporter.id);
				expect(row.reason).toBe('harassment');
				expect(row.notes).toBe('repeated targeted insults in club chat');
				expect(row.status).toBe('pending');
			});

			// ── 2. Moderator sees it in the queue and opens the detail ──
			moderatorCtx = await newConsentingContext(browser, moderator.storageStatePath);
			const moderatorPage = await moderatorCtx.newPage();

			await test.step('moderator finds the target in the /admin/reports queue', async () => {
				await moderatorPage.goto('/admin/reports');

				// Admin chrome renders (am_i_admin → true), not the locked-out card.
				await expect(moderatorPage.getByTestId('admin-not-authorized')).toHaveCount(0);

				const row = moderatorPage
					.getByTestId('admin-queue-row')
					.filter({ hasText: author.id.slice(0, 8) });
				await expect(row).toBeVisible({ timeout: 10_000 });
				// One report against this target so far.
				await expect(row).toContainText('1');
				await row.click();
			});

			await test.step('moderator reviews the report detail', async () => {
				const modal = moderatorPage.getByTestId('admin-detail-modal');
				await expect(modal).toBeVisible({ timeout: 5_000 });
				// The reason chip + the reporter's notes are both visible to the moderator.
				await expect(modal.getByText('harassment', { exact: true })).toBeVisible();
				await expect(modal.getByText('repeated targeted insults in club chat')).toBeVisible();
			});

			// ── 3. Moderator takes the resolve action ──
			await test.step('moderator marks the report reviewed with a resolution note', async () => {
				const modal = moderatorPage.getByTestId('admin-detail-modal');
				await modal.getByTestId('admin-resolution-input').fill('warned the user, removed the posts');
				await modal.getByTestId('admin-mark-reviewed').click();

				// ConfirmDialog → confirm.
				await moderatorPage
					.getByTestId('admin-resolve-confirm')
					.getByRole('button', { name: /reviewed/i })
					.click();

				// The target leaves the queue.
				await expect(
					moderatorPage
						.getByTestId('admin-queue-row')
						.filter({ hasText: author.id.slice(0, 8) }),
				).toHaveCount(0, { timeout: 5_000 });
			});

			// ── 4. The resolution is reflected in the DB + back to the reporter ──
			await test.step('the DB reflects the moderator as reviewer + the resolution note', async () => {
				const admin = getAdminClient();
				const { data } = await admin
					.from('reports')
					.select('status, reviewed_by, resolution')
					.eq('target_kind', 'user')
					.eq('target_id', author.id);
				expect(data?.length).toBe(1);
				const row = data![0];
				expect(row.status).toBe('reviewed');
				expect(row.reviewed_by).toBe(moderator.id);
				expect(row.resolution).toBe('warned the user, removed the posts');
			});

			await test.step('the original reporter sees the resolution in their own RLS-scoped history', async () => {
				// The reporter can only read their OWN reports (RLS, migration
				// 20260908_001). Reading as the real reporter JWT proves the
				// resolution propagated all the way back to the person who filed it.
				const reporterClient = await getUserClient({
					email: reporter.email,
					password: reporter.password,
				});
				const { data, error } = await reporterClient
					.from('reports')
					.select('status, resolution, reviewed_by')
					.eq('target_kind', 'user')
					.eq('target_id', author.id);
				expect(error).toBeNull();
				expect(data?.length).toBe(1);
				expect(data![0].status).toBe('reviewed');
				expect(data![0].resolution).toBe('warned the user, removed the posts');
				expect(data![0].reviewed_by).toBe(moderator.id);
			});
		} finally {
			// Reports cascade off the reporter's auth.users delete, but wipe
			// them explicitly first so a partial failure can't orphan a row
			// keyed to the (soon-deleted) saga ids.
			const admin = getAdminClient();
			await admin.from('reports').delete().eq('target_kind', 'user').eq('target_id', author.id);
			await revokeAdmin(moderator.id);
			await resetReportRateLimit(reporter.id);
			if (reporterCtx) await reporterCtx.close();
			if (moderatorCtx) await moderatorCtx.close();
			await deleteSagaUsers(users);
		}
	});

	test('moderator can dismiss a report as no-action, and it leaves the queue dismissed', async ({
		browser,
	}) => {
		const users = await createSagaUsers(3, {
			displayNames: ['Saga Reporter 2', 'Saga Author 2', 'Saga Moderator 2'],
		});
		const [reporter, author, moderator] = users as [SagaUser, SagaUser, SagaUser];

		let reporterCtx: BrowserContext | null = null;
		let moderatorCtx: BrowserContext | null = null;

		try {
			await resetReportRateLimit(reporter.id);
			await grantAdmin(moderator.id);

			// Reporter files a (this time spurious) report through the UI.
			reporterCtx = await newConsentingContext(browser, reporter.storageStatePath);
			const reporterPage = await reporterCtx.newPage();

			await test.step('reporter files a report', async () => {
				await reporterPage.goto(`/u/${author.id}`);
				const flag = reporterPage.getByRole('button', { name: 'Report this profile' });
				await expect(flag).toBeVisible({ timeout: 10_000 });
				await flag.click();
				const dialog = reporterPage.locator('.modal', { hasText: /Report this profile/ });
				await expect(dialog).toBeVisible({ timeout: 5_000 });
				await dialog.getByRole('radio', { name: /Spam or promotion/ }).check();
				await dialog.getByRole('button', { name: 'Submit report' }).click();
				await expect(reporterPage.getByText('Report submitted. Thanks for flagging.')).toBeVisible({
					timeout: 5_000,
				});
			});

			// Moderator dismisses it (the no-action branch of the arc).
			moderatorCtx = await newConsentingContext(browser, moderator.storageStatePath);
			const moderatorPage = await moderatorCtx.newPage();

			await test.step('moderator dismisses the report', async () => {
				await moderatorPage.goto('/admin/reports');
				const row = moderatorPage
					.getByTestId('admin-queue-row')
					.filter({ hasText: author.id.slice(0, 8) });
				await expect(row).toBeVisible({ timeout: 10_000 });
				await row.click();

				const modal = moderatorPage.getByTestId('admin-detail-modal');
				await expect(modal).toBeVisible({ timeout: 5_000 });
				await modal.getByTestId('admin-dismiss').click();

				await moderatorPage
					.getByTestId('admin-resolve-confirm')
					.getByRole('button', { name: /dismiss/i })
					.click();

				await expect(
					moderatorPage
						.getByTestId('admin-queue-row')
						.filter({ hasText: author.id.slice(0, 8) }),
				).toHaveCount(0, { timeout: 5_000 });
			});

			await test.step('the report is recorded as dismissed', async () => {
				const admin = getAdminClient();
				const { data } = await admin
					.from('reports')
					.select('status, reviewed_by')
					.eq('target_kind', 'user')
					.eq('target_id', author.id);
				expect(data?.length).toBe(1);
				expect(data![0].status).toBe('dismissed');
				expect(data![0].reviewed_by).toBe(moderator.id);
			});
		} finally {
			const admin = getAdminClient();
			await admin.from('reports').delete().eq('target_kind', 'user').eq('target_id', author.id);
			await revokeAdmin(moderator.id);
			await resetReportRateLimit(reporter.id);
			if (reporterCtx) await reporterCtx.close();
			if (moderatorCtx) await moderatorCtx.close();
			await deleteSagaUsers(users);
		}
	});
});

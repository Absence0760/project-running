import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /settings/safety — safety-contact double opt-in (migration
 * 20261218_001, decisions §131). The owner adds a contact by email; the
 * contact's opt-in is a separate step, so the row starts "pending" and
 * only the contact can flip it to "confirmed" — either in-app (an app
 * user matched by their account email) or via the email-link token (an
 * external contact). The finish-alert trigger only fires for confirmed
 * contacts, so this consent gate is the load-bearing privacy property.
 */

async function cleanup() {
	const admin = getAdminClient();
	await admin.from('safety_contacts').delete().eq('owner_id', USER_A.id);
	// USER_B may own rows too if a test added them; keep the table clean.
	await admin.from('safety_contacts').delete().eq('owner_id', USER_B.id);
}

test.describe('/settings/safety', () => {
	test.beforeEach(cleanup);
	test.afterEach(cleanup);

	test('owner adds a contact → contact confirms in-app → owner sees confirmed', async ({
		browser,
	}) => {
		const ctxRunner = await browser.newContext({ storageState: USER_A.storageStatePath });
		const ctxAlex = await browser.newContext({ storageState: USER_B.storageStatePath });
		const runner = await ctxRunner.newPage();
		const alex = await ctxAlex.newPage();

		try {
			// ── Owner adds alex by email ──
			await runner.goto('/settings/safety');
			await runner.getByTestId('safety-email-input').fill(USER_B.email);
			await runner.getByTestId('safety-add-button').click();

			const contact = runner.getByTestId('safety-contact').filter({ hasText: USER_B.email });
			await expect(contact).toBeVisible({ timeout: 5_000 });
			// Starts pending — the contact hasn't opted in yet.
			await expect(contact).toContainText('Pending');

			// ── Alex sees the incoming request and confirms ──
			await alex.goto('/settings/safety');
			const incoming = alex.getByTestId('safety-incoming');
			await expect(incoming).toBeVisible({ timeout: 5_000 });
			await expect(incoming).toContainText('Jared Howard'); // owner display name
			await alex.getByTestId('safety-confirm-request').click();
			// After confirming, the pending section clears.
			await expect(alex.getByTestId('safety-incoming')).toHaveCount(0, { timeout: 5_000 });

			// ── Owner now sees the contact as confirmed ──
			await runner.reload();
			const confirmed = runner.getByTestId('safety-contact').filter({ hasText: USER_B.email });
			await expect(confirmed).toContainText('Confirmed', { timeout: 5_000 });

			// ── Owner removes it ──
			runner.once('dialog', () => {}); // no native dialog; ConfirmDialog is in-DOM
			await confirmed.getByRole('button', { name: 'Remove' }).click();
			await runner.getByRole('button', { name: 'Remove' }).last().click(); // confirm in dialog
			await expect(
				runner.getByTestId('safety-contact').filter({ hasText: USER_B.email }),
			).toHaveCount(0, { timeout: 5_000 });
		} finally {
			await ctxRunner.close();
			await ctxAlex.close();
		}
	});

	test('external contact confirms via the email-link token; a bad token fails', async ({
		browser,
	}) => {
		// Seed a pending external (non-user) contact directly so we can read
		// its confirm_token — this is the path a real opt-in email links to.
		const admin = getAdminClient();
		const email = `external-${Date.now()}@safe.local`;
		const { error: insErr } = await admin
			.from('safety_contacts')
			.insert({ owner_id: USER_A.id, contact_email: email });
		expect(insErr).toBeNull();
		const { data: row } = await admin
			.from('safety_contacts')
			.select('confirm_token')
			.eq('owner_id', USER_A.id)
			.eq('contact_email', email)
			.single();
		const token = (row as { confirm_token: string }).confirm_token;
		expect(token).toBeTruthy();

		// Anonymous (logged-out) context — the external contact only has the link.
		const ctx = await browser.newContext();
		const anon = await ctx.newPage();
		try {
			await anon.goto(`/safety/confirm?token=${token}`);
			const card = anon.getByTestId('safety-confirm-card');
			await expect(card).toHaveAttribute('data-state', 'success', { timeout: 5_000 });

			// The row is now confirmed in the DB.
			const { data: after } = await admin
				.from('safety_contacts')
				.select('confirmed_at')
				.eq('owner_id', USER_A.id)
				.eq('contact_email', email)
				.single();
			expect((after as { confirmed_at: string | null }).confirmed_at).not.toBeNull();

			// A junk / already-used token fails closed.
			await anon.goto('/safety/confirm?token=00000000-0000-0000-0000-000000000000');
			await expect(card).toHaveAttribute('data-state', 'failure', { timeout: 5_000 });
		} finally {
			await ctx.close();
		}
	});
});

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

	test('owner adds a contact with a phone → contact opts into SMS → owner sees the SMS badge', async ({
		browser,
	}) => {
		const ctxRunner = await browser.newContext({ storageState: USER_A.storageStatePath });
		const ctxAlex = await browser.newContext({ storageState: USER_B.storageStatePath });
		const runner = await ctxRunner.newPage();
		const alex = await ctxAlex.newPage();

		try {
			// ── Owner adds alex by email + an E.164 phone ──
			await runner.goto('/settings/safety');
			await runner.getByTestId('safety-email-input').fill(USER_B.email);
			await runner.getByTestId('safety-phone-input').fill('+447700900123');
			await runner.getByTestId('safety-add-button').click();

			const contact = runner.getByTestId('safety-contact').filter({ hasText: USER_B.email });
			await expect(contact).toBeVisible({ timeout: 5_000 });
			await expect(contact).toContainText('Pending');

			// ── Alex sees the incoming request; the SMS opt-in appears because
			// the owner stored a phone (has_phone). Opt in, then confirm. ──
			await alex.goto('/settings/safety');
			await expect(alex.getByTestId('safety-incoming')).toBeVisible({ timeout: 5_000 });
			await expect(alex.getByTestId('safety-confirm-sms')).toBeVisible();
			await alex.getByTestId('safety-confirm-sms').check();
			await alex.getByTestId('safety-confirm-request').click();
			await expect(alex.getByTestId('safety-incoming')).toHaveCount(0, { timeout: 5_000 });

			// ── Owner reloads → confirmed + "SMS on" badge ──
			await runner.reload();
			const confirmed = runner.getByTestId('safety-contact').filter({ hasText: USER_B.email });
			await expect(confirmed).toContainText('Confirmed', { timeout: 5_000 });
			await expect(confirmed.getByTestId('safety-sms-badge')).toBeVisible();

			// The opt-in stamp is persisted server-side.
			const admin = getAdminClient();
			const { data: after } = await admin
				.from('safety_contacts')
				.select('sms_opt_in_at, contact_phone')
				.eq('owner_id', USER_A.id)
				.eq('contact_email', USER_B.email)
				.single();
			expect((after as { sms_opt_in_at: string | null }).sms_opt_in_at).not.toBeNull();
			expect((after as { contact_phone: string | null }).contact_phone).toBe('+447700900123');
		} finally {
			await ctxRunner.close();
			await ctxAlex.close();
		}
	});

	test('an invalid phone is rejected client-side before any insert', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: USER_A.storageStatePath });
		const page = await ctx.newPage();
		try {
			let inserts = 0;
			await page.route('**/rest/v1/safety_contacts**', async (route) => {
				if (route.request().method() === 'POST') inserts++;
				await route.continue();
			});

			await page.goto('/settings/safety');
			await page.getByTestId('safety-email-input').fill(USER_B.email);
			// Missing leading '+' → fails the E.164 mirror of the DB CHECK.
			await page.getByTestId('safety-phone-input').fill('447700900123');
			await page.getByTestId('safety-add-button').click();

			await expect(page.getByText(/international format/)).toBeVisible({ timeout: 5_000 });
			await expect(page.getByTestId('safety-contact')).toHaveCount(0);
			expect(inserts).toBe(0);
		} finally {
			await ctx.close();
		}
	});

	test('double-clicking Confirm on an incoming request fires the RPC once', async ({
		browser,
	}) => {
		// Plant a pending request from USER_A to USER_B (matched by email).
		const admin = getAdminClient();
		const { error } = await admin
			.from('safety_contacts')
			.insert({ owner_id: USER_A.id, contact_email: USER_B.email });
		expect(error).toBeNull();

		const ctx = await browser.newContext({ storageState: USER_B.storageStatePath });
		const page = await ctx.newPage();
		try {
			let calls = 0;
			await page.route('**/rest/v1/rpc/confirm_safety_contact**', async (route) => {
				calls++;
				// Hold the response so the busy guard stays engaged across the
				// second synchronous click.
				await new Promise((r) => setTimeout(r, 400));
				await route.fulfill({ status: 200, contentType: 'application/json', body: 'true' });
			});

			await page.goto('/settings/safety');
			await expect(page.getByTestId('safety-incoming')).toBeVisible({ timeout: 5_000 });

			// Two native clicks in one task — the respondingId guard set on the
			// first must make the second a no-op before the disabled attr paints.
			await page
				.getByTestId('safety-confirm-request')
				.evaluate((el: HTMLButtonElement) => {
					el.click();
					el.click();
				});

			// The RPC is faked (the row stays pending), so the section doesn't
			// clear — wait for the in-flight guard to release (button re-enabled)
			// then assert the double-click only fired the RPC once.
			await expect(page.getByTestId('safety-confirm-request')).toBeEnabled({ timeout: 5_000 });
			expect(calls).toBe(1);
		} finally {
			await ctx.close();
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
			.insert({ owner_id: USER_A.id, contact_email: email, contact_phone: '+447700900124' });
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
			// The page now prompts (with the SMS opt-in) instead of
			// auto-confirming; the contact clicks Confirm to opt in.
			await expect(card).toHaveAttribute('data-state', 'prompt', { timeout: 5_000 });
			await anon.getByTestId('safety-confirm-sms').check();
			await anon.getByTestId('safety-confirm-button').click();
			await expect(card).toHaveAttribute('data-state', 'success', { timeout: 5_000 });

			// The row is now confirmed in the DB, with the SMS opt-in stamped
			// because the owner had stored a phone.
			const { data: after } = await admin
				.from('safety_contacts')
				.select('confirmed_at, sms_opt_in_at')
				.eq('owner_id', USER_A.id)
				.eq('contact_email', email)
				.single();
			expect((after as { confirmed_at: string | null }).confirmed_at).not.toBeNull();
			expect((after as { sms_opt_in_at: string | null }).sms_opt_in_at).not.toBeNull();

			// A junk / already-used token fails closed.
			await anon.goto('/safety/confirm?token=00000000-0000-0000-0000-000000000000');
			await expect(card).toHaveAttribute('data-state', 'prompt', { timeout: 5_000 });
			await anon.getByTestId('safety-confirm-button').click();
			await expect(card).toHaveAttribute('data-state', 'failure', { timeout: 5_000 });
		} finally {
			await ctx.close();
		}
	});
});

test.describe('/settings/safety — overdue alert pref', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		const admin = getAdminClient();
		const { data } = await admin
			.from('user_settings')
			.select('prefs')
			.eq('user_id', USER_A.id)
			.maybeSingle();
		const prefs = (data?.prefs as Record<string, unknown> | null) ?? {};
		delete prefs.safety_overdue_minutes;
		await admin
			.from('user_settings')
			.upsert({ user_id: USER_A.id, prefs });
	});

	test('overdue alert: picking a window persists the pref, Off clears it', async ({
		page,
	}) => {
		// The pref is the backend scan's opt-in gate (fail-closed:
		// null/absent = no escalation) — docs/features/safety.md.
		await page.goto('/settings/safety');
		const select = page.getByTestId('safety-overdue-select');
		await expect(select).toBeVisible({ timeout: 10_000 });

		await select.selectOption('30');
		const admin = getAdminClient();
		await expect
			.poll(async () => {
				const { data } = await admin
					.from('user_settings')
					.select('prefs')
					.eq('user_id', USER_A.id)
					.maybeSingle();
				return (data?.prefs as Record<string, unknown> | null)?.safety_overdue_minutes ?? null;
			}, { timeout: 10_000 })
			.toBe(30);

		// Off writes null — the scan's predicate no longer matches.
		await select.selectOption('off');
		await expect
			.poll(async () => {
				const { data } = await admin
					.from('user_settings')
					.select('prefs')
					.eq('user_id', USER_A.id)
					.maybeSingle();
				return (data?.prefs as Record<string, unknown> | null)?.safety_overdue_minutes ?? null;
			}, { timeout: 10_000 })
			.toBe(null);

		// Reload renders the persisted value, not the default.
		await select.selectOption('60');
		await expect
			.poll(async () => {
				const { data } = await admin
					.from('user_settings')
					.select('prefs')
					.eq('user_id', USER_A.id)
					.maybeSingle();
				return (data?.prefs as Record<string, unknown> | null)?.safety_overdue_minutes ?? null;
			}, { timeout: 10_000 })
			.toBe(60);
		await page.reload();
		await expect(page.getByTestId('safety-overdue-select')).toHaveValue('60', {
			timeout: 10_000,
		});
	});
});

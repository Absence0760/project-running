import { expect, test, type Page } from '@playwright/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { USER_A } from '../fixtures/users';

/**
 * Accessible-name pins for form controls that had a visible-but-not-
 * programmatic label (UX-hunt web finding #5). Each control must now
 * expose a localized accessible name so screen-reader / voice-control
 * users get a named field, not a bare "spin button" / "combo box" /
 * "edit text".
 *
 *   - /routes/new pace min + sec number inputs (adjacent .pace-label span
 *     only) → aria-label "Pace minutes" / "Pace seconds".
 *   - /settings/devices override value number input + enum select (the
 *     "Value" heading named the field generically) → aria-label
 *     "Override value".
 *   - CoachChat inline message-edit textarea (no label) → aria-label
 *     "Edit your message".
 */

async function waitForRouteBuilder(page: Page): Promise<void> {
	await page.waitForFunction(
		() =>
			typeof (window as unknown as { __routeBuilder?: unknown }).__routeBuilder !==
			'undefined',
		undefined,
		{ timeout: 10_000 },
	);
}

async function addWaypoints(
	page: Page,
	points: Array<{ lat: number; lng: number }>,
): Promise<void> {
	await page.evaluate((pts) => {
		const b = (
			window as unknown as {
				__routeBuilder: { addWaypoint: (p: { lat: number; lng: number }) => void };
			}
		).__routeBuilder;
		for (const p of pts) b.addWaypoint(p);
	}, points);
}

test.describe('form-control accessible names', () => {
	test.describe('authed shared user', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test('/routes/new pace min + sec inputs expose accessible names', async ({
			page,
		}) => {
			// The pace-input row only renders once distance > 0, so a route
			// has to snap first. Stub OSRM + the elevation lookup so a clean
			// line is produced offline.
			await page.route('**/route/v1/**', (route) => {
				const url = route.request().url();
				const m = url.match(/\/foot\/([-0-9.,;]+)/);
				const coords: [number, number][] = m
					? m[1].split(';').map((p) => p.split(',').map(Number) as [number, number])
					: [
							[0, 0],
							[0.001, 0.001],
						];
				route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify({
						code: 'Ok',
						routes: [{ geometry: { coordinates: coords }, distance: 1000 }],
						waypoints: coords.map((c) => ({ location: c })),
					}),
				});
			});
			await page.route('https://api.open-meteo.com/**', (route) =>
				route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify({ elevation: Array(100).fill(10) }),
				}),
			);

			await page.goto('/routes/new');
			await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
			await waitForRouteBuilder(page);
			await addWaypoints(page, [
				{ lng: 144.97, lat: -37.816 },
				{ lng: 144.975, lat: -37.82 },
			]);

			// The pace inputs live inside the .pace-input row that appears
			// once distance > 0.
			const minInput = page.getByLabel('Pace minutes');
			const secInput = page.getByLabel('Pace seconds');
			await expect(minInput).toBeVisible({ timeout: 10_000 });
			await expect(secInput).toBeVisible();
			// They stay bindable number spinners, just now named.
			await expect(minInput).toHaveAttribute('type', 'number');
			await expect(secInput).toHaveAttribute('type', 'number');
		});

		test('/settings/devices override value control exposes an accessible name', async ({
			page,
		}) => {
			// loadSettings (called by /settings/preferences onMount) provisions
			// this browser's device row, so /settings/devices has a current
			// device with an "Add override" affordance.
			await page.goto('/settings/preferences');
			await expect(page.getByRole('heading', { name: 'Units & Display' })).toBeVisible({
				timeout: 10_000,
			});

			await page.goto('/settings/devices');
			const currentRow = page.locator('.device.current');
			await expect(currentRow).toBeVisible({ timeout: 10_000 });

			await currentRow.locator('.override-link').click();
			await currentRow.locator('button.override-add-btn').click();

			const dialog = page.locator('.modal', { hasText: 'override' });
			await expect(dialog).toBeVisible({ timeout: 5_000 });

			const keySelect = dialog.locator('select').first();

			// Number-shaped key → the value control is a number input.
			await keySelect.selectOption('voice_feedback_interval_km');
			const numberValue = dialog.getByLabel('Override value');
			await expect(numberValue).toBeVisible();
			await expect(numberValue).toHaveAttribute('type', 'number');

			// Enum-shaped key → the value control swaps to a select, still
			// named "Override value".
			await keySelect.selectOption('preferred_unit');
			const enumValue = dialog.getByLabel('Override value');
			await expect(enumValue).toBeVisible();
			await expect(enumValue).toHaveJSProperty('tagName', 'SELECT');
		});
	});

	test.describe('CoachChat edit textarea', () => {
		let user: SagaUser;

		test.beforeAll(async () => {
			[user] = await createSagaUsers(1, { displayNames: ['Label Coach'] });
		});

		test.afterAll(async () => {
			if (user) await deleteSagaUsers([user]);
		});

		test('the inline message-edit textarea exposes an accessible name', async ({
			browser,
		}) => {
			const admin = getAdminClient();
			const marker = Date.now();
			const userQ = `label ${marker}: how hard should my long run be?`;

			const ctx = await browser.newContext({ storageState: user.storageStatePath });
			await ctx.addInitScript(() => {
				localStorage.setItem(
					'cookie_consent',
					JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
				);
			});
			const page = await ctx.newPage();

			try {
				// Clear the first-use AI-coach consent gate (server-authoritative
				// RPC under the user's own JWT) so the composer + bubbles render.
				const userClient = await getUserClient({
					email: user.email,
					password: user.password,
				});
				const { error: consentErr } = await userClient.rpc('record_coach_consent');
				expect(consentErr).toBeNull();

				// Plant a single user turn so its bubble carries the Edit action.
				const { error: seedErr } = await admin.from('coach_messages').insert([
					{
						user_id: user.id,
						plan_id: null,
						role: 'user',
						content: userQ,
						created_at: '2026-05-20T08:00:00.000Z',
					},
				]);
				expect(seedErr).toBeNull();

				await page.goto('/coach?plan=none');
				const userBubble = page.locator('.bubble.user', { hasText: userQ });
				await expect(userBubble).toBeVisible({ timeout: 15_000 });

				// Open the inline editor via the user bubble's Edit action.
				await userBubble.getByRole('button', { name: 'Edit' }).click();

				const editArea = page.getByLabel('Edit your message');
				await expect(editArea).toBeVisible();
				await expect(editArea).toHaveJSProperty('tagName', 'TEXTAREA');
				await expect(editArea).toHaveValue(userQ);
			} finally {
				await ctx.close();
			}
		});
	});
});

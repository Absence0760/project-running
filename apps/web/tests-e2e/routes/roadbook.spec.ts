import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRoute } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /routes/[id]/roadbook — the race crew sheet built from a route's course
 * markers + a goal time (migration 20270129_001 markers + roadbook.ts engine).
 * Asserts projected arrival, a red cutoff chip when the goal is too slow, the
 * URL carrying the goal (shareable), and that the effort/even toggle re-paces.
 */

async function seedRoute(isPublic = false): Promise<string> {
	const admin = getAdminClient();
	const id = crypto.randomUUID();
	// A climbing course: flat first half, steep second half, so the effort
	// model has terrain to bite on. ~0.001° lat ≈ 111 m.
	const waypoints = [];
	for (let i = 0; i <= 18; i++) {
		waypoints.push({ lat: 51.5 + i * 0.001, lng: -0.12, ele: i > 9 ? (i - 9) * 30 : 0 });
	}
	const { error } = await admin.from('routes').insert({
		id,
		user_id: USER_A.id,
		name: 'E2E Roadbook Course',
		waypoints,
		distance_m: 2000,
		is_public: isPublic
	});
	if (error) throw new Error(`seedRoute failed: ${error.message}`);

	// Aid station near the start, a cutoff near the middle (30-min limit).
	const mk = async (kind: string, label: string, lat: number, meta: object) => {
		const { error: e } = await admin.from('route_markers').insert({
			route_id: id,
			user_id: USER_A.id,
			kind,
			label,
			lat,
			lng: -0.12,
			meta
		});
		if (e) throw new Error(`marker ${label} failed: ${e.message}`);
	};
	await mk('aid_station', 'Aid 1', 51.5 + 4 * 0.001, { services: ['water', 'food'] });
	await mk('cutoff', 'Gate', 51.5 + 9 * 0.001, { cutoff_elapsed_s: 1800 });
	return id;
}

test.describe('/routes/[id]/roadbook', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let routeId: string | null = null;

	test.afterEach(async () => {
		if (routeId) {
			try {
				await deleteRoute(routeId);
			} catch (_) {
				/* cascade clears markers */
			}
			routeId = null;
		}
	});

	test('renders the schedule, flags a missed cutoff, and is URL-shareable', async ({ page }) => {
		routeId = await seedRoute();

		// A deliberately slow goal (2h) → the 30-min cutoff at mid-course is a miss.
		await page.goto(`/routes/${routeId}/roadbook?goal=7200&start=06:00&model=even`);

		const rows = page.locator('.rb-table tbody tr');
		await expect(rows).toHaveCount(4); // start, Aid 1, Gate, finish
		await expect(rows.nth(1)).toContainText('Aid 1');
		await expect(rows.nth(1)).toContainText('Water');
		await expect(rows.nth(2)).toContainText('Gate');

		// The cutoff at the slow goal is red (miss).
		await expect(rows.nth(2).locator('.cut-miss')).toBeVisible();

		// Tighten the goal to 30 min → the cutoff is no longer a miss.
		await page.getByLabel('Goal time').fill('0:30:00');
		await page.getByLabel('Goal time').blur();
		await expect(page).toHaveURL(/goal=1800/);
		await expect(rows.nth(2).locator('.cut-miss')).toHaveCount(0);
	});

	test('the leg-pace column exposes the effort model re-pacing the climb', async ({ page }) => {
		routeId = await seedRoute();

		const paceCells = page.locator('[data-testid="roadbook-leg-pace"]');
		// "m:ss /km" (or "/mi") → seconds. Unit-agnostic: every assertion below
		// is a ratio or an equality between two cells in the same unit.
		const paceSeconds = async (i: number): Promise<number> => {
			const raw = ((await paceCells.nth(i).textContent()) ?? '').trim();
			const [mm, ss] = raw.split(' ')[0].split(':').map(Number);
			return mm * 60 + ss;
		};

		// Even pacing: the flat leg into Aid 1 and the 270 m climb to the finish
		// are run at the same pace by construction.
		await page.goto(`/routes/${routeId}/roadbook?goal=7200&model=even`);
		await expect(page.getByRole('columnheader', { name: 'Leg pace' })).toBeVisible();
		await expect(paceCells).toHaveCount(4);
		await expect(paceCells.nth(0)).toHaveText('—'); // start has no preceding leg
		expect(Math.abs((await paceSeconds(3)) - (await paceSeconds(1)))).toBeLessThanOrEqual(2);

		// Effort pacing: the climb leg must be given materially more time per
		// kilometre than the flat one. Grading each point-pair on its own read
		// this 27 % climb as flat, so the two paces came out equal here too.
		await page.goto(`/routes/${routeId}/roadbook?goal=7200&model=effort`);
		await expect(paceCells).toHaveCount(4);
		const flat = await paceSeconds(1);
		const climb = await paceSeconds(3);
		expect(climb).toBeGreaterThan(flat * 2);
	});

	test('fueling overlay shows per-leg carbs + a carry hint, and ?carbs= re-scales', async ({ page }) => {
		routeId = await seedRoute();

		// 2h goal so the legs are long enough to carry meaningful fuel.
		await page.goto(`/routes/${routeId}/roadbook?goal=7200&fuel=1`);

		// The fueling columns appear when fuel=1.
		await expect(page.getByRole('columnheader', { name: 'Carbs' })).toBeVisible();
		await expect(page.getByRole('columnheader', { name: 'Fluid' })).toBeVisible();

		// A per-leg carbs figure shows on the Aid 1 row, and a carry hint is
		// rendered (the start leg carries fuel out to the first refill).
		const carbsCells = page.locator('[data-testid="fuel-carbs"]');
		await expect(carbsCells.first()).toContainText('g');
		await expect(page.locator('.carry-hint').first()).toBeVisible();
		await expect(page.locator('.carry-hint').first()).toContainText('gels');

		// Capture the Aid 1 leg carbs at the default rate.
		const aidCarbs = carbsCells.nth(1);
		const before = (await aidCarbs.textContent())?.trim();

		// Drive the rate via the shareable ?carbs= override — doubling it must
		// raise the displayed carbs.
		await page.goto(`/routes/${routeId}/roadbook?goal=7200&fuel=1&carbs=120`);
		await expect(async () => {
			const after = (await carbsCells.nth(1).textContent())?.trim();
			expect(after).not.toBe(before);
		}).toPass();
	});

	test('copy-as-text includes the cut-off limit time, not just the margin', async ({
		page,
		context
	}) => {
		routeId = await seedRoute();
		await context.grantPermissions(['clipboard-read', 'clipboard-write']);

		// start 06:00 + a 30-min cut-off limit ⇒ the crew sheet must carry the
		// wall-clock limit 06:30 on the Gate line (regression: fmtClock(undefined)
		// always rendered empty, so the copied text dropped the limit entirely).
		await page.goto(`/routes/${routeId}/roadbook?goal=1800&start=06:00&model=even`);
		await expect(page.locator('.rb-table tbody tr')).toHaveCount(4);

		await page.getByRole('button', { name: 'Copy' }).click();

		await expect
			.poll(async () => page.evaluate(() => navigator.clipboard.readText()), { timeout: 8_000 })
			.toContain('06:30');

		const text = await page.evaluate(() => navigator.clipboard.readText());
		const gateLine = text.split('\n').find((l) => l.includes('Gate')) ?? '';
		expect(gateLine).toContain('06:30');
	});

	test('downloads a GPX with markers containing the waypoints + a marker name', async ({
		page
	}) => {
		routeId = await seedRoute();
		await page.goto(`/routes/${routeId}/roadbook`);

		const downloadPromise = page.waitForEvent('download');
		await page.getByRole('button', { name: 'GPX + markers' }).click();
		const download = await downloadPromise;

		expect(download.suggestedFilename()).toMatch(/_with_markers\.gpx$/);

		const stream = await download.createReadStream();
		const chunks: Buffer[] = [];
		for await (const chunk of stream) chunks.push(Buffer.from(chunk));
		const gpx = Buffer.concat(chunks).toString('utf8');

		// The route line is present as a track…
		expect(gpx).toContain('<trkpt');
		// …and the seeded markers are emitted as waypoints with their names.
		expect(gpx).toContain('<wpt');
		expect(gpx).toContain('<name>Aid 1</name>');
		expect(gpx).toContain('<name>Gate</name>');
	});

	test('effort model re-paces vs even and updates the URL', async ({ page }) => {
		routeId = await seedRoute();
		await page.goto(`/routes/${routeId}/roadbook?goal=3600&model=even`);

		// Read the Gate arrival under even pacing.
		const gateArrival = page.locator('.rb-table tbody tr').nth(2).locator('td.num').nth(2);
		const evenText = (await gateArrival.textContent())?.trim();

		// Switch to effort — the flat first half is reached sooner, so the
		// mid-course Gate arrival should change.
		await page.getByRole('button', { name: 'Effort' }).click();
		await expect(page).toHaveURL(/model=effort/);
		await expect(async () => {
			const effortText = (await gateArrival.textContent())?.trim();
			expect(effortText).not.toBe(evenText);
		}).toPass();
	});

	test('owner saves projected arrivals as marker targets, preserving existing meta', async ({ page }) => {
		routeId = await seedRoute();
		await page.goto(`/routes/${routeId}/roadbook?goal=3600&model=even`);

		await page.getByRole('button', { name: 'Save as marker targets' }).click();
		await expect(page.getByText('Saved projected times to 2 markers')).toBeVisible({
			timeout: 10_000
		});

		// Server truth: both markers gained target_elapsed_s and kept their
		// pre-existing meta (services / cutoff).
		const { data, error } = await getAdminClient()
			.from('route_markers')
			.select('label, meta')
			.eq('route_id', routeId);
		if (error) throw new Error(error.message);
		const byLabel = new Map((data ?? []).map((r) => [r.label, r.meta as Record<string, unknown>]));
		const aid = byLabel.get('Aid 1');
		const gate = byLabel.get('Gate');
		expect(typeof aid?.target_elapsed_s).toBe('number');
		expect(typeof gate?.target_elapsed_s).toBe('number');
		expect(aid?.services).toEqual(['water', 'food']);
		expect(gate?.cutoff_elapsed_s).toBe(1800);
		// Course order: the mid-course Gate's target is after Aid 1's, and
		// both sit inside the 1h goal.
		expect(gate!.target_elapsed_s as number).toBeGreaterThan(aid!.target_elapsed_s as number);
		expect(gate!.target_elapsed_s as number).toBeLessThanOrEqual(3600);

		// And the route detail's course schedule now shows the Target chips.
		await page.goto(`/routes/${routeId}`);
		const details = page.locator('.markers-list .marker-row .marker-detail');
		await expect(details.nth(0)).toContainText('Target');
		await expect(details.nth(1)).toContainText('Target');
	});
});

test.describe('/routes/[id]/roadbook — non-owner', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let routeId: string | null = null;

	test.afterEach(async () => {
		if (routeId) {
			try {
				await deleteRoute(routeId);
			} catch (_) {
				/* cascade clears markers */
			}
			routeId = null;
		}
	});

	test('a viewer never sees the save-as-targets button', async ({ page }) => {
		routeId = await seedRoute(true);
		await page.goto(`/routes/${routeId}/roadbook?goal=3600&model=even`);

		// The roadbook itself renders for a public route…
		await expect(page.locator('.rb-table tbody tr')).toHaveCount(4);
		// …but writing targets onto someone else's markers is owner-only.
		await expect(page.getByRole('button', { name: 'Save as marker targets' })).toHaveCount(0);
	});
});

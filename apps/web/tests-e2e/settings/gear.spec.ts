import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * /settings/gear — current-gear (is_default) star toggle.
 *
 * Pins the partial-unique-default invariant from migration
 * 20260901_001: at most one non-retired gear item per (owner, kind)
 * can carry is_default = true at a time. The settings page exposes
 * this as a star button on each gear card; clicking it flips the
 * default and (if necessary) unsets the previous default of the
 * same kind. The trigger on `runs insert` then auto-tags new runs
 * with whichever gear holds the star.
 *
 * Seed shape used by the asserts:
 *   - 'Pegasus 40' (shoe, is_default=true)
 *   - 'Ghost 16'   (shoe, is_default=false)
 */
test.describe('/settings/gear — current-gear toggle', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('star toggle moves the current default to a different shoe; partial-unique invariant holds', async ({
		page
	}) => {
		const admin = getAdminClient();

		// Pre-condition pin: seed put Pegasus 40 as the current shoe.
		const before = await admin
			.from('gear')
			.select('name, is_default')
			.eq('owner_id', USER_A.id)
			.eq('kind', 'shoe')
			.eq('is_default', true);
		expect(before.data?.length ?? 0).toBe(1);
		expect(before.data?.[0]?.name).toBe('Pegasus 40');

		await page.goto('/settings/gear');
		await expect(page.locator('.gear-list')).toBeVisible({ timeout: 10_000 });

		// The Pegasus row carries the "Current" pill; the Ghost row
		// does not.
		const pegasusRow = page.locator('.gear-row', { hasText: 'Pegasus 40' });
		const ghostRow = page.locator('.gear-row', { hasText: 'Ghost 16' });
		await expect(pegasusRow.locator('.default-pill')).toBeVisible();
		await expect(ghostRow.locator('.default-pill')).toHaveCount(0);

		// Click the star on the Ghost row → it becomes the new default.
		await ghostRow
			.getByRole('button', { name: /Mark Ghost 16 as current/ })
			.click();

		// UI flips: Current pill now lives on Ghost, gone from Pegasus.
		await expect(ghostRow.locator('.default-pill')).toBeVisible({
			timeout: 5_000
		});
		await expect(pegasusRow.locator('.default-pill')).toHaveCount(0);

		// Backend: still exactly one shoe-default, and it's Ghost.
		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('gear')
						.select('name')
						.eq('owner_id', USER_A.id)
						.eq('kind', 'shoe')
						.eq('is_default', true);
					return data?.map((g) => g.name) ?? [];
				},
				{ timeout: 5_000 }
			)
			.toEqual(['Ghost 16']);

		// Restore so the rest of the suite sees the seeded default state.
		await pegasusRow
			.getByRole('button', { name: /Mark Pegasus 40 as current/ })
			.click();
		await expect(pegasusRow.locator('.default-pill')).toBeVisible({
			timeout: 5_000
		});
	});

	test('clicking the star on the current default clears it — no default until the user re-stars one', async ({
		page
	}) => {
		const admin = getAdminClient();

		await page.goto('/settings/gear');
		await expect(page.locator('.gear-list')).toBeVisible({ timeout: 10_000 });

		const pegasusRow = page.locator('.gear-row', { hasText: 'Pegasus 40' });
		await pegasusRow
			.getByRole('button', { name: /Unmark Pegasus 40 as current/ })
			.click();

		// UI: no row has the Current pill anymore.
		await expect(page.locator('.default-pill')).toHaveCount(0, {
			timeout: 5_000
		});

		// Backend: no shoe-default.
		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('gear')
						.select('id')
						.eq('owner_id', USER_A.id)
						.eq('kind', 'shoe')
						.eq('is_default', true);
					return data?.length ?? 0;
				},
				{ timeout: 5_000 }
			)
			.toBe(0);

		// Restore.
		await pegasusRow
			.getByRole('button', { name: /Mark Pegasus 40 as current/ })
			.click();
		await expect(pegasusRow.locator('.default-pill')).toBeVisible({
			timeout: 5_000
		});
	});
});

test.describe('/settings/gear — CRUD', () => {
	test.use({ storageState: USER_A.storageStatePath });

	// Sweep anything the tests below plant on USER_A. Seed gear lives at
	// the pinned UUIDs 11111111-aaaa-bbbb-cccc-222222222201 (Pegasus 40,
	// default) and ...02 (Ghost 16). Anything else under USER_A is a
	// test artifact. Restoring Pegasus as default protects downstream
	// specs (gear-auto-tag-flow + the current-gear toggle suite above)
	// from a half-finished test that flipped the star.
	const PEGASUS_GEAR_ID = '11111111-aaaa-bbbb-cccc-222222222201';
	const SEED_IDS = [
		PEGASUS_GEAR_ID,
		'11111111-aaaa-bbbb-cccc-222222222202',
	];

	test.afterEach(async () => {
		const admin = getAdminClient();
		await admin
			.from('gear')
			.delete()
			.eq('owner_id', USER_A.id)
			.not('id', 'in', `(${SEED_IDS.join(',')})`);
		await admin
			.from('gear')
			.update({ is_default: false })
			.eq('owner_id', USER_A.id);
		await admin
			.from('gear')
			.update({ is_default: true, retired_at: null })
			.eq('id', PEGASUS_GEAR_ID);
		await admin
			.from('gear')
			.update({ retired_at: null })
			.in('id', SEED_IDS);
	});

	test('add a new shoe via the modal — appears in the list + DB row exists', async ({
		page
	}) => {
		const admin = getAdminClient();
		const planted = `E2E Endorphin ${Date.now()}`;

		await page.goto('/settings/gear');
		await expect(page.locator('.gear-list')).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: /New shoes/, exact: false }).first().click();
		await page.locator('input[placeholder="Pegasus 39"]').fill(planted);
		await page.locator('input[placeholder="Nike"]').fill('Saucony');
		await page.locator('input[placeholder="Air Zoom Pegasus 39"]').fill('Endorphin Pro 4');
		await page.locator('input[type="number"]').fill('600');
		await page.getByRole('button', { name: 'Add', exact: true }).click();

		await expect(
			page.locator('.gear-row', { hasText: planted })
		).toBeVisible({ timeout: 10_000 });

		const { data } = await admin
			.from('gear')
			.select('kind, brand, model, target_distance_m')
			.eq('owner_id', USER_A.id)
			.eq('name', planted)
			.maybeSingle();
		expect(data?.kind).toBe('shoe');
		expect(data?.brand).toBe('Saucony');
		expect(data?.model).toBe('Endorphin Pro 4');
		// km tab default = 600 km × 1000 m/km.
		expect(data?.target_distance_m).toBe(600_000);
	});

	test('edit an existing shoe — retirement target round-trips via the modal', async ({
		page
	}) => {
		const admin = getAdminClient();
		const planted = `E2E Edit Pair ${Date.now()}`;
		const { data: created } = await admin
			.from('gear')
			.insert({
				owner_id: USER_A.id,
				kind: 'shoe',
				name: planted,
				target_distance_m: 400_000,
			})
			.select('id')
			.single();

		await page.goto('/settings/gear');
		const row = page.locator('.gear-row', { hasText: planted });
		await expect(row).toBeVisible({ timeout: 10_000 });

		// Click the row body to open the edit modal.
		await row.locator('.gear-main').click();
		const dialog = page.locator('.modal');
		await expect(dialog).toBeVisible({ timeout: 5_000 });

		const targetInput = dialog.locator('input[type="number"]');
		await expect(targetInput).toHaveValue('400');
		await targetInput.fill('750');
		await page.getByRole('button', { name: 'Save', exact: true }).click();

		await expect(dialog).toBeHidden({ timeout: 5_000 });

		// Reload — the new target persisted.
		await page.reload();
		await expect(page.locator('.gear-row', { hasText: planted })).toBeVisible({
			timeout: 10_000
		});
		const { data } = await admin
			.from('gear')
			.select('target_distance_m')
			.eq('id', created!.id)
			.maybeSingle();
		expect(data?.target_distance_m).toBe(750_000);
	});

	test('retire + restore a shoe — Retired section + Restore button toggle', async ({
		page
	}) => {
		const admin = getAdminClient();
		const planted = `E2E Retire Pair ${Date.now()}`;
		await admin.from('gear').insert({
			owner_id: USER_A.id,
			kind: 'shoe',
			name: planted,
			target_distance_m: 500_000,
		});

		await page.goto('/settings/gear');
		const row = page.locator('.gear-row', { hasText: planted });
		await expect(row).toBeVisible({ timeout: 10_000 });
		await expect(row).not.toHaveClass(/retired/);

		await row.getByRole('button', { name: 'Retire', exact: true }).click();

		// After retire, the row is now under the retired list and renders
		// a Restore button instead.
		const retiredRow = page
			.locator('.gear-row.retired', { hasText: planted });
		await expect(retiredRow).toBeVisible({ timeout: 10_000 });
		await expect(
			retiredRow.getByRole('button', { name: 'Restore' })
		).toBeVisible();
		await expect(
			page.getByRole('heading', { name: 'Retired', level: 3 })
		).toBeVisible();

		// Restore — row leaves the retired list, comes back into active.
		await retiredRow.getByRole('button', { name: 'Restore' }).click();
		await expect(
			page.locator('.gear-row.retired', { hasText: planted })
		).toHaveCount(0, { timeout: 5_000 });
		await expect(
			page.locator('.gear-row', { hasText: planted })
		).not.toHaveClass(/retired/);
	});

	test('add a bike — kind=bike row appears on the Bikes tab, not Shoes', async ({
		page
	}) => {
		const admin = getAdminClient();
		const planted = `E2E Allroad ${Date.now()}`;

		await page.goto('/settings/gear');
		// Default tab is Shoes. Flip to Bikes first.
		await page.getByRole('button', { name: /^Bikes$/ }).click();
		await page.getByRole('button', { name: /New bike/, exact: false }).first().click();

		await page.locator('input[placeholder="Pegasus 39"]').fill(planted);
		await page.locator('input[placeholder="Nike"]').fill('Specialized');
		await page.locator('input[placeholder="Air Zoom Pegasus 39"]').fill('Allez');
		await page.locator('input[type="number"]').fill('5000');
		await page.getByRole('button', { name: 'Add', exact: true }).click();

		await expect(
			page.locator('.gear-row', { hasText: planted })
		).toBeVisible({ timeout: 10_000 });

		// Backend: kind is bike, target = 5000 km.
		const { data } = await admin
			.from('gear')
			.select('kind, target_distance_m')
			.eq('owner_id', USER_A.id)
			.eq('name', planted)
			.maybeSingle();
		expect(data?.kind).toBe('bike');
		expect(data?.target_distance_m).toBe(5_000_000);

		// Flip back to Shoes tab — the bike must not render there.
		await page.getByRole('button', { name: /^Shoes$/ }).click();
		await expect(
			page.locator('.gear-row', { hasText: planted })
		).toHaveCount(0);
	});

	test('delete a shoe via the confirmation dialog — row disappears + DB row gone', async ({
		page
	}) => {
		const admin = getAdminClient();
		const planted = `E2E Delete Pair ${Date.now()}`;
		const { data: created } = await admin
			.from('gear')
			.insert({
				owner_id: USER_A.id,
				kind: 'shoe',
				name: planted,
			})
			.select('id')
			.single();

		await page.goto('/settings/gear');
		const row = page.locator('.gear-row', { hasText: planted });
		await expect(row).toBeVisible({ timeout: 10_000 });

		await row.getByRole('button', { name: 'Delete', exact: true }).click();

		// Confirmation dialog comes up — title pinned, message references
		// the gear name. Confirm.
		const dialog = page.locator('.modal');
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await expect(
			dialog.getByRole('heading', { name: 'Delete gear?' })
		).toBeVisible();
		await expect(dialog).toContainText(planted);
		await dialog.getByRole('button', { name: 'Delete', exact: true }).click();

		await expect(
			page.locator('.gear-row', { hasText: planted })
		).toHaveCount(0, { timeout: 5_000 });

		const { data } = await admin
			.from('gear')
			.select('id')
			.eq('id', created!.id)
			.maybeSingle();
		expect(data).toBeNull();
	});

	test('per-kind defaults — shoe default and bike default coexist; partial-unique invariant holds independently per kind', async ({
		page
	}) => {
		const admin = getAdminClient();
		const bikeName = `E2E Default Bike ${Date.now()}`;
		await admin
			.from('gear')
			.insert({
				owner_id: USER_A.id,
				kind: 'bike',
				name: bikeName,
			});

		await page.goto('/settings/gear');
		await page.getByRole('button', { name: /^Bikes$/ }).click();
		const bikeRow = page.locator('.gear-row', { hasText: bikeName });
		await expect(bikeRow).toBeVisible({ timeout: 10_000 });

		await bikeRow
			.getByRole('button', { name: new RegExp(`Mark ${bikeName} as current`) })
			.click();
		await expect(bikeRow.locator('.default-pill')).toBeVisible({
			timeout: 5_000
		});

		// Backend: exactly one bike default + exactly one shoe default
		// for this owner. The partial-unique index keys on (owner_id,
		// kind), so a bike default cannot displace the existing shoe
		// default — pinning this guards against a regression that
		// over-broadened the clear-defaults UPDATE in setDefaultGear.
		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('gear')
						.select('kind, name')
						.eq('owner_id', USER_A.id)
						.eq('is_default', true);
					return (data ?? [])
						.map((g) => `${g.kind}:${g.name}`)
						.sort();
				},
				{ timeout: 5_000 }
			)
			.toEqual([`bike:${bikeName}`, 'shoe:Pegasus 40']);

		// Sanity: shoe tab still shows Pegasus 40 with the Current pill.
		await page.getByRole('button', { name: /^Shoes$/ }).click();
		await expect(
			page
				.locator('.gear-row', { hasText: 'Pegasus 40' })
				.locator('.default-pill')
		).toBeVisible();
	});
});

test.describe('/settings/gear — wear log', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('add + delete a wear observation in the edit modal; DB row scoped to the gear', async ({
		page
	}) => {
		const admin = getAdminClient();
		const name = `E2E Wear Shoe ${Date.now()}`;
		const { data: gear } = await admin
			.from('gear')
			.insert({ owner_id: USER_A.id, kind: 'shoe', name })
			.select('id')
			.single();

		try {
			await page.goto('/settings/gear');
			const row = page.locator('.gear-row', { hasText: name });
			await expect(row).toBeVisible({ timeout: 10_000 });

			// Open the edit modal — the wear log only renders for an existing item.
			await row.locator('.gear-main').click();
			const dialog = page.locator('.modal');
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			const wearLog = dialog.getByTestId('wear-log');
			await expect(wearLog).toBeVisible();
			await expect(wearLog).toContainText('No wear observations yet.');

			// Add an observation with an area.
			const note = `outsole lugs worn ${Date.now()}`;
			await wearLog.getByRole('textbox', { name: 'Observation' }).fill(note);
			await wearLog.getByRole('combobox', { name: 'Area' }).selectOption('outsole');
			await wearLog.getByRole('button', { name: 'Add observation' }).click();

			// Renders in the list with its area pill.
			const item = wearLog.locator('.wear-item', { hasText: note });
			await expect(item).toBeVisible({ timeout: 5_000 });
			await expect(item).toContainText('Outsole');

			// Backend: exactly one row for this gear, scoped to the owner.
			await expect
				.poll(
					async () => {
						const { data } = await admin
							.from('gear_wear_logs')
							.select('note, area')
							.eq('gear_id', gear!.id);
						return data ?? [];
					},
					{ timeout: 5_000 }
				)
				.toEqual([{ note, area: 'outsole' }]);

			// Delete it — now gated by a ConfirmDialog (matching the gear +
			// rotation deletes on this page). The delete icon only OPENS the
			// confirm; the row must survive until the user confirms.
			await item.getByRole('button', { name: 'Delete observation' }).click();
			// The confirm dialog (scoped by its .confirm-body) is the only new
			// surface — its "Delete" confirm button appears.
			const wearConfirm = page
				.locator('.confirm-body')
				.getByRole('button', { name: 'Delete', exact: true });
			await expect(wearConfirm).toBeVisible({ timeout: 5_000 });
			// Still present — a mere tap didn't destroy the observation.
			await expect(wearLog.locator('.wear-item', { hasText: note })).toHaveCount(1);
			await wearConfirm.click();
			await expect(wearLog.locator('.wear-item', { hasText: note })).toHaveCount(0, {
				timeout: 5_000
			});
			await expect
				.poll(
					async () => {
						const { count } = await admin
							.from('gear_wear_logs')
							.select('id', { count: 'exact', head: true })
							.eq('gear_id', gear!.id);
						return count ?? 0;
					},
					{ timeout: 5_000 }
				)
				.toBe(0);
		} finally {
			await admin.from('gear').delete().eq('id', gear!.id); // cascades wear logs
		}
	});
});

test.describe('/settings/gear — empty state', () => {
	// USER_C_PRO has no gear in the seed; the empty card with the
	// "No shoes yet" header + per-kind CTA should render. After adding a
	// pair the empty card disappears and the list takes over.
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test.afterEach(async () => {
		const admin = getAdminClient();
		await admin.from('gear').delete().eq('owner_id', USER_C_PRO.id);
	});

	test('fresh user sees the empty card; adding a pair flips into the list', async ({
		page
	}) => {
		const admin = getAdminClient();

		await page.goto('/settings/gear');
		await expect(
			page.getByRole('heading', { name: 'No shoes yet' })
		).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.gear-list')).toHaveCount(0);

		// CTA inside the empty card opens the same create modal.
		await page
			.locator('.empty-card')
			.getByRole('button', { name: /Add shoes/ })
			.click();
		const planted = `E2E First Pair ${Date.now()}`;
		await page.locator('input[placeholder="Pegasus 39"]').fill(planted);
		await page.getByRole('button', { name: 'Add', exact: true }).click();

		await expect(
			page.locator('.gear-row', { hasText: planted })
		).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.empty-card')).toHaveCount(0);

		// Sanity: backend row exists with owner_id = USER_C_PRO.
		const { data } = await admin
			.from('gear')
			.select('name')
			.eq('owner_id', USER_C_PRO.id);
		expect(data?.map((g) => g.name)).toContain(planted);
	});
});

test.describe('/settings/gear — rotations', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		const admin = getAdminClient();
		// gear_rotations cascade their members; only the rotations are test
		// artifacts here (seed gear stays).
		await admin.from('gear_rotations').delete().eq('owner_id', USER_A.id);
	});

	test('create a rotation, assign gear, filter the list, then delete it', async ({
		page
	}) => {
		const admin = getAdminClient();
		const rotName = `E2E Daily ${Date.now()}`;

		await page.goto('/settings/gear');
		await expect(page.locator('.gear-list')).toBeVisible({ timeout: 10_000 });

		// Create a rotation.
		await page
			.locator('.rotation-create input')
			.fill(rotName);
		await page
			.locator('.rotation-create')
			.getByRole('button', { name: 'Create' })
			.click();

		const rotRow = page.locator('.rotation-row', { hasText: rotName });
		await expect(rotRow).toBeVisible({ timeout: 5_000 });

		// Backend: rotation row exists, owned by USER_A.
		const { data: created } = await admin
			.from('gear_rotations')
			.select('id, name')
			.eq('owner_id', USER_A.id)
			.eq('name', rotName)
			.maybeSingle();
		expect(created?.name).toBe(rotName);

		// Assign the Ghost 16 (a seed shoe) to the rotation via the member modal.
		await rotRow.getByRole('button', { name: 'Edit gear' }).click();
		const memberModal = page.locator('.modal');
		await expect(memberModal).toBeVisible({ timeout: 5_000 });
		await memberModal
			.locator('.member-row', { hasText: 'Ghost 16' })
			.locator('input[type="checkbox"]')
			.check();
		await memberModal.getByRole('button', { name: 'Done' }).click();
		await expect(memberModal).toBeHidden({ timeout: 5_000 });

		// Backend: exactly one membership, pointing at Ghost 16's id.
		const GHOST_ID = '11111111-aaaa-bbbb-cccc-222222222202';
		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('gear_rotation_members')
						.select('gear_id')
						.eq('rotation_id', created!.id);
					return data?.map((m) => m.gear_id) ?? [];
				},
				{ timeout: 5_000 }
			)
			.toEqual([GHOST_ID]);

		// Member count chip updates.
		await expect(rotRow).toContainText('1 item');

		// Filter by the rotation: only Ghost 16 shows, Pegasus 40 hides.
		await page.locator('.rotation-filter select').selectOption(rotName);
		await expect(
			page.locator('.gear-row', { hasText: 'Ghost 16' })
		).toBeVisible();
		await expect(
			page.locator('.gear-row', { hasText: 'Pegasus 40' })
		).toHaveCount(0);

		// Back to All — both shoes show again.
		await page.locator('.rotation-filter select').selectOption({ label: 'All' });
		await expect(
			page.locator('.gear-row', { hasText: 'Pegasus 40' })
		).toBeVisible();

		// Delete the rotation via the confirm dialog.
		await rotRow.getByRole('button', { name: 'Delete', exact: true }).click();
		const confirm = page.locator('.modal');
		await expect(
			confirm.getByRole('heading', { name: 'Delete rotation?' })
		).toBeVisible({ timeout: 5_000 });
		await confirm.getByRole('button', { name: 'Delete', exact: true }).click();

		await expect(
			page.locator('.rotation-row', { hasText: rotName })
		).toHaveCount(0, { timeout: 5_000 });

		// Backend: rotation gone (membership cascaded). Gear itself untouched.
		await expect
			.poll(
				async () => {
					const { count } = await admin
						.from('gear_rotations')
						.select('id', { count: 'exact', head: true })
						.eq('id', created!.id);
					return count ?? 0;
				},
				{ timeout: 5_000 }
			)
			.toBe(0);
		const { count: ghostStillThere } = await admin
			.from('gear')
			.select('id', { count: 'exact', head: true })
			.eq('id', GHOST_ID);
		expect(ghostStillThere).toBe(1);
	});

	test('rename a rotation persists', async ({ page }) => {
		const admin = getAdminClient();
		const orig = `E2E Rot ${Date.now()}`;
		const { data: rot } = await admin
			.from('gear_rotations')
			.insert({ owner_id: USER_A.id, name: orig })
			.select('id')
			.single();

		await page.goto('/settings/gear');
		const rotRow = page.locator('.rotation-row', { hasText: orig });
		await expect(rotRow).toBeVisible({ timeout: 10_000 });

		await rotRow.getByRole('button', { name: 'Rename' }).click();
		const dialog = page.locator('.modal');
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		const renamed = `${orig} renamed`;
		await dialog.locator('input[type="text"]').fill(renamed);
		await dialog.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(dialog).toBeHidden({ timeout: 5_000 });

		await expect(
			page.locator('.rotation-row', { hasText: renamed })
		).toBeVisible({ timeout: 5_000 });
		const { data } = await admin
			.from('gear_rotations')
			.select('name')
			.eq('id', rot!.id)
			.maybeSingle();
		expect(data?.name).toBe(renamed);
	});
});

test.describe('/settings/gear — wear status', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a shoe past its replacement distance shows the worn badge', async ({ page }) => {
		const admin = getAdminClient();
		const name = `E2E Worn Shoe ${Date.now()}`;

		// Target 1 km; a 5 km run linked via run_gear pushes total > target so
		// the gear_with_distance rollup → gearWear → 'worn'.
		const { data: gear } = await admin
			.from('gear')
			.insert({
				owner_id: USER_A.id,
				kind: 'shoe',
				name,
				target_distance_m: 1000,
			})
			.select('id')
			.single();
		const { data: run } = await admin
			.from('runs')
			.insert({
				user_id: USER_A.id,
				started_at: new Date().toISOString(),
				distance_m: 5000,
				duration_s: 1500,
				source: 'app',
				is_public: false,
				metadata: { activity_type: 'run' },
			})
			.select('id')
			.single();
		await admin.from('run_gear').insert({ run_id: run!.id, gear_id: gear!.id });

		try {
			await page.goto('/settings/gear');
			const row = page.locator('.gear-row', { hasText: name });
			await expect(row).toBeVisible({ timeout: 10_000 });
			await expect(row.getByTestId('wear-badge')).toContainText('Past replacement distance');
		} finally {
			await admin.from('runs').delete().eq('id', run!.id); // cascades run_gear
			await admin.from('gear').delete().eq('id', gear!.id);
		}
	});
});

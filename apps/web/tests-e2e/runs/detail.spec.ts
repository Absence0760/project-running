import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';
import type { TrackPoint } from '../../src/lib/types';

/**
 * /runs/[id] — owner-only run detail page.
 *
 * Operations covered: render, inline edit Save, inline edit Cancel.
 * The cross-user-isolation case (User A cannot see User B's private
 * run) is in cross-cutting/auth-walls.spec.ts. The kudos / comment
 * surfaces are reachable from /share/run/ for non-owners — those
 * tests live under cross-user/ and share/.
 *
 * Future depth here: photos upload + delete, segment-effort chip
 * generation, share-link copy, manual workout-mark-done from a plan.
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('/runs/[id]', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('mounts with the seeded run title as h1', async ({ page }) => {
		// Use the pinned runner public run so this test is deterministic.
		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);
		// Run-detail fetches the row + (lazily) the track via Storage.

		// Title is the metadata.title we seeded. If the run loaded, the
		// h1 reflects it. We don't assert the map mounts — the seeded
		// run has no track in Storage so RunMap never renders. The
		// inline-edit tests below cover track-less runs adequately.
		await expect(
			page.getByRole('heading', { name: 'E2E demo public run', level: 1 })
		).toBeVisible();
	});

	test('inline edit title — save persists across reload, restore', async ({
		page
	}) => {
		const newTitle = uniqueText('renamed');
		const originalTitle = 'E2E demo public run';

		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);

		// Open the inline editor. The Edit button is an .icon-btn with
		// title="Edit"; selecting by accessible name is more brittle
		// because the title attribute isn't always exposed as the
		// accessible name in Chromium. Use the exact title.
		await page.locator('button[title="Edit"]').first().click();

		// editTitle prefills with the current title — clear + replace.
		const titleInput = page.locator('input.edit-input');
		await titleInput.fill(newTitle);
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		// `saveEdit` awaits the network call before flipping
		// `editing = false`; wait for the form to close so the reload
		// below sees a persisted state, not in-flight optimistic UI.
		await expect(page.locator('input.edit-input')).toHaveCount(0);

		// Reload to confirm persistence — not a stale local state.
		await page.reload();
		await expect(
			page.getByRole('heading', { name: newTitle, level: 1 })
		).toBeVisible();

		// Restore so the spec is idempotent.
		await page.locator('button[title="Edit"]').first().click();
		await page.locator('input.edit-input').fill(originalTitle);
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(page.locator('input.edit-input')).toHaveCount(0);
		await page.reload();
		await expect(
			page.getByRole('heading', { name: originalTitle, level: 1 })
		).toBeVisible();
	});

	test('inline edit notes — save persists across reload, restore', async ({
		page
	}) => {
		// Companion to the title test: same updateRunMetadata path,
		// different field. The metadata jsonb merge has independent
		// risks per key — a save that drops the notes field would
		// pass the title test but fail this one.
		const newNotes = uniqueText('e2e-notes');

		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);

		// The pinned public run has no seeded notes — the .run-notes
		// paragraph is absent. Open the editor.
		await page.locator('button[title="Edit"]').first().click();
		const notesArea = page.locator('textarea.edit-textarea');
		await expect(notesArea).toBeVisible();
		await notesArea.fill(newNotes);
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(page.locator('input.edit-input')).toHaveCount(0);

		// Reload — notes must persist via the metadata jsonb.
		await page.reload();
		await expect(page.locator('p.run-notes')).toHaveText(newNotes, {
			timeout: 10_000
		});

		// Restore to empty notes so the seed shape is preserved.
		await page.locator('button[title="Edit"]').first().click();
		await page.locator('textarea.edit-textarea').fill('');
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(page.locator('input.edit-input')).toHaveCount(0);
		await page.reload();
		await expect(page.locator('p.run-notes')).toHaveCount(0);
	});

	test('inline edit title — Cancel reverts unsaved changes', async ({
		page
	}) => {
		// Companion to the Save test above. Catches a regression where
		// Cancel accidentally writes (e.g. a refactor wiring Save and
		// Cancel to the same handler).
		const originalTitle = 'E2E demo public run';
		const draft = uniqueText('e2e-cancel-draft');

		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);

		// Confirm starting state.
		await expect(
			page.getByRole('heading', { name: originalTitle, level: 1 })
		).toBeVisible({ timeout: 10_000 });

		await page.locator('button[title="Edit"]').first().click();
		await page.locator('input.edit-input').fill(draft);
		await page.getByRole('button', { name: 'Cancel', exact: true }).click();

		// Editor closes immediately and the heading reads the original
		// title — no save fired.
		await expect(page.locator('input.edit-input')).toHaveCount(0);
		await expect(
			page.getByRole('heading', { name: originalTitle, level: 1 })
		).toBeVisible();

		// Reload to confirm nothing landed on the row server-side.
		await page.reload();
		await expect(
			page.getByRole('heading', { name: originalTitle, level: 1 })
		).toBeVisible();
	});

	test('delete-from-detail: trash icon → confirm → redirect to /runs, row gone', async ({
		page
	}) => {
		// runs/list.spec.ts pins the bulk-delete from the list page.
		// This pins the single-run delete from the detail page —
		// distinct UI (the .icon-btn.danger trash next to the share /
		// edit affordances), distinct callsite for deleteRun, distinct
		// post-delete navigation (goto('/runs') instead of staying on
		// the list).
		const planted = await insertRun({
			user_id: USER_A.id,
			distance_m: 4_000,
			duration_s: 1_200,
			is_public: false
		});

		await page.goto(`/runs/${planted}`);
		await expect(page.getByRole('heading', { level: 1 }))
			.toBeVisible({ timeout: 10_000 });

		// Trash button is icon-only with title="Delete".
		await page.locator('button[title="Delete"]').click();
		const dialog = page.locator('.modal');
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Delete', exact: true }).click();

		// confirmDelete() calls deleteRun + goto('/runs').
		await page.waitForURL(/\/runs$/, { timeout: 10_000 });

		// Sanity: the run's storage row is gone in the DB. Re-listing
		// would require driving the date filter to All-time which is
		// flaky here (the runs-list filter UI is exercised in
		// runs/list.spec.ts already). The DB state is the contract —
		// deleteRun under the hood deletes the row, and the goto to
		// /runs proves the handler completed without throwing.
		const adminCheck = await import('../fixtures/local-supabase').then((m) =>
			m.getAdminClient()
		);
		const { data: stillThere } = await adminCheck
			.from('runs')
			.select('id')
			.eq('id', planted)
			.maybeSingle();
		expect(stillThere).toBeNull();
	});

	test('Share link button on a private run flips is_public=true and opens /share/run for anon', async ({
		page,
		context
	}) => {
		// Private runs return 404 from /share/run for anon. Clicking the
		// "Share link" icon-btn now opens a consent dialog (decisions §33
		// — sharing flips is_public, exposing the full track to anyone
		// with the link). Confirming the dialog calls makeRunPublic()
		// which sets runs.is_public=true and copies a shareable URL.
		// After that the /share/run/[id] page must mount for an
		// unauthenticated viewer. Pin the round-trip so a regression in
		// makeRunPublic (or its underlying RLS policy) shows up as a 404
		// against /share.
		const planted = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: false
		});

		try {
			// Grant clipboard perms so navigator.clipboard.writeText
			// inside makeRunPublic doesn't reject.
			await context.grantPermissions(['clipboard-read', 'clipboard-write']);

			await page.goto(`/runs/${planted}`);
			await page.locator('button[title="Share link"]').click();

			// Consent dialog gates the public-flip. Confirm it explicitly.
			const dialog = page.locator('[data-testid="share-confirm-dialog"]');
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await expect(dialog).toContainText('Make this run public?');
			await dialog.locator('button', { hasText: /Make public/ }).click();

			// Toast confirms success — the makeRunPublic call resolved.
			await expect(page.locator('.toast', { hasText: /Share link copied/ }))
				.toBeVisible({ timeout: 10_000 });

			// In-page assertion (no reload): the visibility chip must flip
			// to "Public" the instant the share succeeds. Pins the fix for
			// the stale chip — proceedShare reassigns the local `run` so the
			// chip + share button stop reading the old is_public=false.
			await expect(page.locator('.visibility-chip.is-public'))
				.toContainText('Public', { timeout: 5_000 });

			// Backend assertion: runs.is_public flipped.
			const admin = getAdminClient();
			const { data: row } = await admin
				.from('runs')
				.select('is_public')
				.eq('id', planted)
				.single();
			expect(row?.is_public).toBe(true);

			// Anon /share/run/[id] now resolves (vs the 404 it would
			// have hit while is_public=false). Use a fresh anon context
			// so we don't carry runner's auth.
			const anonContext = await context.browser()!.newContext({
				storageState: { cookies: [], origins: [] }
			});
			const anonPage = await anonContext.newPage();
			try {
				await anonPage.route('**/functions/v1/clip-public-track', (route) =>
					route.fulfill({
						status: 200,
						contentType: 'application/json',
						body: JSON.stringify({ points: [] })
					})
				);
				await anonPage.goto(`/share/run/${planted}`);
				// Share-page mounts RunShareView with .run-meta — same
				// signal share/run.spec.ts uses to confirm the page
				// rendered for anon (vs. the 404 path).
				await expect(anonPage.locator('.run-meta'))
					.toBeVisible({ timeout: 10_000 });
			} finally {
				await anonContext.close();
			}
		} finally {
			await deleteRun(planted);
		}
	});

	test('Share dialog Cancel keeps the run private (consent gate)', async ({
		page,
		context
	}) => {
		// Persona-hunt finding (Casual #1, decisions §33): the share
		// flow USED to flip is_public silently. The dialog now gates
		// the flip; if the user cancels, the run must stay private.
		// Pin so a refactor that calls makeRunPublic on Cancel surfaces
		// here as a privacy regression, not just a UX one.
		const planted = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: false
		});

		try {
			await context.grantPermissions(['clipboard-read', 'clipboard-write']);
			await page.goto(`/runs/${planted}`);
			await page.locator('button[title="Share link"]').click();

			const dialog = page.locator('[data-testid="share-confirm-dialog"]');
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.locator('button', { hasText: /Cancel/ }).click();

			// is_public must STILL be false after cancel.
			const admin = getAdminClient();
			const { data: row } = await admin
				.from('runs')
				.select('is_public')
				.eq('id', planted)
				.single();
			expect(row?.is_public).toBe(false);

			// No success toast either — the share never happened.
			await expect(
				page.locator('.toast', { hasText: /Share link copied/ })
			).toHaveCount(0);
		} finally {
			await deleteRun(planted);
		}
	});

	test('run without a GPS track shows a real empty-state instead of a fake Melbourne circle', async ({
		page
	}) => {
		// Real bug surfaced during the /runs/[id] polish round: when a
		// run has no track (manual entry, parkrun row, HealthKit summary
		// without polyline) the page synthesised a fake circular track
		// centred on (-37.8136, 144.9631) — Melbourne — and rendered it
		// on the map as if it were real GPS. Users would see a route
		// they never ran. Fix: drop the synthesised fallback, gate the
		// map render on the track being non-empty, and surface a clear
		// empty-state instead. The elevation profile is also hidden in
		// this case because every point would read as 0m.
		const planted = await insertRun({
			user_id: USER_A.id,
			distance_m: 5000,
			duration_s: 1800,
			source: 'app',
			is_public: false
			// no `track` passed → run.track stays null
		});
		try {
			await page.goto(`/runs/${planted}`);

			// The empty-state copy is visible.
			await expect(
				page.getByText('No GPS track for this run')
			).toBeVisible({ timeout: 10_000 });

			// The fake map canvas (MapLibre) is NOT mounted.
			await expect(page.locator('.maplibregl-map')).toHaveCount(0);

			// And the elevation profile section is suppressed too
			// (every-point-is-0 would otherwise read as a flat line).
			await expect(
				page.getByRole('heading', { name: 'Elevation Profile' })
			).toHaveCount(0);

			// Download GPX + Save as route both stay disabled because
			// there's nothing to export.
			await expect(
				page.getByRole('button', { name: 'Download GPX file' })
			).toBeDisabled();
			await expect(
				page.getByRole('button', { name: 'Save this track as a reusable route' })
			).toBeDisabled();
		} finally {
			await deleteRun(planted);
		}
	});

	test('owner tags gear via RunGearChips → chip renders → DB row created → untag removes the row', async ({
		page
	}) => {
		// Closes a coverage gap: every other interactive surface on
		// /runs/[id] (edit, delete, share, photos, kudos, comments,
		// save-as-route, segment efforts, workout review) has an e2e
		// pinned somewhere in tests-e2e/, but gear-tagging had none.
		// Round-trip: plant a run + a piece of gear, open /runs/[id],
		// click "+ Tag gear", check the box, Save, assert the chip
		// renders + the run_gear row landed. Then re-open the picker,
		// uncheck, Save, assert the chip is gone + the row is gone.
		const admin = getAdminClient();
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5000,
			duration_s: 1800,
			source: 'app',
			is_public: false
		});

		const { data: gear, error: gearErr } = await admin
			.from('gear')
			.insert({
				owner_id: USER_A.id,
				kind: 'shoe',
				name: uniqueText('Test Pegasus')
			})
			.select('id, name')
			.single();
		if (gearErr || !gear) throw new Error(`gear plant failed: ${gearErr?.message}`);

		// Strip the auto-tagged seed default so this test starts from
		// a clean "no gear" state and asserts the manual tag flow
		// specifically, not the auto-tag-on-insert flow (which has its
		// own test).
		await admin.from('run_gear').delete().eq('run_id', runId);

		try {
			await page.goto(`/runs/${runId}`);

			// Before tagging: only the "Edit" / "+ Tag gear" affordance
			// is visible. (Label is "+ Tag gear" because we cleared the
			// auto-tagged Pegasus row above.)
			const gearStrip = page.locator('.gear-strip');
			await expect(gearStrip).toBeVisible({ timeout: 10_000 });
			await expect(gearStrip.locator('.gear-chip')).toHaveCount(0);
			const tagBtn = gearStrip.getByRole('button', { name: '+ Tag gear' });
			await expect(tagBtn).toBeVisible();

			// Open the picker modal.
			await tagBtn.click();
			const dialog = page.getByRole('dialog', { name: /Tag gear used on this run/ });
			await expect(dialog).toBeVisible({ timeout: 5_000 });

			// Check our planted gear's box, hit Save.
			await dialog
				.locator('label', { hasText: gear.name })
				.locator('input[type="checkbox"]')
				.check();
			await dialog.getByRole('button', { name: 'Save', exact: true }).click();
			await expect(dialog).toBeHidden({ timeout: 5_000 });

			// Chip now renders with the gear name + a shoe icon (kind='shoe').
			await expect(
				gearStrip.locator('.gear-chip', { hasText: gear.name })
			).toBeVisible({ timeout: 5_000 });

			// Backend: run_gear row exists.
			await expect
				.poll(
					async () => {
						const { data } = await admin
							.from('run_gear')
							.select('gear_id')
							.eq('run_id', runId)
							.eq('gear_id', gear.id)
							.maybeSingle();
						return data?.gear_id ?? null;
					},
					{ timeout: 5_000 }
				)
				.toBe(gear.id);

			// Untag: re-open picker, uncheck, Save.
			await gearStrip.getByRole('button', { name: 'Edit' }).click();
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog
				.locator('label', { hasText: gear.name })
				.locator('input[type="checkbox"]')
				.uncheck();
			await dialog.getByRole('button', { name: 'Save', exact: true }).click();
			await expect(dialog).toBeHidden({ timeout: 5_000 });

			// Chip gone, "+ Tag gear" affordance back.
			await expect(gearStrip.locator('.gear-chip')).toHaveCount(0);
			await expect(
				gearStrip.getByRole('button', { name: '+ Tag gear' })
			).toBeVisible();

			// Backend: run_gear row gone.
			await expect
				.poll(
					async () => {
						const { data } = await admin
							.from('run_gear')
							.select('gear_id')
							.eq('run_id', runId)
							.eq('gear_id', gear.id)
							.maybeSingle();
						return data;
					},
					{ timeout: 5_000 }
				)
				.toBeNull();
		} finally {
			await admin.from('run_gear').delete().eq('run_id', runId);
			await admin.from('gear').delete().eq('id', gear.id);
			await deleteRun(runId);
		}
	});

	test('current gear auto-tags newly-inserted runs — chip appears with no manual tagging', async ({
		page
	}) => {
		// New "is_default" gear concept (migration 20260901_001):
		// marking a piece of gear as the user's current default
		// auto-tags every subsequently-inserted run of the matching
		// activity kind (run/walk/hike → shoe, cycle → bike) via the
		// auto_tag_default_gear trigger on runs.
		//
		// The seed marks the "Pegasus 40" shoe as the current default
		// for USER_A. This test plants a new shoe-eligible run and
		// asserts the chip renders without the user opening the
		// gear picker. A regression in the trigger, the partial-unique
		// index, or the data-layer chip read would fail here.
		const admin = getAdminClient();
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 6000,
			duration_s: 2100,
			source: 'app',
			is_public: false
			// activity_type defaults to 'run' in insertRun's metadata
		});
		try {
			await page.goto(`/runs/${runId}`);

			// Chip is visible with the default shoe's name. NO manual
			// picker interaction was performed.
			const gearStrip = page.locator('.gear-strip');
			await expect(
				gearStrip.locator('.gear-chip', { hasText: 'Pegasus 40' })
			).toBeVisible({ timeout: 10_000 });

			// Backend mirrors it: a run_gear row was created by the trigger.
			const { data } = await admin
				.from('run_gear')
				.select('gear_id, gear:gear_id(name)')
				.eq('run_id', runId);
			expect(data?.length ?? 0).toBe(1);
			expect((data?.[0] as { gear: { name: string } } | undefined)?.gear?.name).toBe(
				'Pegasus 40'
			);
		} finally {
			await admin.from('run_gear').delete().eq('run_id', runId);
			await deleteRun(runId);
		}
	});

	// Linked-cursor: hovering the elevation profile paints a marker
	// on the route map at the corresponding point. Pinned end-to-end
	// because the wiring spans three components (ElevationProfile,
	// /runs/[id] page-level state, RunMap) and any one going silent
	// breaks the affordance for real users without any test failure
	// in the unit-level guards. Plants a run WITH a track + elevation
	// samples (RUNNER_PUBLIC_RUN_ID is metadata-only — no Storage
	// track upload — so the Elevation Profile section is gated off
	// for it).
	test('hovering the elevation profile paints a marker on the route map', async ({
		page,
	}) => {
		// Build a small synthetic track with a real elevation curve so
		// the chart has something to draw + an idx-space wide enough
		// for the hover-at-60% lookup to land on a non-edge point.
		const track: TrackPoint[] = [];
		for (let i = 0; i < 30; i++) {
			track.push({
				lat: 51.5 + i * 0.0005,
				lng: -0.1 + i * 0.0007,
				// Sine-shaped elevation — non-flat so the chart renders a
				// real curve and the hover idx lookup is meaningful.
				ele: 50 + 20 * Math.sin((i / 30) * Math.PI),
			});
		}
		const planted = await insertRun({
			user_id: USER_A.id,
			started_at: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
			duration_s: 1800,
			distance_m: 5000,
			source: 'app',
			is_public: true,
			metadata: { activity_type: 'run', title: 'e2e linked-cursor track' },
			track,
		});
		try {
			await page.goto(`/runs/${planted}`);
			// Wait for both the elevation profile and the map to be live.
			await expect(
				page.getByRole('heading', { name: 'Elevation Profile' }),
			).toBeVisible({ timeout: 15_000 });
			await expect(page.locator('.maplibregl-map')).toBeVisible({
				timeout: 10_000,
			});

			// No hover yet — the marker should be absent.
			await expect(
				page.locator('[data-testid="chart-hover-marker"]'),
			).toHaveCount(0);

			// Find the SVG and pointer-move over the middle of it. The chart's
			// pointer handlers attach via `onpointermove`, so dispatching a
			// real pointer event is what wakes them up.
			const svg = page.locator('.elevation-svg').first();
			await expect(svg).toBeVisible();
			// Scroll into view first — Elevation Profile lives well down
			// the page and Playwright's positional .hover needs the SVG
			// inside the viewport.
			await svg.scrollIntoViewIfNeeded();
			const box = await svg.boundingBox();
			if (!box) throw new Error('elevation svg has no bounding box');

			// Hover ~60 % across — pick a non-edge point so the index is well
			// into the track, not at start/end (which could surface a wrong-
			// position-by-rounding ambiguity).
			await svg.hover({ position: { x: box.width * 0.6, y: box.height / 2 } });

			// The marker should now exist + be positioned by MapLibre (i.e.
			// transformed via the maplibregl-marker class). The pulse
			// animation keeps it visually distinct from the segment pin.
			const marker = page.locator('[data-testid="chart-hover-marker"]');
			await expect(marker).toBeVisible({ timeout: 5_000 });
			// And it must be a child of the map, not a stray DOM node — pin
			// the parent relationship so a refactor that moves it outside
			// the map container fails here.
			const inMap = await marker.evaluate((el) =>
				Boolean(el.closest('.maplibregl-map')),
			);
			expect(inMap).toBe(true);

			// Move the pointer off the chart — the marker should clear.
			// Hover-leave is the contract that makes the cursor feel light;
			// without it the dot stays painted on the map after the user
			// looks away.
			await page.mouse.move(10, 10);
			await expect(marker).toHaveCount(0, { timeout: 5_000 });
		} finally {
			await deleteRun(planted);
		}
	});

	test('not-found: visiting a missing run id shows "Run not found" with a way back', async ({
		page
	}) => {
		// A user clicking a stale email/Slack link to a deleted run
		// shouldn't see a blank shell — they should land on a page that
		// says what happened and gives them a way out. Without this
		// branch the {:else if run} fall-through rendered nothing,
		// which feels broken and is a leave-the-app moment.
		const bogusId = '00000000-0000-0000-0000-000000000bad';
		await page.goto(`/runs/${bogusId}`);

		await expect(
			page.getByRole('heading', { level: 1, name: 'Run not found' })
		).toBeVisible({ timeout: 10_000 });
		await expect(
			page.getByRole('link', { name: 'Back to your runs' })
		).toBeVisible();
	});

	test('share button is in-flight-guarded so a double-tap makes the run public only once', async ({
		page,
		context
	}) => {
		// proceedShare had no busy guard: a fast second tap (or a second
		// tap once the run is already public) fired makeRunPublic again.
		// The button now disables while the flip is in flight. Hold the
		// PATCH open to widen the window and count how many leave.
		const planted = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: false
		});

		let patchCount = 0;
		await page.route('**/rest/v1/runs?id=eq.*', async (route) => {
			if (route.request().method() === 'PATCH') {
				patchCount += 1;
				await new Promise((r) => setTimeout(r, 1200));
			}
			await route.continue();
		});

		try {
			await context.grantPermissions(['clipboard-read', 'clipboard-write']);
			await page.goto(`/runs/${planted}`);

			const shareBtn = page.locator('button[title="Share link"]');
			await expect(shareBtn).toBeVisible({ timeout: 10_000 });
			await shareBtn.click();

			// Confirm the consent dialog — this kicks the held PATCH.
			const dialog = page.locator('[data-testid="share-confirm-dialog"]');
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.locator('button', { hasText: /Make public/ }).click();

			// While the flip is in flight the button is disabled, so a
			// second tap cannot queue a duplicate makeRunPublic.
			await expect(shareBtn).toBeDisabled();

			// Let it settle (the success toast means proceedShare resolved
			// and cleared the busy flag — the button's title then flips to
			// "Copy share link", so re-find it by the share glyph), then
			// assert exactly one PATCH was issued.
			await expect(page.locator('.toast', { hasText: /Share link copied/ }))
				.toBeVisible({ timeout: 10_000 });
			await expect(
				page.locator('button:has(.material-symbols:text-is("share"))')
			).toBeEnabled();
			expect(patchCount).toBe(1);
		} finally {
			await deleteRun(planted);
		}
	});
});

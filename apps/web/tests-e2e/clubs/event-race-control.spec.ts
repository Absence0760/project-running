import { expect, test } from '@playwright/test';

import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /clubs/[slug]/events/[id] — race control admin surface, exercised
 * across two browser contexts.
 *
 * The event page subscribes to postgres_changes on `race_sessions`
 * (filtered by event_id). When a club admin clicks "Arm race" / "GO"
 * / "End race", the DB write fans out to every subscribed member's
 * page — admins see updated controls, non-admins see the "Race
 * armed" / "Race running" banner. Without realtime fan-out members
 * would only learn the race started when they manually refreshed,
 * which defeats the wrist-app handoff (a member's watch is supposed
 * to flip into recording-armed state the moment the organiser fires
 * Arm — that handoff is driven by the same realtime channel).
 *
 * This spec drives the full Arm → GO → End sequence in the admin
 * context (USER_A — Sydney Run Club owner) and asserts that the
 * member context (USER_B — active member) sees each state transition
 * land WITHOUT a page reload. A regression in any link of the chain
 * (the page's realtime channel filter, the race_sessions publication,
 * RLS on race_sessions for non-admin readers, or the page's
 * scheduleReload debounce) would surface as a stale member banner.
 *
 * Per-context auth pattern: instead of `test.use({ storageState })`,
 * which would lock the whole describe to a single auth, each test
 * spins up two contexts via `browser.newContext({ storageState })`
 * so admin + member can co-exist on the same URL within one test.
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/clubs/[slug]/events/[id] — race control (admin + member multi-context)', () => {
	test('Arm → GO → End: state transitions land in both contexts via realtime', async ({
		browser
	}) => {
		const title = `e2e race-control ${Date.now()}`;
		const eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			created_by: USER_A.id,
			title,
			starts_at: new Date(Date.now() + 60 * 60 * 1000).toISOString() // +1h
		});

		const ctxOpts = { locale: 'en-GB', timezoneId: 'UTC' } as const;
		const adminCtx = await browser.newContext({
			...ctxOpts,
			storageState: USER_A.storageStatePath
		});
		const memberCtx = await browser.newContext({
			...ctxOpts,
			storageState: USER_B.storageStatePath
		});

		try {
			const adminPage = await adminCtx.newPage();
			const memberPage = await memberCtx.newPage();

			await Promise.all([
				adminPage.goto(`/clubs/sydney-run-club/events/${eventId}`),
				memberPage.goto(`/clubs/sydney-run-club/events/${eventId}`)
			]);

			// Wait for both to finish their initial load AND for the
			// realtime channel to reach SUBSCRIBED — the page sets
			// data-realtime-ready="true" from the .subscribe() callback.
			// Without this, the admin's Arm click can land before the
			// member's WS handshake completes, the postgres_changes
			// event is dropped, and the banner never appears.
			await Promise.all([
				expect(adminPage.getByRole('heading', { name: title })).toBeVisible({
					timeout: 10_000
				}),
				expect(memberPage.getByRole('heading', { name: title })).toBeVisible({
					timeout: 10_000
				}),
				expect(adminPage.locator('[data-realtime-ready="true"]')).toBeVisible({
					timeout: 10_000
				}),
				expect(memberPage.locator('[data-realtime-ready="true"]')).toBeVisible({
					timeout: 10_000
				})
			]);

			// ── Pre-arm state ────────────────────────────────────────
			// Admin sees the Race control panel + "Arm race" button.
			// Member sees neither the panel NOR the armed/running
			// banner. The .race-banner only appears mid-race, and the
			// .race-panel is admin-only (gated on isRaceDirector).
			await expect(adminPage.locator('.race-panel')).toBeVisible();
			await expect(
				adminPage.getByRole('button', { name: 'Arm race' })
			).toBeVisible();
			await expect(memberPage.locator('.race-panel')).toHaveCount(0);
			await expect(memberPage.locator('.race-banner')).toHaveCount(0);

			// ── Arm ──────────────────────────────────────────────────
			await adminPage.getByRole('button', { name: 'Arm race' }).click();

			// Admin context flips locally: GO button now visible.
			await expect(
				adminPage.getByRole('button', { name: 'GO', exact: true })
			).toBeVisible({ timeout: 10_000 });

			// Member context picks it up via realtime — armed banner
			// appears WITHOUT a reload. The banner copy is the
			// load-bearing pin: a regression in the banner gating
			// (e.g. raceSession.status === 'armed' check inverted)
			// would surface here.
			await expect(memberPage.locator('.race-banner')).toBeVisible({
				timeout: 15_000
			});
			await expect(memberPage.locator('.race-banner')).toContainText(/Race armed/i);

			// ── GO (start race) ──────────────────────────────────────
			await adminPage.getByRole('button', { name: 'GO', exact: true }).click();

			// Admin flips to "End race".
			await expect(
				adminPage.getByRole('button', { name: 'End race' })
			).toBeVisible({ timeout: 10_000 });

			// Member's banner flips from "armed" to "running" via the
			// same realtime channel (an UPDATE event on race_sessions,
			// not a fresh INSERT — the regression vector here is the
			// page's scheduleReload mistakenly only handling INSERTs).
			await expect(memberPage.locator('.race-banner')).toContainText(
				/Race running/i,
				{ timeout: 15_000 }
			);

			// ── End race ─────────────────────────────────────────────
			// "End race" + "Cancel" both open a ConfirmDialog (role
			// "dialog") with its own confirm button. The page-level
			// "End race" button and the dialog's confirm button share
			// the label, so scope the second click to the dialog.
			await adminPage.getByRole('button', { name: 'End race' }).click();
			await adminPage
				.getByRole('dialog')
				.getByRole('button', { name: 'End race' })
				.click();

			// Admin returns to the pre-arm panel — "Arm race" reappears.
			await expect(
				adminPage.getByRole('button', { name: 'Arm race' })
			).toBeVisible({ timeout: 10_000 });

			// Member's banner clears — race-banner element disappears
			// because raceSession.status flips to 'finished', which is
			// neither 'armed' nor 'running'.
			await expect(memberPage.locator('.race-banner')).toHaveCount(0, {
				timeout: 15_000
			});
		} finally {
			await adminCtx.close();
			await memberCtx.close();
			// deleteEvent cascades to race_sessions + race_pings via FK
			// (migration 20260425_001 — `on delete cascade`).
			await deleteEvent(eventId);
		}
	});

	test('Cancel from armed: armed banner clears for member without End-race detour', async ({
		browser
	}) => {
		// The Cancel button on the armed panel is a different path —
		// it writes status='cancelled' directly, bypassing the
		// 'running' state. Pin separately because the member-side
		// banner-clear logic must accept BOTH 'cancelled' and
		// 'finished' as armed-banner-removal signals.
		const title = `e2e race-cancel ${Date.now()}`;
		const eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			created_by: USER_A.id,
			title,
			starts_at: new Date(Date.now() + 60 * 60 * 1000).toISOString()
		});

		const ctxOpts = { locale: 'en-GB', timezoneId: 'UTC' } as const;
		const adminCtx = await browser.newContext({
			...ctxOpts,
			storageState: USER_A.storageStatePath
		});
		const memberCtx = await browser.newContext({
			...ctxOpts,
			storageState: USER_B.storageStatePath
		});

		try {
			const adminPage = await adminCtx.newPage();
			const memberPage = await memberCtx.newPage();

			await Promise.all([
				adminPage.goto(`/clubs/sydney-run-club/events/${eventId}`),
				memberPage.goto(`/clubs/sydney-run-club/events/${eventId}`)
			]);
			// Same data-realtime-ready guard as the Arm → GO → End test
			// above. The member's WS handshake must reach SUBSCRIBED
			// before the admin's Arm click or the postgres_changes event
			// is dropped.
			await Promise.all([
				expect(adminPage.getByRole('heading', { name: title })).toBeVisible({
					timeout: 10_000
				}),
				expect(memberPage.getByRole('heading', { name: title })).toBeVisible({
					timeout: 10_000
				}),
				expect(adminPage.locator('[data-realtime-ready="true"]')).toBeVisible({
					timeout: 10_000
				}),
				expect(memberPage.locator('[data-realtime-ready="true"]')).toBeVisible({
					timeout: 10_000
				})
			]);

			// Arm the race.
			await adminPage.getByRole('button', { name: 'Arm race' }).click();
			await expect(
				adminPage.getByRole('button', { name: 'GO', exact: true })
			).toBeVisible({ timeout: 10_000 });
			await expect(memberPage.locator('.race-banner')).toContainText(
				/Race armed/i,
				{ timeout: 15_000 }
			);

			// Cancel from the armed state. The page's "Cancel" link
			// fires handleEnd('cancelled'), which opens a ConfirmDialog
			// whose confirm button is labelled "Cancel race"
			// (unambiguous on the page).
			await adminPage.getByRole('button', { name: 'Cancel' }).click();
			await adminPage
				.getByRole('dialog')
				.getByRole('button', { name: 'Cancel race' })
				.click();

			// Admin returns to the pre-arm card (with the lingering
			// "Previous race cancelled." muted note above the Arm
			// button — pin the button reappearance, not the copy, since
			// copy is a separate UX concern.
			await expect(
				adminPage.getByRole('button', { name: 'Arm race' })
			).toBeVisible({ timeout: 10_000 });

			// Member's banner clears.
			await expect(memberPage.locator('.race-banner')).toHaveCount(0, {
				timeout: 15_000
			});
		} finally {
			await adminCtx.close();
			await memberCtx.close();
			await deleteEvent(eventId);
		}
	});
});

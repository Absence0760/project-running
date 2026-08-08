import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

/**
 * /clubs/[slug]/events/[id] — a failed session-plan read must not take the
 * event page down.
 *
 * `fetchSessionPlan` rethrows, and `loadSessionPlan()` was awaited from a
 * `load()` with no try/catch that cleared `loading` only on the success path.
 * So on an event with an attached session plan, one failed read left the
 * race-day page on its aria-busy skeletons indefinitely — no RSVP, no roster,
 * no results, nothing said, nothing to retry.
 *
 * The attached plan is auxiliary to the event, so the read now degrades to
 * "no plan" and the rest of the page renders (the L0–L4 layering contract).
 */
test.describe('/clubs/[slug]/events/[id] — session-plan read failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let eventId: string | null = null;
	let planId: string | null = null;

	test.afterEach(async () => {
		const admin = getAdminClient();
		if (eventId) {
			try {
				await deleteEvent(eventId);
			} catch (_) {
				/* best-effort cleanup */
			}
			eventId = null;
		}
		if (planId) {
			try {
				await admin.from('session_plans').delete().eq('id', planId);
			} catch (_) {
				/* best-effort cleanup */
			}
			planId = null;
		}
	});

	test('the event still renders when its attached session plan fails to load', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const title = `e2e-event-plan-failure ${Date.now()}`;

		const { data: plan, error: planErr } = await admin
			.from('session_plans')
			.insert({ author_id: USER_A.id, title: `e2e-plan ${Date.now()}` })
			.select('id')
			.single();
		if (planErr || !plan) throw planErr ?? new Error('session plan insert failed');
		planId = plan.id as string;

		eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'class',
		});
		const { error: attachErr } = await admin
			.from('events')
			.update({ session_plan_id: planId })
			.eq('id', eventId);
		if (attachErr) throw attachErr;

		await page.route('**/rest/v1/session_plans*', (route) =>
			route.fulfill({ status: 500, body: 'boom' })
		);

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);

		// The page resolves onto the real event rather than skeletoning forever.
		await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible({
			timeout: 15_000,
		});
		await expect(page.locator('[aria-busy="true"]')).toHaveCount(0);
	});
});

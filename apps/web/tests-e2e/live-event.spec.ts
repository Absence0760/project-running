import { expect, test } from '@playwright/test';

import { getAdminClient } from './fixtures/local-supabase';
import { insertEvent } from './fixtures/simulate';
import { USER_A } from './fixtures/users';

/**
 * /live/event/[id]/[instance] — live event spectator view.
 *
 * Renders a leaderboard + map of recent race-pings for an event
 * instance. The seed has no race_session row; the page surfaces a
 * "No race session yet for this instance." empty-state card in that
 * case. Pin both the empty-state mount AND a planted-race mount
 * to exercise the fetch + the leaderboard render.
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/live/event/[id]/[instance]', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('mounts an empty-state card when no race_session exists for the instance', async ({
		page
	}) => {
		// Plant an event but not a race_session. The page should mount
		// past the loading shell and render the no-race-session empty
		// state — the realistic path before the organiser arms the
		// race timer.
		const eventId = await insertEvent({
			club_id: SYDNEY_RUN_CLUB_ID,
			created_by: USER_A.id,
			title: `e2e live-event ${Date.now()}`,
			starts_at: new Date(Date.now() + 60 * 60 * 1000).toISOString()
		});
		const instance = encodeURIComponent(
			new Date(Date.now() + 60 * 60 * 1000).toISOString()
		);

		try {
			await page.goto(`/live/event/${eventId}/${instance}`);
			await page.waitForLoadState('networkidle');

			// Pre-race shape: status pill reads "Pre-race" with a
			// sub-message explaining the organiser hasn't armed the
			// timer, and the leaderboard's "On course" section shows
			// the zero-pings empty-inline card. Pin both surfaces so
			// neither regresses silently.
			await expect(
				page.getByText(/Organiser hasn’t armed the race timer/)
			).toBeVisible({ timeout: 10_000 });
			await expect(
				page.getByText(/No live position data yet/)
			).toBeVisible();
		} finally {
			await getAdminClient().from('events').delete().eq('id', eventId);
		}
	});
});

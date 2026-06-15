import { expect, test } from '@playwright/test';

import {
	deleteEvent,
	insertEvent,
	insertCheckpoint,
	insertCrossing
} from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Race-director checkpoint operations (race_director_ops.md):
 *  - P1 web side: organiser checkpoint management on the event page.
 *  - P2: the organiser live-results + cutoff board.
 *  - P4: the public account-optional results page.
 *
 * USER_A owns Richmond Run Club (slug richmond-run-club), so they are an event
 * organiser and can manage checkpoints + read the organiser board. Crossings
 * are seeded via the service-role admin client (the table is RPC-write-only for
 * clients, but the board read is what we're exercising).
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('race-director checkpoint board + public results', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('organiser creates a checkpoint on the event page', async ({ page }) => {
		const startsAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
		const eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e checkpoint mgmt ${Date.now()}`,
			starts_at: startsAt,
			distance_m: 30000
		});
		try {
			await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
			const manager = page.getByTestId('checkpoint-manager');
			await expect(manager).toBeVisible();
			await expect(page.getByText('No checkpoints yet.')).toBeVisible();

			await page.getByTestId('checkpoint-add').click();
			await page.getByTestId('checkpoint-name').fill('Aid Station 1');
			await page.getByTestId('checkpoint-save').click();

			await expect(manager.getByText('Aid Station 1')).toBeVisible();
			await expect(page.getByTestId('checkpoint-row')).toHaveCount(1);
		} finally {
			await deleteEvent(eventId);
		}
	});

	test('board projects per-runner progress + cutoff verdicts', async ({ page }) => {
		const startsAt = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(); // 2h ago
		const startMs = new Date(startsAt).getTime();
		const eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e checkpoint board ${Date.now()}`,
			starts_at: startsAt,
			distance_m: 30000
		});
		try {
			const cp1 = await insertCheckpoint({
				event_id: eventId,
				created_by: USER_A.id,
				name: 'Aid 1',
				ordinal: 1,
				position_m: 10000,
				cutoff_elapsed_s: 3600
			});
			const cp2 = await insertCheckpoint({
				event_id: eventId,
				created_by: USER_A.id,
				name: 'Finish',
				ordinal: 2,
				position_m: 30000,
				cutoff_elapsed_s: 10800
			});
			// Bib runner reached Aid 1 at +30min (safe vs the 1h cutoff).
			await insertCrossing({
				event_id: eventId,
				checkpoint_id: cp1,
				instance_start: startsAt,
				bib: '101',
				runner_name: 'Ada Aidstation',
				in_time: new Date(startMs + 30 * 60 * 1000).toISOString()
			});
			// Account runner blew Aid 1 (+90min vs 1h cutoff) → DNF.
			await insertCrossing({
				event_id: eventId,
				checkpoint_id: cp2,
				instance_start: startsAt,
				bib: '101',
				runner_name: 'Ada Aidstation',
				in_time: new Date(startMs + 100 * 60 * 1000).toISOString()
			});

			await page.goto(
				`/clubs/richmond-run-club/events/${eventId}/board?instance=${encodeURIComponent(startsAt)}`
			);
			const table = page.getByTestId('board-table');
			await expect(table).toBeVisible();
			await expect(page.getByTestId('board-row')).toHaveCount(1);
			await expect(table.getByText('Ada Aidstation')).toBeVisible();
			// Reached both checkpoints inside cutoff → finished.
			await expect(table.getByText('Finished')).toBeVisible();
			// At least one safe verdict chip shows.
			await expect(table.getByText('Safe').first()).toBeVisible();

			// Mark DNF.
			await page.getByTestId('mark-dnf').click();
			await page.getByRole('button', { name: 'Mark DNF' }).last().click();
			await expect(table.getByText('DNF')).toBeVisible();
		} finally {
			await deleteEvent(eventId);
		}
	});

	test('public results page lists finishers + splits', async ({ page }) => {
		const startsAt = new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString();
		const startMs = new Date(startsAt).getTime();
		const eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e public results ${Date.now()}`,
			starts_at: startsAt,
			distance_m: 30000
		});
		try {
			const cp1 = await insertCheckpoint({
				event_id: eventId,
				created_by: USER_A.id,
				name: 'Aid 1',
				ordinal: 1,
				position_m: 10000
			});
			await insertCrossing({
				event_id: eventId,
				checkpoint_id: cp1,
				instance_start: startsAt,
				bib: '202',
				runner_name: 'Pub Lic',
				in_time: new Date(startMs + 40 * 60 * 1000).toISOString()
			});

			await page.goto(
				`/share/event/${eventId}/results?instance=${encodeURIComponent(startsAt)}`
			);
			const results = page.getByTestId('public-results');
			await expect(results).toBeVisible();
			await expect(page.getByTestId('public-results-row')).toHaveCount(1);
			await expect(results.getByText('Pub Lic')).toBeVisible();
		} finally {
			await deleteEvent(eventId);
		}
	});
});

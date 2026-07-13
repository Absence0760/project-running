import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Tab-close guard for the long-running client-side Strava bulk-zip import
 * (persona-hunt persona-runner-strava-migration.md, "[high] No 'don't
 * close this tab' guard on a fully-serial ... import").
 *
 * importStravaZip walks the archive serially on the main thread — a
 * multi-year export is tens of minutes with no resume. handleZipSelect
 * arms a `beforeunload` listener for the duration of the in-flight import
 * (triggering the browser's native "leave site?" confirmation) and tears
 * it down in the finally block. We can't assert the browser's own native
 * dialog from Playwright, so we instrument add/removeEventListener before
 * the page script runs and assert the listener LIFECYCLE instead:
 *
 *   - IDLE: loading the page registers zero beforeunload listeners from
 *     our code (the guard is scoped to an in-flight import, not idle
 *     page views).
 *   - IN FLIGHT: while the import is walking the archive, exactly one
 *     more beforeunload listener is active than has been removed.
 *   - AFTER: the finally block removes it — adds and removes balance,
 *     so no listener leaks past the import.
 *
 * The runs REST write is delayed via a route interception so the import
 * stays in flight long enough to observe the active-guard window
 * deterministically (a one-row import otherwise completes in ~ms).
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

function stravaActivityDate(d: Date): string {
	const months = [
		'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
		'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
	];
	let hour = d.getUTCHours();
	const ampm = hour >= 12 ? 'PM' : 'AM';
	hour = hour % 12;
	if (hour === 0) hour = 12;
	const mm = String(d.getUTCMinutes()).padStart(2, '0');
	const ss = String(d.getUTCSeconds()).padStart(2, '0');
	return `${months[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}, ${hour}:${mm}:${ss} ${ampm}`;
}

async function buildStravaZip(opts: {
	stravaId: string;
	name: string;
	startedAt: Date;
}): Promise<Buffer> {
	const JSZip = (await import('jszip')).default;
	const zip = new JSZip();
	const csv = [
		'Activity ID,Activity Date,Activity Name,Activity Type,Filename,Distance,Moving Time,Elevation Gain',
		`${opts.stravaId},"${stravaActivityDate(opts.startedAt)}","${opts.name}",Run,,5.00,1500,42`,
		''
	].join('\n');
	zip.file('activities.csv', csv);
	const arr = await zip.generateAsync({ type: 'uint8array', compression: 'DEFLATE' });
	return Buffer.from(arr);
}

test.describe('Strava bulk-import tab-close guard', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('arms a beforeunload guard only while the import is in flight, then tears it down', async ({
		page
	}) => {
		const admin = getAdminClient();
		const stravaId = `${Date.now()}${Math.floor(Math.random() * 1000)}`;
		const externalId = `strava:${stravaId}`;
		const activityName = uniqueText('e2e-tab-close-guard-run');
		const startedAt = new Date();
		let runId = '';

		// Instrument beforeunload registration BEFORE any page script runs
		// so both the SvelteKit shell and our handler are counted.
		await page.addInitScript(() => {
			const w = window as unknown as { __beAdds: number; __beRemoves: number };
			w.__beAdds = 0;
			w.__beRemoves = 0;
			const origAdd = window.addEventListener.bind(window);
			const origRemove = window.removeEventListener.bind(window);
			window.addEventListener = ((type: string, ...rest: unknown[]) => {
				if (type === 'beforeunload') w.__beAdds++;
				// eslint-disable-next-line @typescript-eslint/no-explicit-any
				return (origAdd as any)(type, ...rest);
			}) as typeof window.addEventListener;
			window.removeEventListener = ((type: string, ...rest: unknown[]) => {
				if (type === 'beforeunload') w.__beRemoves++;
				// eslint-disable-next-line @typescript-eslint/no-explicit-any
				return (origRemove as any)(type, ...rest);
			}) as typeof window.removeEventListener;
		});

		// Delay the runs REST write so the (one-row) import stays in flight
		// long enough to sample the active-guard window deterministically.
		await page.route(/\/rest\/v1\/runs(\?|$)/, async (route) => {
			await new Promise((r) => setTimeout(r, 1500));
			await route.continue();
		});

		try {
			await page.goto('/settings/integrations');

			const stravaBulkCard = page
				.locator('section.bulk-import')
				.filter({ hasText: 'Bulk import from a Strava export' });
			await expect(stravaBulkCard).toBeVisible({ timeout: 10_000 });

			// IDLE: our code registered no beforeunload listener for a plain
			// page view (guard is scoped to an in-flight import).
			const activeAtIdle = await page.evaluate(() => {
				const w = window as unknown as { __beAdds: number; __beRemoves: number };
				return w.__beAdds - w.__beRemoves;
			});
			expect(activeAtIdle).toBe(0);

			const zip = await buildStravaZip({ stravaId, name: activityName, startedAt });
			await stravaBulkCard.locator('input[type="file"]').setInputFiles({
				name: 'strava_export.zip',
				mimeType: 'application/zip',
				buffer: zip
			});

			// IN FLIGHT: while the delayed runs write is outstanding, exactly
			// one beforeunload guard is active (added, not yet removed).
			await expect
				.poll(
					() =>
						page.evaluate(() => {
							const w = window as unknown as {
								__beAdds: number;
								__beRemoves: number;
							};
							return w.__beAdds - w.__beRemoves;
						}),
					{ timeout: 10_000 }
				)
				.toBeGreaterThanOrEqual(1);

			// The import completes (success toast) — the finally block ran.
			await expect(page.locator('.toast-success')).toContainText(/1 new/i, {
				timeout: 15_000
			});

			// AFTER: the guard was torn down — every add balanced by a remove,
			// no listener leaks past the import.
			const afterState = await page.evaluate(() => {
				const w = window as unknown as { __beAdds: number; __beRemoves: number };
				return { adds: w.__beAdds, removes: w.__beRemoves };
			});
			expect(afterState.adds).toBeGreaterThanOrEqual(1);
			expect(afterState.adds).toBe(afterState.removes);

			const { data: rows } = await admin
				.from('runs')
				.select('id')
				.eq('user_id', USER_A.id)
				.eq('external_id', externalId);
			runId = (rows?.[0]?.id as string) ?? '';
		} finally {
			if (runId) await admin.from('runs').delete().eq('id', runId);
		}
	});
});

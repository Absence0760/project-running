import { expect, test } from '@playwright/test';

import { createClient } from '@supabase/supabase-js';

import { getAdminClient, getUserClient, loadSupabaseEnv } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Storage RLS boundaries — the layer the runs / public_runs table
 * tests don't reach.
 *
 * The `runs` bucket holds gzipped GPS tracks at `{user_id}/{run_id}.json.gz`.
 * Public-share viewers go through `clip-public-track` (which downloads
 * via service-role and clips); a direct curl-from-devtools attack on
 * the Storage URL must be denied by `storage.objects` RLS so an anon
 * user can't read the unclipped track. Same shape for cross-user:
 * alex with a real JWT must not be able to download runner's track
 * by asking Storage directly.
 *
 * Defence-in-depth: even if the row's RLS softened, the Storage
 * policy is the second line. The pgtap suite covers the SQL contract;
 * these tests pin the on-the-wire behaviour through the exact same
 * supabase-js client real callers use.
 */

test.describe('Storage RLS — runs bucket', () => {
	test('anon cannot download a private run\'s track via the runs bucket directly', async () => {
		// Plant a private run with a track payload via service-role —
		// owner client would also work but service-role is faster.
		const admin = getAdminClient();
		const planted = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: false,
			track: [
				{ lat: -33.89, lng: 151.27, ele: 10, t: '2026-04-01T08:00:00Z' },
				{ lat: -33.89, lng: 151.28, ele: 11, t: '2026-04-01T08:01:00Z' }
			]
		});

		try {
			// Confirm via service-role that the Storage object exists at
			// the canonical path.
			const trackPath = `${USER_A.id}/${planted}.json.gz`;
			const { data: list } = await admin.storage
				.from('runs')
				.list(USER_A.id, { search: planted });
			const matched = list?.find((f) => f.name.startsWith(planted));
			expect(matched).toBeDefined();

			// Anon attempt — fresh client with the anon key only.
			const { url, anonKey } = loadSupabaseEnv();
			const anon = createClient(url, anonKey, {
				auth: { persistSession: false }
			});
			const { data: dl, error } = await anon.storage
				.from('runs')
				.download(trackPath);

			// Either the SDK surfaces an error, OR the download returns
			// an empty/error blob. Pin the negative — anon must NOT
			// receive the track bytes.
			if (error) {
				expect(error.message.toLowerCase()).toMatch(/not.*authorized|denied|not found|403|401/);
			} else {
				// supabase-js sometimes returns an empty Blob with no
				// error on RLS denial; treat any non-empty body as a
				// real leak.
				const buf = dl ? new Uint8Array(await dl.arrayBuffer()) : new Uint8Array();
				expect(buf.length, 'anon must not receive track bytes').toBeLessThan(1);
			}
		} finally {
			await deleteRun(planted);
		}
	});

	test('Authed cross-user cannot download another user\'s track via the runs bucket', async () => {
		// Planted run owned by runner. Alex signs in with a real JWT
		// and tries to download runner's track. The Storage RLS on
		// the `runs` bucket scopes select to
		// `(storage.foldername(name))[1] = auth.uid()::text` — alex's
		// uid != runner's, so the read must fail.
		const planted = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: false,
			track: [
				{ lat: -33.89, lng: 151.27, ele: 10, t: '2026-04-01T08:00:00Z' }
			]
		});

		try {
			const alex = await getUserClient({
				email: USER_B.email,
				password: USER_B.password
			});
			const { data: dl, error } = await alex.storage
				.from('runs')
				.download(`${USER_A.id}/${planted}.json.gz`);

			if (error) {
				expect(error.message.toLowerCase()).toMatch(/not.*authorized|denied|not found|403|401/);
			} else {
				const buf = dl ? new Uint8Array(await dl.arrayBuffer()) : new Uint8Array();
				expect(buf.length, 'cross-user must not receive track bytes').toBeLessThan(1);
			}
		} finally {
			await deleteRun(planted);
		}
	});

	test('Authed user cannot upload to another user\'s runs/{user_id}/ prefix', async () => {
		// The Storage INSERT policy scopes the path's first folder to
		// auth.uid(). Alex trying to upload into runner's prefix must
		// be rejected.
		const alex = await getUserClient({
			email: USER_B.email,
			password: USER_B.password
		});
		const targetPath = `${USER_A.id}/e2e-cross-user-upload.json.gz`;
		const fakeBytes = new Blob([new Uint8Array([0x1f, 0x8b, 0x08])], {
			type: 'application/gzip'
		});

		const { error } = await alex.storage
			.from('runs')
			.upload(targetPath, fakeBytes, { upsert: false });

		expect(error).not.toBeNull();
		// Sanity: the object must not exist now.
		const admin = getAdminClient();
		const { data: list } = await admin.storage
			.from('runs')
			.list(USER_A.id, { search: 'e2e-cross-user-upload' });
		const found = list?.find((f) =>
			f.name.includes('e2e-cross-user-upload')
		);
		expect(found).toBeUndefined();
	});
});

import { expect, test } from '@playwright/test';

import { createClient } from '@supabase/supabase-js';

import { getAdminClient, loadSupabaseEnv } from '../fixtures/local-supabase';
import { USER_C_PRO } from '../fixtures/users';

/**
 * Invite-token redemption security — the `join_club_by_token` RPC
 * (migration 20260417_001) is the only path into a private club for a
 * non-owner, so its failure modes matter:
 *
 *   1. A garbage / non-matching token fails CLOSED: it raises "invalid
 *      invite token" and plants NO membership row anywhere. (A regression
 *      that inserted before validating, or that fell through to a
 *      best-match, would leak access.)
 *   2. A valid token grants membership to EXACTLY its owning club — not a
 *      sibling club. The token is matched by equality against
 *      clubs.invite_token, so redeeming Friends-of-Jared's token must put
 *      morgan in Friends of Jared and leave Tempo Tuesday untouched.
 *   3. An anonymous caller can't redeem at all (execute revoked + the
 *      function raises on a null auth.uid()).
 *
 * invite-rotation.spec.ts covers the rotate-invalidates-old contract;
 * this file covers the cross-club + malformed-token + anon surface.
 */

const FRIENDS_OF_JARED_ID = 'c3333333-0000-0000-0000-000000000003';
const FRIENDS_OF_JARED_TOKEN = 'c3fr13nd50fj4r3dc1ubtoken000000';
const TEMPO_TUESDAY_ID = 'c2222222-0000-0000-0000-000000000002';

async function sweepMorgan(clubId: string): Promise<void> {
	try {
		await getAdminClient()
			.from('club_members')
			.delete()
			.eq('club_id', clubId)
			.eq('user_id', USER_C_PRO.id);
	} catch (_) {
		/* best-effort */
	}
}

function userClient() {
	const { url, anonKey } = loadSupabaseEnv();
	return createClient(url, anonKey, {
		auth: { persistSession: false, autoRefreshToken: false }
	});
}

test.describe('invite-token redemption — failure + cross-club isolation', () => {
	test.afterEach(async () => {
		await sweepMorgan(FRIENDS_OF_JARED_ID);
		await sweepMorgan(TEMPO_TUESDAY_ID);
	});

	test('a garbage token raises "invalid invite token" and plants no membership row', async () => {
		const client = userClient();
		const { error: signInErr } = await client.auth.signInWithPassword({
			email: USER_C_PRO.email,
			password: USER_C_PRO.password
		});
		expect(signInErr).toBeNull();

		const { data, error } = await client.rpc('join_club_by_token', {
			token: 'totally-not-a-real-token-zzzzzzzz'
		});
		expect(data).toBeNull();
		expect(error).not.toBeNull();
		expect(error?.message ?? '').toMatch(/invalid invite token/i);

		// No membership row was created on ANY club for morgan from the
		// failed redemption.
		const admin = getAdminClient();
		const { count } = await admin
			.from('club_members')
			.select('user_id', { count: 'exact', head: true })
			.eq('user_id', USER_C_PRO.id)
			.in('club_id', [FRIENDS_OF_JARED_ID, TEMPO_TUESDAY_ID]);
		expect(count).toBe(0);
	});

	test("Friends-of-Jared's token grants membership to that club only, not a sibling", async () => {
		const client = userClient();
		await client.auth.signInWithPassword({
			email: USER_C_PRO.email,
			password: USER_C_PRO.password
		});

		const { data: joinedClub, error } = await client.rpc('join_club_by_token', {
			token: FRIENDS_OF_JARED_TOKEN
		});
		expect(error).toBeNull();
		// The RPC returns the owning club id — it must be Friends of Jared.
		expect(joinedClub).toBe(FRIENDS_OF_JARED_ID);

		const admin = getAdminClient();
		const { data: fojRow } = await admin
			.from('club_members')
			.select('status')
			.eq('club_id', FRIENDS_OF_JARED_ID)
			.eq('user_id', USER_C_PRO.id)
			.maybeSingle();
		expect(fojRow?.status).toBe('active');

		// Crucially: no membership leaked into the OTHER club.
		const { data: tempoRow } = await admin
			.from('club_members')
			.select('user_id')
			.eq('club_id', TEMPO_TUESDAY_ID)
			.eq('user_id', USER_C_PRO.id)
			.maybeSingle();
		expect(tempoRow).toBeNull();
	});

	test('an anonymous caller cannot redeem a valid token', async () => {
		// Execute is revoked from anon, and the function raises on a null
		// auth.uid() — either way no membership lands.
		const anon = userClient();
		const { error } = await anon.rpc('join_club_by_token', {
			token: FRIENDS_OF_JARED_TOKEN
		});
		expect(error).not.toBeNull();

		// Belt-and-braces: confirm via service-role that no anon-attributed
		// row was created (auth.uid() is null, so nothing could insert).
		const admin = getAdminClient();
		const { count } = await admin
			.from('club_members')
			.select('user_id', { count: 'exact', head: true })
			.eq('club_id', FRIENDS_OF_JARED_ID)
			.eq('user_id', USER_C_PRO.id);
		expect(count).toBe(0);
	});
});

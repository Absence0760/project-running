import { expect, test } from '@playwright/test';

import { getAdminClient, loadSupabaseEnv } from '../fixtures/local-supabase';
import { createClient } from '@supabase/supabase-js';

/**
 * Wire-format pin for migration 20260801_001_clubs_invite_token_lockdown.sql.
 *
 * Pre-fix: an anon caller could `select=invite_token` from the `clubs`
 * table on every public club and use the token via `join_club_by_token`
 * to defeat `join_policy = 'invite'`. The lockdown migration revokes
 * table-level SELECT for anon + authenticated, then re-grants every
 * column except `invite_token`. Admin reads now go through the
 * `get_club_invite_token` SECURITY DEFINER RPC gated on
 * `is_club_admin`.
 *
 * pgtap (`rls_clubs_invite_token_lockdown_test.sql`) covers the SQL
 * shape; this spec pins the PostgREST wire format so a future
 * column-level grant change can't silently re-expose the token.
 */

const FRIENDS_OF_JARED_ID = 'c3333333-0000-0000-0000-000000000003';

test.describe('clubs.invite_token wire-format lockdown', () => {
	test('anon GET /rest/v1/clubs?select=invite_token returns 4xx (column-level grant revoked)', async () => {
		const { url, anonKey } = loadSupabaseEnv();
		const anon = createClient(url, anonKey, {
			auth: { persistSession: false, autoRefreshToken: false }
		});

		const { data, error } = await anon
			.from('clubs')
			.select('invite_token')
			.eq('is_public', true)
			.limit(5);

		// Column-level revoke should surface as a PostgREST 4xx
		// (translated 42501 / "permission denied"). The data must NOT
		// include any token strings.
		expect(error, 'anon select(invite_token) must be rejected').not.toBeNull();
		expect(data ?? []).toEqual([]);
	});

	test('anon GET /rest/v1/clubs?select=name,slug still returns rows (safe-column re-grant works)', async () => {
		const { url, anonKey } = loadSupabaseEnv();
		const anon = createClient(url, anonKey, {
			auth: { persistSession: false, autoRefreshToken: false }
		});

		const { data, error } = await anon
			.from('clubs')
			.select('id, name, slug')
			.eq('is_public', true)
			.limit(5);

		expect(error).toBeNull();
		expect(Array.isArray(data)).toBe(true);
		expect((data ?? []).length).toBeGreaterThan(0);
	});

	test('anon RPC get_club_invite_token returns NULL — the RPC fails closed when auth.uid() is null', async () => {
		const { url, anonKey } = loadSupabaseEnv();
		const anon = createClient(url, anonKey, {
			auth: { persistSession: false, autoRefreshToken: false }
		});

		const { data } = await anon.rpc('get_club_invite_token', {
			target_club: FRIENDS_OF_JARED_ID
		});

		// The function is SECURITY DEFINER with an `is_club_admin`
		// gate. For anon, `auth.uid() is null`, the gate is false, and
		// the case-when returns null — never the actual token.
		expect(data).toBeNull();
	});

	test('admin client (service role) confirms the row still has its invite_token (data is intact, only the wire is locked)', async () => {
		// Sanity check: the lockdown is a wire-format change, not a
		// column delete. Service role bypasses the column-level grant
		// and confirms the column still holds a value — so admin reads
		// via `get_club_invite_token` have something to return.
		const admin = getAdminClient();
		const { data, error } = await admin
			.from('clubs')
			.select('invite_token')
			.eq('id', FRIENDS_OF_JARED_ID)
			.maybeSingle();

		expect(error).toBeNull();
		expect(data?.invite_token).toBeTruthy();
	});
});

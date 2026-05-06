import { execSync } from 'node:child_process';
import { resolve } from 'node:path';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

/**
 * Shared helper for talking to the local Supabase stack from inside
 * Playwright fixtures. Two callers today:
 *   - saga-users.ts — admin-creates ephemeral users + inserts profiles.
 *   - simulate.ts — service-role helpers for actions only mobile/watch
 *     can do on the canonical web surface.
 *
 * The service-role key is fetched once via `supabase status -o env`
 * (cached for the test process). Local dev + CI both have the local
 * stack running, so this always resolves.
 */

type LocalEnv = { url: string; serviceKey: string; anonKey: string };
let envCache: LocalEnv | null = null;

export function loadSupabaseEnv(): LocalEnv {
	if (envCache) return envCache;

	// `supabase` looks for config.toml in cwd. apps/backend is two
	// levels up from tests-e2e/fixtures.
	const backendDir = resolve(import.meta.dirname, '..', '..', '..', 'backend');

	let out: string;
	try {
		out = execSync('supabase status -o env', { cwd: backendDir }).toString();
	} catch (e) {
		throw new Error(
			`saga fixtures: 'supabase status -o env' failed in ${backendDir}. ` +
				`Is the local Supabase stack running? (cd apps/backend && supabase start)`
		);
	}

	const url = out.match(/^API_URL="([^"]+)"/m)?.[1];
	const serviceKey = out.match(/^SERVICE_ROLE_KEY="([^"]+)"/m)?.[1];
	const anonKey = out.match(/^ANON_KEY="([^"]+)"/m)?.[1];
	if (!url || !serviceKey || !anonKey) {
		throw new Error(
			'saga fixtures: could not parse API_URL / SERVICE_ROLE_KEY / ANON_KEY ' +
				'from `supabase status -o env`. The output format may have changed.'
		);
	}

	envCache = { url, serviceKey, anonKey };
	return envCache;
}

let adminClient: SupabaseClient | null = null;

/**
 * A supabase-js client authenticated with the SERVICE ROLE key.
 * Bypasses RLS — use it for fixture setup + teardown only, never
 * for the assertions a test is meant to make. Cached for the
 * process so we don't reconstruct it per fixture call.
 */
export function getAdminClient(): SupabaseClient {
	if (adminClient) return adminClient;
	const { url, serviceKey } = loadSupabaseEnv();
	adminClient = createClient(url, serviceKey, {
		auth: { persistSession: false, autoRefreshToken: false }
	});
	return adminClient;
}

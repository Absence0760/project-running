/// Single source of truth for the public share-profile fetch shape.
/// Used by both:
///   - apps/web/src/routes/share/profile/[id]/+page.ts (dev-server SSR).
///   - the production entity-SSR Lambda that owns /share/profile/*.
///
/// Reads through the `public_profile_by_id` SECURITY DEFINER RPC (migration
/// 20261011_001), which is the ONLY anon-granted projection of user_profiles
/// — it returns the display-safe columns (id, display_name, avatar_url) and
/// nothing else. No private profile fields, settings, or location ever reach
/// this surface.

import { createClient } from '@supabase/supabase-js';

export interface SharedProfile {
	id: string;
	display_name: string | null;
	avatar_url: string | null;
}

export interface SharedProfileLookup {
	profile: SharedProfile | null;
}

export interface SharedProfileLookupConfig {
	supabaseUrl: string;
	supabaseAnonKey: string;
}

/// Fetch a public profile by user id. Returns `{ profile: null }` when
/// config is missing, the profile doesn't exist, or the RPC throws
/// (logged, not surfaced — the share page renders a branded shell).
export async function lookupSharedProfile(
	id: string,
	config: SharedProfileLookupConfig | null,
): Promise<SharedProfileLookup> {
	if (!config?.supabaseUrl || !config?.supabaseAnonKey) {
		return { profile: null };
	}
	try {
		const supabase = createClient(config.supabaseUrl, config.supabaseAnonKey, {
			auth: { persistSession: false },
		});
		const { data, error } = await supabase
			.rpc('public_profile_by_id', { p_id: id })
			.maybeSingle();
		if (error) {
			console.error('[share-profile] upstream_unreachable');
			return { profile: null };
		}
		if (!data) return { profile: null };
		const p = data as { id?: string; display_name?: string | null; avatar_url?: string | null };
		return {
			profile: {
				id: p.id ?? id,
				display_name: p.display_name ?? null,
				avatar_url: p.avatar_url ?? null,
			},
		};
	} catch (err) {
		console.error(
			'[share-profile] upstream_unreachable',
			err instanceof Error ? err.message : String(err),
		);
		return { profile: null };
	}
}

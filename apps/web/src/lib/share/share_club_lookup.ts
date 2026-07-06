/// Single source of truth for the public share-club fetch shape.
/// Used by both:
///   - apps/web/src/routes/share/club/[slug]/+page.ts (dev-server SSR).
///   - the production entity-SSR Lambda that owns /share/club/*.
///
/// A club is anon-readable only when `is_public = true` (clubs RLS), so
/// the anon-key query returns nothing for a private club and the caller
/// degrades to the branded fallback. Selects only display-safe columns.
/// Keyed by `slug` — the same identifier the in-app /clubs/[slug] URL
/// uses — so the share link mirrors the canonical club URL.

import { createClient } from '@supabase/supabase-js';

export interface SharedClub {
	id: string;
	slug: string;
	name: string;
	description: string | null;
	avatar_url: string | null;
	location_label: string | null;
}

export interface SharedClubLookup {
	club: SharedClub | null;
}

export interface SharedClubLookupConfig {
	supabaseUrl: string;
	supabaseAnonKey: string;
}

/// Fetch a public club by slug. Returns `{ club: null }` when config is
/// missing, the club doesn't exist / isn't public (anon RLS returns
/// nothing), or the fetch throws (logged, not surfaced).
export async function lookupSharedClub(
	slug: string,
	config: SharedClubLookupConfig | null,
): Promise<SharedClubLookup> {
	if (!config?.supabaseUrl || !config?.supabaseAnonKey) {
		return { club: null };
	}
	try {
		const supabase = createClient(config.supabaseUrl, config.supabaseAnonKey, {
			auth: { persistSession: false },
		});
		const { data: club, error } = await supabase
			.from('clubs')
			.select('id, slug, name, description, avatar_url, location_label, is_public')
			.eq('slug', slug)
			.maybeSingle();
		if (error) {
			console.error('[share-club] upstream_unreachable');
			return { club: null };
		}
		if (!club) return { club: null };
		const c = club as Record<string, unknown>;
		// Defence-in-depth: RLS already blocks a private club for anon.
		if (c.is_public === false) return { club: null };
		return {
			club: {
				id: c.id as string,
				slug: c.slug as string,
				name: (c.name as string) ?? '',
				description: (c.description as string | null) ?? null,
				avatar_url: (c.avatar_url as string | null) ?? null,
				location_label: (c.location_label as string | null) ?? null,
			},
		};
	} catch (err) {
		console.error(
			'[share-club] upstream_unreachable',
			err instanceof Error ? err.message : String(err),
		);
		return { club: null };
	}
}

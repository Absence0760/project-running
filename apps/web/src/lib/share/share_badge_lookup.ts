/// Single source of truth for the share-badge + og-image fetch shape.
/// Used by both:
///   - apps/web/src/routes/share/badge/[id]/+page.ts (dev-server SSR).
///   - apps/web/lambda/share-badge/src/index.ts (production Lambda that
///     owns /share/badge/* and /og/badge/*.png).
///
/// Public-row column discipline: a badge share is anonymous + public, so the
/// query selects only the milestone-safe columns and filters on is_public =
/// true. It never reads a private badge or any private location/track data —
/// a badge exposes a numeric milestone + a date, nothing else.

import { createClient } from '@supabase/supabase-js';
import { TABLES } from '../core/schema';

export interface SharedBadge {
	id: string;
	user_id: string | null;
	badge_key: string;
	tier: string;
	value_num: number | null;
	earned_at: string | null;
}

export interface SharedBadgeLookup {
	badge: SharedBadge | null;
	displayName: string | null;
}

export interface SharedBadgeLookupConfig {
	supabaseUrl: string;
	supabaseAnonKey: string;
}

/// Fetch a public badge + the owner's display name. Returns
/// `{ badge: null, displayName: null }` when config is missing, the badge
/// doesn't exist / isn't public, or the fetch throws (logged, not surfaced).
export async function lookupSharedBadge(
	id: string,
	config: SharedBadgeLookupConfig | null,
): Promise<SharedBadgeLookup> {
	if (!config?.supabaseUrl || !config?.supabaseAnonKey) {
		return { badge: null, displayName: null };
	}
	try {
		const supabase = createClient(config.supabaseUrl, config.supabaseAnonKey, {
			auth: { persistSession: false },
		});
		const { data: badge, error } = await supabase
			.from(TABLES.achievements)
			.select('id, user_id, badge_key, tier, value_num, earned_at')
			.eq('id', id)
			.eq('is_public', true)
			.maybeSingle();
		// Non-null error (vs a clean data:null not-found) = Supabase unreachable
		// / 5xx; the badge card degrades to the branded fallback with no Lambda
		// Errors metric. Tagged line drives the share-badge-upstream-unreachable
		// alarm. /audit/infra N2.
		if (error) {
			console.error('[share-badge] upstream_unreachable');
			return { badge: null, displayName: null };
		}
		if (!badge) return { badge: null, displayName: null };
		let displayName: string | null = null;
		if (badge.user_id) {
			const { data: profile } = await supabase
				.rpc('public_profile_by_id', { p_id: badge.user_id })
				.maybeSingle();
			displayName = (profile as { display_name?: string | null } | null)?.display_name ?? null;
		}
		return { badge: badge as SharedBadge, displayName };
	} catch (err) {
		console.error(
			'[share-badge] upstream_unreachable',
			err instanceof Error ? err.message : String(err),
		);
		return { badge: null, displayName: null };
	}
}

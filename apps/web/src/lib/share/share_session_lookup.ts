/// Single source of truth for the share-session-plan fetch shape, mirroring
/// `share_workout_lookup.ts`. Used by
///   - apps/web/src/routes/share/session/[id]/+page.ts (dev-server SSR +
///     SPA hydration).
///
/// A public session plan is readable by anyone (the "public session plans are
/// readable" RLS policy gates non-owner/anon reads on `is_public`, and the
/// blocks/items inherit-visibility policies expose the children when the parent
/// is public), so the share page works logged-out. Only the non-sensitive plan
/// fields + the blocks/items needed to render the read-only sequence are
/// fetched — a session plan carries no author fitness data, so nothing private
/// leaks past what the owner chose to make public.

import { createClient } from '@supabase/supabase-js';
import type { SessionItemKind } from '$lib/social/session_steps';

export interface SharedSessionBlock {
	id: string;
	position: number;
	name: string | null;
}

export interface SharedSessionItem {
	id: string;
	block_id: string | null;
	position: number;
	movement_name: string;
	kind: SessionItemKind;
	duration_s: number | null;
	reps: number | null;
	per_side: boolean;
	tempo: string | null;
	cue: string | null;
}

export interface SharedSession {
	id: string;
	author_id: string | null;
	title: string | null;
	discipline: string | null;
	equipment: string | null;
	est_duration_min: number | null;
	blocks: SharedSessionBlock[];
	items: SharedSessionItem[];
}

export interface SharedSessionLookup {
	session: SharedSession | null;
	displayName: string | null;
}

export interface SharedSessionLookupConfig {
	supabaseUrl: string;
	supabaseAnonKey: string;
}

/// Fetch a public session plan + the author's display name. Returns
/// `{ session: null, displayName: null }` when config is missing, the
/// plan doesn't exist or isn't public, or the fetch throws.
export async function lookupSharedSession(
	id: string,
	config: SharedSessionLookupConfig | null,
): Promise<SharedSessionLookup> {
	if (!config?.supabaseUrl || !config?.supabaseAnonKey) {
		return { session: null, displayName: null };
	}
	try {
		const supabase = createClient(config.supabaseUrl, config.supabaseAnonKey, {
			auth: { persistSession: false },
		});
		// `is_public = true` is enforced by RLS, but filter explicitly too so a
		// non-public id resolves to "not found" rather than relying on RLS to
		// blank the row.
		const { data: plan } = await supabase
			.from('session_plans')
			.select('id, author_id, title, discipline, equipment, est_duration_min, is_public')
			.eq('id', id)
			.eq('is_public', true)
			.maybeSingle();
		if (!plan) return { session: null, displayName: null };

		const [{ data: blocks }, { data: items }] = await Promise.all([
			supabase
				.from('session_plan_blocks')
				.select('id, position, name')
				.eq('plan_id', id)
				.order('position', { ascending: true }),
			supabase
				.from('session_plan_items')
				.select(
					'id, block_id, position, movement_name, kind, duration_s, reps, per_side, tempo, cue',
				)
				.eq('plan_id', id)
				.order('position', { ascending: true }),
		]);

		let displayName: string | null = null;
		if (plan.author_id) {
			const { data: profile } = await supabase
				.rpc('public_profile_by_id', { p_id: plan.author_id })
				.maybeSingle();
			displayName =
				(profile as { display_name?: string | null } | null)?.display_name ?? null;
		}
		return {
			session: {
				id: plan.id,
				author_id: plan.author_id,
				title: plan.title,
				discipline: plan.discipline,
				equipment: plan.equipment,
				est_duration_min: plan.est_duration_min,
				blocks: (blocks ?? []) as SharedSessionBlock[],
				items: (items ?? []) as SharedSessionItem[],
			},
			displayName,
		};
	} catch (err) {
		console.warn('lookupSharedSession: fetch failed', err);
		return { session: null, displayName: null };
	}
}

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

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { SessionItemKind } from '$lib/social/session_steps';
import { isEntityId } from '../core/entity_id';

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
	makeClient: (url: string, key: string) => SupabaseClient = (url, key) =>
		createClient(url, key, { auth: { persistSession: false } }),
): Promise<SharedSessionLookup> {
	if (!config?.supabaseUrl || !config?.supabaseAnonKey) {
		return { session: null, displayName: null };
	}
	// A non-uuid segment raises 22P02 on the uuid column, which PostgREST
	// returns as an error — indistinguishable at this layer from Supabase
	// being down, so reject it before querying and keep the tagged line below
	// meaning "outage" only.
	if (!isEntityId(id)) return { session: null, displayName: null };
	try {
		const supabase = makeClient(config.supabaseUrl, config.supabaseAnonKey);
		// `is_public = true` is enforced by RLS, but filter explicitly too so a
		// non-public id resolves to "not found" rather than relying on RLS to
		// blank the row.
		const { data: plan, error } = await supabase
			.from('session_plans')
			.select('id, author_id, title, discipline, equipment, est_duration_min, is_public')
			.eq('id', id)
			.eq('is_public', true)
			.maybeSingle();
		// Non-null error (vs a clean data:null not-found) = Supabase unreachable
		// / 5xx; the page degrades to the branded 404 with no Lambda Errors
		// metric. Tagged line drives the share-session-upstream-unreachable alarm.
		if (error) {
			console.error('[share-session] upstream_unreachable');
			return { session: null, displayName: null };
		}
		if (!plan) return { session: null, displayName: null };

		const [{ data: blocks, error: blocksError }, { data: items, error: itemsError }] =
			await Promise.all([
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
		// A hollow page — the plan's title with an empty sequence — is worse than
		// the branded 404, and it is what an unchecked child-query error renders.
		if (blocksError || itemsError) {
			console.error('[share-session] upstream_unreachable');
			return { session: null, displayName: null };
		}

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
		console.error(
			'[share-session] upstream_unreachable',
			err instanceof Error ? err.message : String(err),
		);
		return { session: null, displayName: null };
	}
}

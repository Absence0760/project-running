/// Single source of truth for the share-workout fetch shape, mirroring
/// `share_run_lookup.ts`. Used by
///   - apps/web/src/routes/share/workout/[id]/+page.ts (dev-server SSR +
///     SPA hydration).
///
/// A public gym workout is readable by anyone via the redacted
/// `public_gym_workouts` / `public_gym_sets` views (the base tables are
/// owner-only since migration 20270313_001 dropped their public-read RLS
/// branches — an anon base-table read matches zero rows and rendered every
/// share page as "Workout not found", CI run 28707481878), so the share page
/// works logged-out. Only the headline columns + the sets needed to render
/// the read-only detail are fetched — no notes / RPE leak beyond what the
/// owner already chose to make public.

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { isEntityId } from '../core/entity_id';

export interface SharedWorkoutSet {
	set_index: number;
	exercise_name: string;
	reps: number | null;
	weight_kg: number | null;
	duration_s: number | null;
}

export interface SharedWorkout {
	id: string;
	user_id: string | null;
	title: string | null;
	started_at: string | null;
	set_count: number | null;
	volume_kg: number | null;
	sets: SharedWorkoutSet[];
}

export interface SharedWorkoutLookup {
	workout: SharedWorkout | null;
	displayName: string | null;
}

export interface SharedWorkoutLookupConfig {
	supabaseUrl: string;
	supabaseAnonKey: string;
}

/// Fetch a public workout + the owner's display name. Returns
/// `{ workout: null, displayName: null }` when config is missing, the
/// workout doesn't exist or isn't public, or the fetch throws.
export async function lookupSharedWorkout(
	id: string,
	config: SharedWorkoutLookupConfig | null,
	makeClient: (url: string, key: string) => SupabaseClient = (url, key) =>
		createClient(url, key, { auth: { persistSession: false } }),
): Promise<SharedWorkoutLookup> {
	if (!config?.supabaseUrl || !config?.supabaseAnonKey) {
		return { workout: null, displayName: null };
	}
	// A non-uuid segment raises 22P02 on the uuid column, which PostgREST
	// returns as an error — indistinguishable at this layer from Supabase
	// being down, so reject it before querying and keep the tagged line below
	// meaning "outage" only.
	if (!isEntityId(id)) return { workout: null, displayName: null };
	try {
		const supabase = makeClient(config.supabaseUrl, config.supabaseAnonKey);
		// `is_public = true` is baked into the views, but filter explicitly too
		// so a non-public id resolves to "not found" rather than relying on the
		// view to blank the row.
		const { data: workout, error } = await supabase
			.from('public_gym_workouts')
			.select('id, user_id, title, started_at, set_count, volume_kg, is_public')
			.eq('id', id)
			.eq('is_public', true)
			.maybeSingle();
		// Non-null error (vs a clean data:null not-found) = Supabase unreachable
		// / 5xx; the page degrades to the branded 404 with no Lambda Errors
		// metric. Tagged line drives the share-workout-upstream-unreachable alarm.
		if (error) {
			console.error('[share-workout] upstream_unreachable');
			return { workout: null, displayName: null };
		}
		if (!workout) return { workout: null, displayName: null };

		const { data: sets, error: setsError } = await supabase
			.from('public_gym_sets')
			.select('set_index, exercise_name, reps, weight_kg, duration_s')
			.eq('workout_id', id)
			.order('set_index', { ascending: true });
		// A hollow page — the workout's title with no sets — is worse than the
		// branded 404, and it is what an unchecked child-query error renders.
		if (setsError) {
			console.error('[share-workout] upstream_unreachable');
			return { workout: null, displayName: null };
		}

		let displayName: string | null = null;
		if (workout.user_id) {
			const { data: profile } = await supabase
				.rpc('public_profile_by_id', { p_id: workout.user_id })
				.maybeSingle();
			displayName =
				(profile as { display_name?: string | null } | null)?.display_name ?? null;
		}
		return {
			workout: {
				id: workout.id,
				user_id: workout.user_id,
				title: workout.title,
				started_at: workout.started_at,
				set_count: workout.set_count,
				volume_kg: workout.volume_kg,
				sets: (sets ?? []) as SharedWorkoutSet[],
			},
			displayName,
		};
	} catch (err) {
		console.error(
			'[share-workout] upstream_unreachable',
			err instanceof Error ? err.message : String(err),
		);
		return { workout: null, displayName: null };
	}
}

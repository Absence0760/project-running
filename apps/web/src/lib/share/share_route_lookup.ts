/// Single source of truth for the share-route + og-image fetch shape.
/// Used by both:
///   - apps/web/src/routes/share/route/[id]/+page.ts (dev-server SSR
///     of the per-route <head>).
///   - apps/web/lambda/share-route/src/index.ts (production Lambda
///     that owns /share/route/* and /og/route/*.png — see
///     apps/web/lambda/share-route/README.md).
///
/// Mirror of share_run_lookup.ts. Returns a tagged shape so the
/// missing-vs-present route case stays explicit at the call site
/// without forcing a try/catch on every consumer.
///
/// The track is fetched through the `clip_track_for_user` SECURITY
/// DEFINER RPC (the same path fetchPublicRoute uses for non-owner
/// viewers) so privacy zones are applied server-side — a runner's
/// home / work coordinate never leaks into a public unfurl image.
/// `withTrack: false` skips that RPC for the HTML path, which only
/// needs the route's name + distance for the <head> meta.

import { createClient } from '@supabase/supabase-js';

import type { TrackPoint } from '../types';

export interface SharedRoute {
	id: string;
	name: string | null;
	distance_m: number | null;
	surface: string | null;
	elevation_m: number | null;
}

export interface SharedRouteLookup {
	route: SharedRoute | null;
	track: TrackPoint[];
}

export interface SharedRouteLookupConfig {
	supabaseUrl: string;
	supabaseAnonKey: string;
}

export interface SharedRouteLookupOptions {
	/// Fetch the privacy-clipped track polyline (for the og:image PNG).
	/// Defaults true. Pass false on the HTML path — the <head> tags
	/// only need the route meta, so the extra clip RPC is wasted work.
	withTrack?: boolean;
}

/// Fetch a public route's meta (+ optionally its privacy-clipped
/// track). Returns `{ route: null, track: [] }` when:
///   - config is missing (caller is expected to short-circuit before
///     calling, but defence-in-depth);
///   - the route doesn't exist or isn't public;
///   - the Supabase fetch throws (logged, not surfaced).
export async function lookupSharedRoute(
	id: string,
	config: SharedRouteLookupConfig | null,
	options: SharedRouteLookupOptions = {},
): Promise<SharedRouteLookup> {
	if (!config?.supabaseUrl || !config?.supabaseAnonKey) {
		return { route: null, track: [] };
	}
	const withTrack = options.withTrack ?? true;
	try {
		const supabase = createClient(config.supabaseUrl, config.supabaseAnonKey, {
			auth: { persistSession: false },
		});
		const { data: route } = await supabase
			.from('public_routes')
			.select('id, name, distance_m, surface, elevation_m')
			.eq('id', id)
			.maybeSingle();
		if (!route) return { route: null, track: [] };
		let track: TrackPoint[] = [];
		if (withTrack) {
			try {
				// The route may not be loadable for anon (private + clip
				// RPC denies). The PNG card still renders title-only.
				const { data: clipped } = await supabase.rpc('clip_track_for_user', {
					p_route_id: id,
				});
				if (Array.isArray(clipped)) {
					track = (clipped as unknown[]).map((p) => p as TrackPoint);
				}
			} catch {
				/* clip denied — degenerate to a title-only card */
			}
		}
		return { route: route as SharedRoute, track };
	} catch (err) {
		console.warn('lookupSharedRoute: fetch failed', err);
		return { route: null, track: [] };
	}
}

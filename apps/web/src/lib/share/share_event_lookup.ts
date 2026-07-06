/// Single source of truth for the public share-event fetch shape.
/// Used by both:
///   - apps/web/src/routes/share/event/[id]/+page.ts (dev-server SSR).
///   - the production entity-SSR Lambda that owns /share/event/*.
///
/// Public-row discipline: an event is anon-readable only when its club is
/// public (events RLS inherits `clubs.is_public`), so the anon-key query
/// returns nothing for a private club's event and the caller degrades to
/// the branded fallback. The query selects only display-safe columns and
/// deliberately OMITS the precise meet point (meet_lat/meet_lng): the
/// event meet coordinate is privacy-sensitive (the discovery layer revoked
/// it — decisions §147), so structured data + unfurls use the CLUB's coarse
/// location_label instead, never the exact meet point.

import { createClient } from '@supabase/supabase-js';

export interface SharedEvent {
	id: string;
	club_id: string;
	title: string;
	description: string | null;
	starts_at: string;
	duration_min: number | null;
	distance_m: number | null;
	category: string | null;
	discipline: string | null;
	/// The event's host club — name + coarse location for the unfurl +
	/// JSON-LD organizer/location.
	club_name: string | null;
	club_slug: string | null;
	club_location: string | null;
}

export interface SharedEventLookup {
	event: SharedEvent | null;
}

export interface SharedEventLookupConfig {
	supabaseUrl: string;
	supabaseAnonKey: string;
}

/// Fetch a public event + its club's name/slug/location. Returns
/// `{ event: null }` when config is missing, the event doesn't exist or
/// belongs to a non-public club (anon RLS returns nothing), or the fetch
/// throws (logged, not surfaced — the share page renders a branded shell).
export async function lookupSharedEvent(
	id: string,
	config: SharedEventLookupConfig | null,
): Promise<SharedEventLookup> {
	if (!config?.supabaseUrl || !config?.supabaseAnonKey) {
		return { event: null };
	}
	try {
		const supabase = createClient(config.supabaseUrl, config.supabaseAnonKey, {
			auth: { persistSession: false },
		});
		const { data: event, error } = await supabase
			.from('events')
			.select(
				'id, club_id, title, description, starts_at, duration_min, distance_m, category, discipline, clubs(name, slug, location_label, is_public)',
			)
			.eq('id', id)
			.maybeSingle();
		// Non-null error (vs a clean data:null not-found) = Supabase
		// unreachable / 5xx; degrade to the branded fallback. Tagged line
		// drives the entity-SSR-upstream-unreachable alarm.
		if (error) {
			console.error('[share-event] upstream_unreachable');
			return { event: null };
		}
		if (!event) return { event: null };
		// Defence-in-depth: RLS already blocks a private club's event for
		// anon, but never surface one even if the embed shape shifts.
		const club = (event as { clubs?: { name?: string; slug?: string; location_label?: string; is_public?: boolean } | null }).clubs ?? null;
		if (club && club.is_public === false) return { event: null };
		const e = event as Record<string, unknown>;
		return {
			event: {
				id: e.id as string,
				club_id: e.club_id as string,
				title: (e.title as string) ?? '',
				description: (e.description as string | null) ?? null,
				starts_at: e.starts_at as string,
				duration_min: (e.duration_min as number | null) ?? null,
				distance_m: (e.distance_m as number | null) ?? null,
				category: (e.category as string | null) ?? null,
				discipline: (e.discipline as string | null) ?? null,
				club_name: club?.name ?? null,
				club_slug: club?.slug ?? null,
				club_location: club?.location_label ?? null,
			},
		};
	} catch (err) {
		console.error(
			'[share-event] upstream_unreachable',
			err instanceof Error ? err.message : String(err),
		);
		return { event: null };
	}
}

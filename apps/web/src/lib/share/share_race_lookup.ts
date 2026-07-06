/// Single source of truth for the public share-race fetch shape.
/// Used by both:
///   - apps/web/src/routes/share/race/[id]/+page.ts (dev-server SSR).
///   - the production entity-SSR Lambda that owns /share/race/*.
///
/// The race calendar is public discovery data — race_listings is
/// anon-readable by RLS (migration 20270214_001). Selects only the
/// display-safe columns and deliberately omits `submitted_by` (redacted
/// per 20270320_001) and the precise `location_point` geometry — only the
/// coarse `location_label` is surfaced.

import { createClient } from '@supabase/supabase-js';

export interface SharedRace {
	id: string;
	name: string;
	race_date: string;
	distance_m: number | null;
	location_label: string | null;
	entry_url: string | null;
	is_verified: boolean;
}

export interface SharedRaceLookup {
	race: SharedRace | null;
}

export interface SharedRaceLookupConfig {
	supabaseUrl: string;
	supabaseAnonKey: string;
}

export async function lookupSharedRace(
	id: string,
	config: SharedRaceLookupConfig | null,
): Promise<SharedRaceLookup> {
	if (!config?.supabaseUrl || !config?.supabaseAnonKey) {
		return { race: null };
	}
	try {
		const supabase = createClient(config.supabaseUrl, config.supabaseAnonKey, {
			auth: { persistSession: false },
		});
		const { data: race, error } = await supabase
			.from('race_listings')
			.select('id, name, race_date, distance_m, location_label, entry_url, is_verified')
			.eq('id', id)
			.maybeSingle();
		if (error) {
			console.error('[share-race] upstream_unreachable');
			return { race: null };
		}
		if (!race) return { race: null };
		const r = race as Record<string, unknown>;
		return {
			race: {
				id: r.id as string,
				name: (r.name as string) ?? '',
				race_date: r.race_date as string,
				distance_m: (r.distance_m as number | null) ?? null,
				location_label: (r.location_label as string | null) ?? null,
				entry_url: (r.entry_url as string | null) ?? null,
				is_verified: Boolean(r.is_verified),
			},
		};
	} catch (err) {
		console.error(
			'[share-race] upstream_unreachable',
			err instanceof Error ? err.message : String(err),
		);
		return { race: null };
	}
}

/// Single source of truth for the public-recap share + og-image fetch shape.
/// Used by both:
///   - apps/web/src/routes/recap/share/[id]/+page.ts (dev-server SSR + SPA
///     hydration)
///   - apps/web/lambda/share-recap/src/index.ts (production Lambda that owns
///     /recap/share/* and /og/recap/*.png).
///
/// The recap snapshot is anon-readable by id via the public_recap_by_id RPC
/// (the uuid is the capability token; the bare public_recaps table is not
/// enumerable — migration 20270305_001). Returns a tagged shape so
/// the missing-vs-present case is explicit at the call site without a
/// try/catch on every consumer. Only aggregate, non-track numbers are read.

import { createClient } from '@supabase/supabase-js';
import { recapPeriodLabel } from './recap_period_label';

export { recapPeriodLabel };

export interface SharedRecapSnapshot {
	year?: number | null;
	month?: number | null;
	totalDistanceM?: number | null;
	runCount?: number | null;
	longestRunM?: number | null;
	bestStreakDays?: number | null;
	totalElevationM?: number | null;
	topWeek?: { distanceM?: number | null } | null;
	[k: string]: unknown;
}

export interface SharedRecap {
	id: string;
	periodKind: 'year' | 'month';
	periodKey: string;
	snapshot: SharedRecapSnapshot;
	displayName: string | null;
}

export interface SharedRecapLookup {
	recap: SharedRecap | null;
}

export interface SharedRecapLookupConfig {
	supabaseUrl: string;
	supabaseAnonKey: string;
}

export async function lookupSharedRecap(
	id: string,
	config: SharedRecapLookupConfig | null,
): Promise<SharedRecapLookup> {
	if (!config?.supabaseUrl || !config?.supabaseAnonKey) {
		return { recap: null };
	}
	try {
		const supabase = createClient(config.supabaseUrl, config.supabaseAnonKey, {
			auth: { persistSession: false },
		});
		const { data, error } = await supabase
			.rpc('public_recap_by_id', { p_id: id })
			.maybeSingle();
		// Non-null error (vs a clean data:null not-found) = Supabase unreachable
		// / 5xx; the recap card degrades to the branded fallback with no Lambda
		// Errors metric. Tagged line drives the share-recap-upstream-unreachable
		// alarm. /audit/infra N2.
		if (error) {
			console.error('[share-recap] upstream_unreachable');
			return { recap: null };
		}
		const row = data as {
			id: string;
			user_id: string | null;
			period_kind: 'year' | 'month';
			period_key: string;
			snapshot: SharedRecapSnapshot | null;
		} | null;
		if (!row) return { recap: null };
		let displayName: string | null = null;
		if (row.user_id) {
			const { data: profile } = await supabase
				.rpc('public_profile_by_id', { p_id: row.user_id })
				.maybeSingle();
			displayName =
				(profile as { display_name?: string | null } | null)?.display_name ?? null;
		}
		return {
			recap: {
				id: row.id,
				periodKind: row.period_kind,
				periodKey: row.period_key,
				snapshot: (row.snapshot ?? {}) as SharedRecapSnapshot,
				displayName,
			},
		};
	} catch (err) {
		console.error(
			'[share-recap] upstream_unreachable',
			err instanceof Error ? err.message : String(err),
		);
		return { recap: null };
	}
}

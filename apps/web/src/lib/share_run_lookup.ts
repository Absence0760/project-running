/// Single source of truth for the share-run + og-image fetch shape.
/// Used by both:
///   - apps/web/src/routes/share/run/[id]/+page.ts (dev-server SSR
///     + the eventual SPA hydration once the Lambda has streamed
///     the per-request HTML).
///   - apps/web/lambda/share-run/src/index.ts (production Lambda
///     that owns /share/run/* and /og/run/*.png — see
///     apps/web/lambda/share-run/README.md).
///
/// Returning a tagged shape (`SharedRunLookup`) instead of just the
/// row keeps the missing-vs-error vs absent-display-name cases
/// explicit at the call site without forcing a try/catch on every
/// consumer.

import { createClient } from '@supabase/supabase-js';

export interface SharedRun {
	id: string;
	user_id: string | null;
	distance_m: number | null;
	duration_s: number | null;
	started_at: string | null;
	source: string | null;
}

export interface SharedRunLookup {
	run: SharedRun | null;
	displayName: string | null;
}

export interface SharedRunLookupConfig {
	supabaseUrl: string;
	supabaseAnonKey: string;
}

/// Fetch a public run + the owner's display name. Returns
/// `{ run: null, displayName: null }` when:
///   - config is missing (caller is expected to short-circuit before
///     calling, but defence-in-depth);
///   - the run doesn't exist or isn't public;
///   - the Supabase fetch throws (logged, not surfaced — the share
///     page renders an empty-state shell either way).
export async function lookupSharedRun(
	id: string,
	config: SharedRunLookupConfig | null,
): Promise<SharedRunLookup> {
	if (!config?.supabaseUrl || !config?.supabaseAnonKey) {
		return { run: null, displayName: null };
	}
	try {
		const supabase = createClient(config.supabaseUrl, config.supabaseAnonKey, {
			auth: { persistSession: false },
		});
		const { data: run } = await supabase
			.from('public_runs')
			.select('id, user_id, distance_m, duration_s, started_at, source')
			.eq('id', id)
			.maybeSingle();
		if (!run) return { run: null, displayName: null };
		let displayName: string | null = null;
		if (run.user_id) {
			const { data: profile } = await supabase
				.from('public_profiles')
				.select('display_name')
				.eq('id', run.user_id)
				.maybeSingle();
			displayName = profile?.display_name ?? null;
		}
		return { run: run as SharedRun, displayName };
	} catch (err) {
		console.warn('lookupSharedRun: fetch failed', err);
		return { run: null, displayName: null };
	}
}

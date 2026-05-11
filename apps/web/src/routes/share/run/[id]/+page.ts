import type { EntryGenerator, PageLoad } from './$types';
import { createClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';

// Build-time prerender — adapter-static bakes one HTML file per
// public run so crawlers (Slack, FB, Twitter, LinkedIn, etc.) read
// a per-run og:title + og:description rather than the SPA-shell
// fallback they were getting before. SvelteKit calls `entries()`
// during the build to discover which ids to prerender; `load()`
// then runs once per id to populate `data`.
//
// Why we can't enrich with display_name yet: `user_profiles` is
// owner-only by RLS (`auth.uid() = id` policy). Anon reads return
// empty, so a build-time fetch with the anon key wouldn't see the
// runner's name. Adding a `public_profiles` view + grant to anon
// would unlock that — deferred per `docs/followups.md § #15`.
export const prerender = true;

// Cap defensive — sitemap caps at 10k; 5k prerendered share pages
// is plenty for v1 and keeps the build size sane.
const MAX_RUNS = 5_000;

export const entries: EntryGenerator = async () => {
	if (!PUBLIC_SUPABASE_URL || !PUBLIC_SUPABASE_ANON_KEY) return [];
	try {
		const supabase = createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
			auth: { persistSession: false },
		});
		const { data, error } = await supabase
			.from('public_runs')
			.select('id')
			.order('started_at', { ascending: false })
			.limit(MAX_RUNS);
		if (error) {
			console.warn('share/run prerender entries: public_runs fetch failed', error);
			return [];
		}
		return (data ?? []).map((r) => ({ id: r.id }));
	} catch (err) {
		console.warn('share/run prerender entries: supabase boot failed', err);
		return [];
	}
};

export const load: PageLoad = async ({ params }) => {
	// Use a fresh native-fetch-backed supabase client at prerender time.
	// Don't pass SvelteKit's wrapped `fetch`: it rewrites
	// cross-origin requests during prerender and supabase-js's
	// internal call to PUBLIC_SUPABASE_URL ends up looped back to
	// the SvelteKit dev server (returns null body) instead of hitting
	// the real Supabase instance.
	if (!PUBLIC_SUPABASE_URL || !PUBLIC_SUPABASE_ANON_KEY) {
		return { id: params.id, run: null, displayName: null };
	}
	try {
		const supabase = createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
			auth: { persistSession: false },
		});
		const { data: run } = await supabase
			.from('public_runs')
			.select('id, user_id, distance_m, duration_s, started_at, source')
			.eq('id', params.id)
			.maybeSingle();
		// Second hop: pull the runner's display name from
		// public_profiles (anon-readable per migration
		// 20260824_001) so the og:title can attribute the run.
		// Done as a separate query rather than a PostgREST embed
		// because public_runs and public_profiles are views, not
		// tables, and embeds across views are gated on FK metadata
		// that views don't carry.
		let displayName: string | null = null;
		if (run?.user_id) {
			const { data: profile } = await supabase
				.from('public_profiles')
				.select('display_name')
				.eq('id', run.user_id)
				.maybeSingle();
			displayName = profile?.display_name ?? null;
		}
		return { id: params.id, run: run ?? null, displayName };
	} catch (err) {
		console.warn('share/run load: fetch failed', err);
		return { id: params.id, run: null, displayName: null };
	}
};

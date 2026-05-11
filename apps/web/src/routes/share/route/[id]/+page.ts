import type { EntryGenerator, PageLoad } from './$types';
import { createClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';

// Build-time prerender for public routes — mirror of the
// share/run/[id] shape. `entries()` lists every public route id
// from the `public_routes` view; `load()` does a thin name + meta
// fetch so the <title> + og tags bake into the prerendered HTML.
//
// Body rendering still goes through `fetchRouteById` in +page.svelte
// onMount — that path is owner-aware (full polyline for owners /
// club members, server-clipped waypoints for anon / non-owner via
// the `clip-public-track` Edge Function). Lifting that into load()
// would push the auth-context fetch into prerender, which neither
// makes sense (no auth at build time) nor would be correct (owner-
// only polyline would never reach a viewer that's actually the
// owner). Keep the two paths separate: minimal meta for head,
// full owner-aware body for the page itself.
export const prerender = true;

const MAX_ROUTES = 5_000;

export const entries: EntryGenerator = async () => {
	if (!PUBLIC_SUPABASE_URL || !PUBLIC_SUPABASE_ANON_KEY) return [];
	try {
		const supabase = createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
			auth: { persistSession: false },
		});
		const { data, error } = await supabase
			.from('public_routes')
			.select('id')
			.order('updated_at', { ascending: false })
			.limit(MAX_ROUTES);
		if (error) {
			console.warn('share/route prerender entries: public_routes fetch failed', error);
			return [];
		}
		return (data ?? []).map((r) => ({ id: r.id }));
	} catch (err) {
		console.warn('share/route prerender entries: supabase boot failed', err);
		return [];
	}
};

export const load: PageLoad = async ({ params }) => {
	// Native fetch (not SvelteKit's wrapped fetch) — see the parallel
	// note in share/run/[id]/+page.ts: wrapping rewrites cross-origin
	// requests during prerender and the supabase call loops back to
	// the SvelteKit dev server.
	if (!PUBLIC_SUPABASE_URL || !PUBLIC_SUPABASE_ANON_KEY) {
		return { id: params.id, route: null };
	}
	try {
		const supabase = createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
			auth: { persistSession: false },
		});
		const { data } = await supabase
			.from('public_routes')
			.select('id, name, distance_m, surface, elevation_m')
			.eq('id', params.id)
			.maybeSingle();
		return { id: params.id, route: data ?? null };
	} catch (err) {
		console.warn('share/route load: fetch failed', err);
		return { id: params.id, route: null };
	}
};

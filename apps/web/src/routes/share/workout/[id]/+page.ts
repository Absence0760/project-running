import type { PageLoad } from './$types';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { lookupSharedWorkout } from '$lib/share/share_workout_lookup';

// `prerender = false` opts out of the module-level `prerender: { default:
// true }` so adapter-static doesn't bake per-id HTML at build time — a
// workout can flip public/private after the build. This PageLoad runs under
// the SvelteKit dev server so /share/workout/[id] works locally; the
// public lift workout is fetched directly (RLS gates the read on is_public,
// so anon / logged-out viewers see only public workouts).
export const prerender = false;

export const load: PageLoad = async ({ params }) => {
	const lookup = await lookupSharedWorkout(
		params.id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	return { id: params.id, workout: lookup.workout, displayName: lookup.displayName };
};

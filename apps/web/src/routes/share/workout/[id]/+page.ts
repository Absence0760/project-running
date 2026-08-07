import type { PageLoad } from './$types';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { env } from '$env/dynamic/public';
import { lookupSharedWorkout } from '$lib/share/share_workout_lookup';
import { DEFAULT_SITE_URL } from '$lib/core/site_url';

// Per-request SSR via the production entity-SSR Lambda — CloudFront routes
// /share/workout/* to the Lambda Function URL, which bakes the per-workout
// <title> + Open Graph + canonical + JSON-LD into the response HTML before a
// crawler or chat-app unfurler (neither runs the SPA's JS) can see it.
//
// `prerender = false` opts out of the module-level `prerender: { default:
// true }` so adapter-static doesn't bake per-id HTML at build time — a
// workout can flip public/private after the build. This PageLoad still runs
// under the SvelteKit dev server so /share/workout/[id] works locally without
// the Lambda; the public lift workout is fetched through the redacted
// public_gym_workouts / public_gym_sets views, so anon / logged-out viewers
// see only public workouts and never the owner's notes / RPE.
export const prerender = false;


export const load: PageLoad = async ({ params }) => {
	const lookup = await lookupSharedWorkout(
		params.id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	const siteUrl = env.PUBLIC_SITE_URL || DEFAULT_SITE_URL;
	return {
		id: params.id,
		workout: lookup.workout,
		displayName: lookup.displayName,
		siteUrl,
	};
};

import type { PageLoad } from './$types';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { env } from '$env/dynamic/public';
import { lookupSharedRoute } from '$lib/share/share_route_lookup';

// Canonical host for the absolute <link rel="canonical"> + og:url +
// JSON-LD URLs. Same source + fallback as /sitemap.xml so the host
// stays consistent across the indexable surface (preview vs prod set
// PUBLIC_SITE_URL; local falls through to the prod host).
const DEFAULT_SITE_URL = 'https://threkir.com';

// Per-request SSR via apps/web/lambda/share-route in production —
// CloudFront routes /share/route/* to the Lambda Function URL, which
// fetches the route meta and bakes the per-route <title> + Open Graph
// + canonical + JSON-LD into the response HTML before crawlers can see
// it. This PageLoad still runs under the SvelteKit dev server so
// /share/route/[id] works locally without standing up the Lambda.
//
// `prerender = false` opts out of the module-level
// `prerender: { default: true }` so adapter-static doesn't bake per-id
// HTML files at build time — those staled the moment a route flipped
// public/private after the build, or went unbuilt past the 5k cap. The
// Lambda owns this path in prod.
//
// Body rendering still goes through `fetchRouteById` in +page.svelte
// onMount — that path is owner-aware (full polyline for owners / club
// members, server-clipped waypoints for anon / non-owner). Only the
// minimal meta needed for the <head> is fetched here; `withTrack:
// false` skips the clip RPC since the head doesn't render the polyline.
export const prerender = false;

export const load: PageLoad = async ({ params }) => {
	const siteUrl = env.PUBLIC_SITE_URL || DEFAULT_SITE_URL;
	const lookup = await lookupSharedRoute(
		params.id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
		{ withTrack: false },
	);
	return { id: params.id, route: lookup.route, siteUrl };
};

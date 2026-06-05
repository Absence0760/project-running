import type { RequestHandler } from './$types';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { renderRouteOgPng } from '$lib/share/og_route_png';

// Per-route og:image PNG renderer. Served at REQUEST time, never
// prerendered: under adapter-static a prerendered route only exists
// for ids known at build time, so a route made public after the last
// build (or beyond the 5k cap) would 404 and its social unfurl would
// show a broken image. In prod CloudFront routes /og/route/* to the
// share-route Lambda (which calls the same renderRouteOgPng helper);
// this endpoint owns the path under the SvelteKit dev server.
//
// Track polyline comes from the `clip_track_for_user` SECURITY DEFINER
// RPC (inside renderRouteOgPng → lookupSharedRoute) so privacy zones
// are applied server-side — a runner's home / work coordinate never
// leaks into a public unfurl image.
export const prerender = false;

export const GET: RequestHandler = async ({ params }) => {
	// renderRouteOgPng falls back to a generic branded card when the
	// route can't be loaded (private / deleted / never existed), so a
	// missing route yields a 200 image, never a 404 — an unfurl must
	// never break.
	const png = await renderRouteOgPng(
		params.id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	return new Response(new Uint8Array(png), {
		headers: {
			'content-type': 'image/png',
			// 5-min cache to match the share-route Lambda's TTL — a flip
			// from public to private must propagate to the og:image
			// unfurl within minutes.
			'cache-control': 'public, max-age=300, s-maxage=300, stale-while-revalidate=60',
		},
	});
};

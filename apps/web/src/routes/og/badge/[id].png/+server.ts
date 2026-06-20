import type { RequestHandler } from './$types';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { renderBadgeOgPng } from '$lib/share/og_badge_png';

// Per-badge og:image PNG renderer, served at REQUEST time, never prerendered.
// In prod CloudFront routes /og/badge/* to the share-badge Lambda (same
// renderBadgeOgPng helper); this endpoint owns the path under the dev server.
export const prerender = false;

export const GET: RequestHandler = async ({ params }) => {
	// renderBadgeOgPng falls back to a generic branded card when the badge
	// can't be loaded (private / deleted / never existed), so a missing badge
	// yields a 200 image, never a 404 — an unfurl must never break.
	const png = await renderBadgeOgPng(
		params.id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	return new Response(new Uint8Array(png), {
		headers: {
			'content-type': 'image/png',
			// 5-min cache so a public→private flip propagates to the unfurl
			// within minutes (matches the share-run Lambda TTL).
			'cache-control': 'public, max-age=300, s-maxage=300, stale-while-revalidate=60',
		},
	});
};

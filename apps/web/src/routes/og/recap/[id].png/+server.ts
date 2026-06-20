import type { RequestHandler } from './$types';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { renderRecapOgPng } from '$lib/share/og_recap_png';

// Per-recap og:image PNG renderer. Served at REQUEST time, never
// prerendered (a recap published after the last build wouldn't exist as a
// static file → broken unfurl). In prod CloudFront routes /og/recap/* to the
// share-recap Lambda (same renderRecapOgPng helper); this endpoint owns the
// path under the SvelteKit dev server. Mirrors /og/run/[id].png.
export const prerender = false;

export const GET: RequestHandler = async ({ params }) => {
	// renderRecapOgPng falls back to a generic branded card when the recap
	// can't be loaded (never published / revoked / never existed), so a missing
	// recap yields a 200 image, never a 404 — an unfurl must never break.
	const png = await renderRecapOgPng(
		params.id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	return new Response(new Uint8Array(png), {
		headers: {
			'content-type': 'image/png',
			// 5-min cache so a revoke (delete the public_recaps row) propagates to
			// the unfurl within minutes, matching /og/run.
			'cache-control': 'public, max-age=300, s-maxage=300, stale-while-revalidate=60',
		},
	});
};

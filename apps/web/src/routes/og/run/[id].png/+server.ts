import type { RequestHandler } from './$types';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { renderRunOgPng } from '$lib/share/og_run_png';

// Per-run og:image PNG renderer. Served at REQUEST time, never
// prerendered: under adapter-static a prerendered route only exists
// for ids known at build time, so a run created after the last build
// would 404 and its social unfurl would show a broken image. In prod
// CloudFront routes /og/run/* to the share-run Lambda (which calls the
// same renderRunOgPng helper); this endpoint owns the path under the
// SvelteKit dev server. Persona-hunt round-5 finding very-social
// (image 404) + Casual #4 (the HTML head).
export const prerender = false;

export const GET: RequestHandler = async ({ params }) => {
	// renderRunOgPng falls back to a generic branded card when the run
	// can't be loaded (private / deleted / never existed), so a missing
	// run yields a 200 image, never a 404 — an unfurl must never break.
	const png = await renderRunOgPng(
		params.id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	return new Response(new Uint8Array(png), {
		headers: {
			'content-type': 'image/png',
			// 5-min cache to match the share-run Lambda's TTL. Persona-
			// hunt Round 3 finding Privacy #3 — a flip from public to
			// private must propagate to the og:image unfurl within
			// minutes, not the previous hour.
			'cache-control': 'public, max-age=300, s-maxage=300, stale-while-revalidate=60',
		},
	});
};

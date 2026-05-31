import type { EntryGenerator, RequestHandler } from './$types';
import { createClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { Resvg } from '@resvg/resvg-js';
import { buildRunOgSvg } from '$lib/share/og_run_image';
import { lookupSharedRun } from '$lib/share/share_run_lookup';

// Per-run og:image PNG renderer. Prerendered at build time — the
// share-run Lambda owns the HTML head injection at request time
// (apps/web/lambda/share-run/) but the PNG renderer stays at build
// time because @resvg ships a native arm64 binary that would need a
// Lambda Layer or platform-specific install to run in the Lambda
// runtime. Out-of-scope cost for the persona-hunt fix; the realistic
// degradation for a brand-new (over-cap) run is og:image 404 → text-
// only unfurl, while title + description still come from the
// Lambda. Persona-hunt finding Casual #4.
export const prerender = true;

const MAX_RUNS = 50_000;

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
			console.warn('og/run prerender entries: public_runs fetch failed', error);
			return [];
		}
		return (data ?? []).map((r) => ({ id: r.id }));
	} catch (err) {
		console.warn('og/run prerender entries: supabase boot failed', err);
		return [];
	}
};
//
// The card is stats-only (distance + runner attribution + date)
// rather than including the polyline — the run track is a gzipped
// JSON blob in the `runs` Storage bucket reachable only via the
// `clip-public-track` Edge Function (decisions §33), too hot a loop
// for build-time + uncached request-time renders.

export const GET: RequestHandler = async ({ params }) => {
	const png = await renderRunPng(params.id);
	return new Response(new Uint8Array(png), {
		headers: {
			'content-type': 'image/png',
			// 5-min cache to match the share-run Lambda's HTML TTL.
			// Persona-hunt Round 3 finding Privacy #3 — a flip from
			// public to private must propagate to the og:image unfurl
			// within minutes, not the previous hour. The PNG is
			// adapter-static-prerendered at build time so this header
			// is written into the static file's Cache-Control;
			// CloudFront honours it for the on-edge cache.
			'cache-control': 'public, max-age=300, s-maxage=300, stale-while-revalidate=60',
		},
	});
};

async function renderRunPng(id: string): Promise<Buffer> {
	const lookup = await lookupSharedRun(
		id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	const svg = buildRunOgSvg({
		distance_m: lookup.run?.distance_m,
		duration_s: lookup.run?.duration_s,
		started_at: lookup.run?.started_at,
		source: lookup.run?.source,
		displayName: lookup.displayName,
	});
	const resvg = new Resvg(svg, {
		fitTo: { mode: 'width', value: 1200 },
		font: { loadSystemFonts: true },
	});
	return resvg.render().asPng();
}

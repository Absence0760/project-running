import type { EntryGenerator, RequestHandler } from './$types';
import { createClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { Resvg } from '@resvg/resvg-js';
import { buildRunOgSvg } from '$lib/og_run_image';

// Build-time per-run og:image PNG renderer. Mirror of
// /og/route/[id].png — adapter-static prerenders one PNG per
// public run so chat-app unfurls carry a real card.
//
// The card is stats-only (distance + runner attribution + date)
// rather than including the polyline. Reason: the run track is a
// gzipped JSON blob in the `runs` Storage bucket reachable only via
// the `clip-public-track` Edge Function (decisions §33). Calling
// that EF for every public run at build time is a hot loop we'd
// rather not own; a future iteration can layer the polyline on if
// the build cost stays acceptable. The current card is already a
// significant upgrade over the generic favicon — Slack / FB / X /
// LinkedIn unfurls now show the runner's distance + name + date.
export const prerender = true;

// Matches the +page.ts cap so the OG image and the +page surface
// cover the same set of runs. Pre-fix, both were 5k — a new public
// run between builds served the SPA-shell fallback `<head>` AND a
// missing og:image. 50k moves the gap from days to months.
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

export const GET: RequestHandler = async ({ params }) => {
	const png = await renderRunPng(params.id);
	return new Response(new Uint8Array(png), {
		headers: {
			'content-type': 'image/png',
			'cache-control': 'public, max-age=3600',
		},
	});
};

async function renderRunPng(id: string): Promise<Buffer> {
	let run:
		| {
				distance_m?: number | null;
				duration_s?: number | null;
				started_at?: string | null;
				source?: string | null;
				user_id?: string | null;
		  }
		| null = null;
	let displayName: string | null = null;
	if (PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY) {
		try {
			const supabase = createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
				auth: { persistSession: false },
			});
			const { data: row } = await supabase
				.from('public_runs')
				.select('id, user_id, distance_m, duration_s, started_at, source')
				.eq('id', id)
				.maybeSingle();
			run = row ?? null;
			if (run?.user_id) {
				const { data: profile } = await supabase
					.from('public_profiles')
					.select('display_name')
					.eq('id', run.user_id)
					.maybeSingle();
				displayName = profile?.display_name ?? null;
			}
		} catch (err) {
			console.warn('og/run load: supabase fetch failed', err);
		}
	}
	const svg = buildRunOgSvg({
		distance_m: run?.distance_m,
		duration_s: run?.duration_s,
		started_at: run?.started_at,
		source: run?.source,
		displayName,
	});
	const resvg = new Resvg(svg, {
		fitTo: { mode: 'width', value: 1200 },
		font: { loadSystemFonts: true },
	});
	return resvg.render().asPng();
}

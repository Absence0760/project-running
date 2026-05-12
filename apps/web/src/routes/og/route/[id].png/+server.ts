import type { EntryGenerator, RequestHandler } from './$types';
import { createClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { Resvg } from '@resvg/resvg-js';
import { buildRouteOgSvg } from '$lib/og_route_image';
import { fetchClippedRouteForViewer } from '$lib/data';
import type { TrackPoint } from '$lib/types';

// Build-time per-route og:image PNG renderer. adapter-static prerenders
// one PNG per public route alongside the /share/route/[id]/index.html
// page so chat-app unfurls (Slack / Discord / FB / LinkedIn / Twitter)
// get a real track preview rather than the generic apple-touch-icon.
//
// Output path: build/og/route/<id>.png — referenced from
// /share/route/[id]/+page.svelte as the og:image URL. CloudFront
// serves it straight from S3, same edge cache as the rest of the
// static site.
//
// SVG is built by the pure helper in `$lib/og_route_image`; resvg-js
// renders to PNG bytes here. Track polyline comes from the
// `clip_track_for_user` SECURITY DEFINER RPC (same path
// fetchPublicRoute uses for non-owner viewers) so privacy zones are
// applied server-side — a runner's home / work coordinate never leaks
// into a public unfurl image.
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
			console.warn('og/route prerender entries: public_routes fetch failed', error);
			return [];
		}
		return (data ?? []).map((r) => ({ id: r.id }));
	} catch (err) {
		console.warn('og/route prerender entries: supabase boot failed', err);
		return [];
	}
};

export const GET: RequestHandler = async ({ params }) => {
	const png = await renderRoutePng(params.id);
	return new Response(new Uint8Array(png), {
		headers: {
			'content-type': 'image/png',
			'cache-control': 'public, max-age=3600',
		},
	});
};

async function renderRoutePng(id: string): Promise<Buffer> {
	let routeMeta:
		| { name?: string | null; distance_m?: number | null; surface?: string | null }
		| null = null;
	let track: TrackPoint[] = [];
	if (PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY) {
		try {
			const supabase = createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
				auth: { persistSession: false },
			});
			const { data: meta } = await supabase
				.from('public_routes')
				.select('id, name, distance_m, surface')
				.eq('id', id)
				.maybeSingle();
			routeMeta = meta ?? null;
			// fetchClippedRouteForViewer uses the same supabase client
			// `import { supabase } from './supabase'` — that one is browser-
			// only. Inline the RPC call here with the prerender's anon
			// client instead so the build-time fetch works.
			try {
				const { data: clipped } = await supabase.rpc('clip_track_for_user', {
					p_route_id: id,
				});
				if (Array.isArray(clipped)) {
					track = (clipped as unknown[]).map((p) => p as TrackPoint);
				}
			} catch {
				// The route may not be loadable for anon (private + clip
				// RPC denies). The card still renders with the title.
			}
		} catch (err) {
			console.warn('og/route load: supabase fetch failed', err);
		}
	}
	const svg = buildRouteOgSvg({
		name: routeMeta?.name,
		distance_m: routeMeta?.distance_m,
		surface: routeMeta?.surface,
		track,
	});
	const resvg = new Resvg(svg, {
		fitTo: { mode: 'width', value: 1200 },
		font: {
			// Use the system DejaVu Sans available on linux build images
			// + CI; fonts inside the SVG fall through to this on the
			// rasteriser's font lookup so the strap/title aren't blank.
			loadSystemFonts: true,
		},
	});
	return resvg.render().asPng();
}

// silence the unused-import warning during dev — fetchClippedRouteForViewer
// is referenced in a comment above to anchor the design decision.
void fetchClippedRouteForViewer;

import type { RequestHandler } from './$types';
import { createClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { env } from '$env/dynamic/public';
import { buildRunCountByRouteId, buildSitemap, composeEntries } from '$lib/sitemap';

// Build-time sitemap. `adapter-static` runs this once during the
// production build because of `prerender = true`; the resulting
// /sitemap.xml is a plain file in `build/`. CloudFront serves it
// straight from S3 — no Lambda invocation per crawl.
//
// Source data: `public_routes` + `public_runs` views (both anon-
// readable per their grant statements). Anon JWT only — the
// service-role key never enters the static bundle.
//
// PUBLIC_SITE_URL (`$env/dynamic/public`) lets preview vs prod use
// different canonical hosts; defaults to https://threkir.com when
// unset so the local prerender still emits sensible URLs.
export const prerender = true;

const DEFAULT_SITE_URL = 'https://threkir.com';

// Sitemap spec caps at 50k URLs per file. Our public counts are
// nowhere near that; cap each list defensively at 10k as a guard
// against an unbounded build-time query landing a multi-MB blob in
// the static bundle.
const MAX_ROUTES = 10_000;
const MAX_RUNS = 10_000;

export const GET: RequestHandler = async () => {
	const base = env.PUBLIC_SITE_URL || DEFAULT_SITE_URL;
	// Tolerate a missing or unreachable Supabase instance at build
	// time — preview / local builds shouldn't hard-fail the static
	// build over a sitemap. Fall through to a top-level-only sitemap
	// when the fetch fails; the static site still ships.
	let routes: Array<{ id: string; updated_at: string | null }> = [];
	// public_runs deliberately omits `updated_at` (migration
	// 20260807_001 — the value leaks last-edit / last-sync cadence to
	// share-link viewers). `started_at` is the only timestamp the view
	// publishes and is the right lastmod for a public share page anyway.
	let runs: Array<{ id: string; updated_at: string | null; started_at: string | null }> = [];
	// Popularity map: route_id -> # of public_runs that ran it. Bumps
	// <priority> + <changefreq> on routes the community actually uses.
	let runCountByRouteId: Map<string, number> | undefined;
	if (PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY) {
		try {
			const supabase = createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
				auth: { persistSession: false },
			});
			const [routesRes, runsRes, popularityRes] = await Promise.all([
				supabase
					.from('public_routes')
					.select('id, updated_at')
					.order('updated_at', { ascending: false })
					.limit(MAX_ROUTES),
				supabase
					.from('public_runs')
					.select('id, started_at')
					.order('started_at', { ascending: false })
					.limit(MAX_RUNS),
				// public_runs.route_id is nulled out unless the linked
				// route is itself public (migration 20260626_001), so
				// the popularity signal only counts public-on-public
				// matches. The not.is.null filter keeps the payload
				// small (most runs don't link to a saved route).
				supabase
					.from('public_runs')
					.select('route_id')
					.not('route_id', 'is', null)
					.limit(MAX_RUNS),
			]);
			if (routesRes.error) {
				console.warn('sitemap: public_routes fetch failed', routesRes.error);
			}
			if (runsRes.error) {
				console.warn('sitemap: public_runs fetch failed', runsRes.error);
			}
			if (popularityRes.error) {
				console.warn('sitemap: popularity fetch failed', popularityRes.error);
			}
			routes = routesRes.data ?? [];
			runs = (runsRes.data ?? []).map((r) => ({
				id: r.id,
				updated_at: null,
				started_at: r.started_at,
			}));
			runCountByRouteId = buildRunCountByRouteId(popularityRes.data ?? []);
		} catch (err) {
			console.warn('sitemap: supabase fetch failed; emitting top-level-only', err);
		}
	}

	const body = buildSitemap(composeEntries(base, routes, runs, runCountByRouteId));
	return new Response(body, {
		headers: {
			'content-type': 'application/xml; charset=utf-8',
			// Crawl etiquette: long-cache the static file; CloudFront
			// invalidates on every release-web deploy anyway.
			'cache-control': 'public, max-age=3600',
		},
	});
};

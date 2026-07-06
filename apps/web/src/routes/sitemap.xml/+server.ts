import type { RequestHandler } from './$types';
import { createClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { env } from '$env/dynamic/public';
import {
	buildRunCountByRouteId,
	buildSitemap,
	composeEntries,
	entityEntries,
	learnEntries,
} from '$lib/share/sitemap';
import { listGuides } from '$lib/learn/guides';
import { CATEGORIES } from '$lib/learn/categories';

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
const MAX_ENTITIES = 10_000;
// Sitemap protocol hard limit: 50,000 URLs per file. The five capped
// lists above (routes + runs + events + clubs + races) sum to a
// theoretical 50k, which with the top-level + learn entries would tip
// just over and make the WHOLE file invalid (search engines reject an
// oversized sitemap outright). Guard the total; the durable fix once
// real counts approach this is a sitemap index (multiple files), see
// the truncation warning below.
const SITEMAP_MAX_URLS = 50_000;

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
	// Public entity share surfaces served by the entity-SSR Lambda.
	// All three tables are anon-readable (events inherit public-club
	// RLS, clubs filter is_public, race_listings is public discovery
	// data); profiles are intentionally NOT enumerated here.
	let events: Array<{ id: string; updated_at: string | null }> = [];
	let clubs: Array<{ slug: string; updated_at: string | null }> = [];
	let races: Array<{ id: string; updated_at: string | null }> = [];
	if (PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY) {
		try {
			const supabase = createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
				auth: { persistSession: false },
			});
			const [routesRes, runsRes, popularityRes, eventsRes, clubsRes, racesRes] =
				await Promise.all([
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
				// Public entity share pages. Events inherit public-club
				// visibility via RLS, clubs filter is_public, race_listings
				// is anon-readable public discovery data. All exclude
				// shadow_hidden (moderation auto-hide, migration 20270218_001) —
				// a hidden target must not be advertised to crawlers. Events
				// have no shadow_hidden column, so gate on the parent club's
				// via an inner-join filter.
				supabase
					.from('events')
					.select('id, updated_at, clubs!inner(shadow_hidden)')
					.eq('clubs.shadow_hidden', false)
					.order('updated_at', { ascending: false })
					.limit(MAX_ENTITIES),
				supabase
					.from('clubs')
					.select('slug, updated_at')
					.eq('is_public', true)
					.eq('shadow_hidden', false)
					.order('updated_at', { ascending: false })
					.limit(MAX_ENTITIES),
				// Anon reads go through the redacted public_race_listings
				// view, not the base table (migration 20270320_001 dropped
				// the base-table anon policy to strip submitted_by).
				supabase
					.from('public_race_listings')
					.select('id, updated_at')
					.order('race_date', { ascending: false })
					.limit(MAX_ENTITIES),
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
			if (eventsRes.error) console.warn('sitemap: events fetch failed', eventsRes.error);
			if (clubsRes.error) console.warn('sitemap: clubs fetch failed', clubsRes.error);
			if (racesRes.error) console.warn('sitemap: race_listings fetch failed', racesRes.error);
			routes = routesRes.data ?? [];
			runs = (runsRes.data ?? []).map((r) => ({
				id: r.id,
				updated_at: null,
				started_at: r.started_at,
			}));
			runCountByRouteId = buildRunCountByRouteId(popularityRes.data ?? []);
			// Drop the join-only `clubs` field the shadow_hidden filter pulled in.
			events = (eventsRes.data ?? []).map((e) => ({ id: e.id, updated_at: e.updated_at }));
			clubs = clubsRes.data ?? [];
			races = racesRes.data ?? [];
		} catch (err) {
			console.warn('sitemap: supabase fetch failed; emitting top-level-only', err);
		}
	}

	// Learn entries are build-time constants from the static guide index,
	// so they ship even if the Supabase fetch above failed.
	const learn = learnEntries(
		base,
		listGuides().map((g) => ({ slug: g.slug, updated: g.updated })),
		CATEGORIES.map((c) => c.id),
	);
	// Order matters for the total-cap truncation below: the small,
	// high-value surfaces (top-level + learn) go first so they're never
	// the ones dropped; the high-cardinality entity lists follow.
	const entries = [
		...composeEntries(base, routes, runs, runCountByRouteId),
		...learn,
		...entityEntries(base, events, clubs, races),
	];
	if (entries.length > SITEMAP_MAX_URLS) {
		// Not a silent cap — surface that the single-file sitemap has
		// outgrown the protocol limit and needs splitting into an index.
		console.warn(
			`sitemap: ${entries.length} URLs exceeds the ${SITEMAP_MAX_URLS} per-file limit; ` +
				`truncating. Split into a sitemap index.`,
		);
	}
	const body = buildSitemap(entries.slice(0, SITEMAP_MAX_URLS));
	return new Response(body, {
		headers: {
			'content-type': 'application/xml; charset=utf-8',
			// Crawl etiquette: long-cache the static file; CloudFront
			// invalidates on every release-web deploy anyway.
			'cache-control': 'public, max-age=3600',
		},
	});
};

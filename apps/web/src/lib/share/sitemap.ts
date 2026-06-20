/// Pure helpers for the prerendered /sitemap.xml endpoint. Split
/// out from `+server.ts` so unit tests can exercise the XML shape
/// without a SvelteKit build.
///
/// Sitemap spec: https://www.sitemaps.org/protocol.html
///   - Document declares xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
///   - Each <url> carries <loc> (required) + <lastmod> (optional)
///   - Hard caps: 50,000 URLs per file, 50 MB uncompressed. Our
///     run + route counts are far below either ceiling for the
///     foreseeable future.

export type SitemapEntry = {
	loc: string;
	lastmod?: string; // ISO 8601 (or any subset the spec accepts)
	changefreq?: 'always' | 'hourly' | 'daily' | 'weekly' | 'monthly' | 'yearly' | 'never';
	priority?: number; // 0.0..1.0
};

/// XML-escape the five characters with special meaning inside element
/// content + attribute values. Sitemap URLs shouldn't contain `<` or
/// `>`, but uuids and the trailing slash on the base URL are stable
/// — guarding here is cheap insurance against a future schema that
/// allows non-uuid public ids (slugs, handles).
export function xmlEscape(s: string): string {
	return s
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&apos;');
}

/// Strip the trailing slash from a base URL so concatenation with
/// `/share/...` yields a single-slash join. Idempotent.
export function normaliseBase(base: string): string {
	return base.replace(/\/+$/, '');
}

/// Build the sitemap XML body from an entries list. Stable ordering
/// — callers pass entries in the order they want them emitted; the
/// builder does not sort.
export function buildSitemap(entries: SitemapEntry[]): string {
	const lines: string[] = [];
	lines.push('<?xml version="1.0" encoding="UTF-8"?>');
	lines.push('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');
	for (const e of entries) {
		lines.push('  <url>');
		lines.push(`    <loc>${xmlEscape(e.loc)}</loc>`);
		if (e.lastmod) lines.push(`    <lastmod>${xmlEscape(e.lastmod)}</lastmod>`);
		if (e.changefreq) lines.push(`    <changefreq>${e.changefreq}</changefreq>`);
		if (e.priority != null) {
			lines.push(`    <priority>${e.priority.toFixed(1)}</priority>`);
		}
		lines.push('  </url>');
	}
	lines.push('</urlset>');
	return lines.join('\n') + '\n';
}

/// Bucket a route's run-count into a sitemap priority. Routes
/// without any recorded runs use the base 0.7; popular routes
/// bump up through 0.8 / 0.9 / 1.0 (cap matches the landing page).
/// Sub-linear (log-buckets) so a single hyper-popular route doesn't
/// drown the rest of the namespace.
export function priorityForRunCount(count: number): number {
	if (count >= 50) return 1.0;
	if (count >= 20) return 0.9;
	if (count >= 5) return 0.8;
	return 0.7;
}

/// changefreq for a route — popular routes get crawled more often.
/// Same bucketing as `priorityForRunCount` (a route popular enough
/// to bump priority is one where crawl freshness matters too).
export function changefreqForRunCount(
	count: number,
): 'daily' | 'weekly' | 'monthly' {
	if (count >= 20) return 'daily';
	if (count >= 5) return 'weekly';
	return 'monthly';
}

/// Compose the full entries list from the base URL + raw db rows.
/// Top-level surfaces (landing, feed, explore) come first; share
/// pages follow. `runCountByRouteId` is an optional popularity map
/// from a `public_runs.route_id` aggregation — present values bump
/// the route's <priority> + <changefreq>.
export function composeEntries(
	base: string,
	routes: Array<{ id: string; updated_at?: string | null }>,
	runs: Array<{ id: string; updated_at?: string | null; started_at?: string | null }>,
	runCountByRouteId?: Map<string, number>,
): SitemapEntry[] {
	const b = normaliseBase(base);
	const entries: SitemapEntry[] = [
		{ loc: `${b}/`, changefreq: 'weekly', priority: 1.0 },
		// /feed is auth-gated but the URL is well-known; let crawlers
		// know it exists so the login redirect resolves to a stable
		// destination.
		{ loc: `${b}/feed`, changefreq: 'daily', priority: 0.5 },
		// /routes?tab=explore is the public discovery entry point.
		{ loc: `${b}/routes?tab=explore`, changefreq: 'daily', priority: 0.6 },
	];
	for (const r of routes) {
		const count = runCountByRouteId?.get(r.id) ?? 0;
		entries.push({
			loc: `${b}/share/route/${r.id}`,
			lastmod: r.updated_at ?? undefined,
			changefreq: changefreqForRunCount(count),
			priority: priorityForRunCount(count),
		});
	}
	for (const r of runs) {
		entries.push({
			loc: `${b}/share/run/${r.id}`,
			lastmod: r.updated_at ?? r.started_at ?? undefined,
			changefreq: 'monthly',
			priority: 0.6,
		});
	}
	return entries;
}

/// Learn-hub sitemap entries: the hub, one per category, one per guide.
/// Pure — the caller passes plain `{ slug, updated, category }` rows (the
/// build-time guide index from `$lib/learn/guides`) + the category ids so
/// this module stays import.meta.glob-free and tsx-testable. The Learn
/// entries are build-time constants, so the endpoint emits them even when
/// the Supabase fetch for routes/runs fails.
export function learnEntries(
	base: string,
	guides: Array<{ slug: string; updated?: string | null }>,
	categoryIds: string[],
): SitemapEntry[] {
	const b = normaliseBase(base);
	const entries: SitemapEntry[] = [
		{ loc: `${b}/learn`, changefreq: 'weekly', priority: 0.8 },
	];
	for (const id of categoryIds) {
		entries.push({ loc: `${b}/learn/category/${id}`, changefreq: 'weekly', priority: 0.6 });
	}
	for (const g of guides) {
		entries.push({
			loc: `${b}/learn/${g.slug}`,
			lastmod: g.updated ?? undefined,
			changefreq: 'monthly',
			priority: 0.7,
		});
	}
	return entries;
}

/// Tally `public_runs.route_id` into a Map keyed by route_id. Used
/// by the sitemap endpoint to popularity-weight routes. Rows with a
/// null `route_id` (the most common case — most runs aren't matched
/// to a saved route) are ignored.
export function buildRunCountByRouteId(
	rows: Array<{ route_id?: string | null }>,
): Map<string, number> {
	const out = new Map<string, number>();
	for (const r of rows) {
		const id = r.route_id;
		if (!id) continue;
		out.set(id, (out.get(id) ?? 0) + 1);
	}
	return out;
}

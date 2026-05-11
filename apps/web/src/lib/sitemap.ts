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

/// Compose the full entries list from the base URL + raw db rows.
/// Top-level surfaces (landing, feed, explore) come first; share
/// pages follow.
export function composeEntries(
	base: string,
	routes: Array<{ id: string; updated_at?: string | null }>,
	runs: Array<{ id: string; updated_at?: string | null; started_at?: string | null }>,
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
		entries.push({
			loc: `${b}/share/route/${r.id}`,
			lastmod: r.updated_at ?? undefined,
			changefreq: 'weekly',
			priority: 0.7,
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

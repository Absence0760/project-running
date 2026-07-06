/// Site-wide schema.org JSON-LD builders — the `Organization` and
/// `WebSite` nodes that belong on the public landing page (and any
/// other top-level marketing surface). Sibling of share_meta.ts /
/// learn_meta.ts: per-entity pages describe themselves (WebPage /
/// Article / Event), while these two describe the brand + site as a
/// whole so search engines can render the knowledge-panel / sitelinks
/// treatment for the "Threkir" query.
///
/// Pure string helpers so a unit test can pin the wire shape without
/// booting SvelteKit. The three-character JSON-LD escape is duplicated
/// here rather than shared (a three-line helper isn't worth a module —
/// same call the sibling builders make).

import { normaliseSiteUrl } from './share_meta';

const SITE_NAME = 'Threkir';

/// One-line brand description reused across the Organization + WebSite
/// nodes and available as the landing-page meta description default.
export const SITE_DESCRIPTION =
	'Track your runs, build training plans, and follow friends — a cross-platform running app for road, trail, and ultra.';

/// Escape the three characters that let a string break out of a
/// `<script type="application/ld+json">` block when injected verbatim
/// into HTML. `<` is the only strictly necessary one (`</script>`); the
/// other two keep the payload valid JSON either way (belt-and-braces).
function escapeJsonLd(json: string): string {
	return json
		.replace(/</g, '\\u003c')
		.replace(/>/g, '\\u003e')
		.replace(/&/g, '\\u0026');
}

/// schema.org `Organization` node for the brand. `logo` points at the
/// 512px app icon (a square raster Google accepts for the knowledge
/// panel). `sameAs` is intentionally omitted until there are real,
/// stable social profiles to list — an empty or speculative array is
/// worse than none. Returns a string ready to drop inside a
/// `<script type="application/ld+json">`.
export function buildOrganizationJsonLd(base: string | null | undefined): string {
	const b = normaliseSiteUrl(base);
	const graph = {
		'@context': 'https://schema.org',
		'@type': 'Organization',
		name: SITE_NAME,
		url: `${b}/`,
		logo: `${b}/icon-512.png`,
		description: SITE_DESCRIPTION,
	};
	return escapeJsonLd(JSON.stringify(graph));
}

/// schema.org `WebSite` node. Deliberately carries no `potentialAction`
/// SearchAction: the app has no public, unauthenticated search endpoint
/// to point one at, and a SearchAction whose target 404s / bounces to
/// /login is worse than none (Google may surface a broken sitelinks
/// searchbox). Add one only if/when a public `/search?q=` route ships.
export function buildWebSiteJsonLd(base: string | null | undefined): string {
	const b = normaliseSiteUrl(base);
	const graph = {
		'@context': 'https://schema.org',
		'@type': 'WebSite',
		name: SITE_NAME,
		url: `${b}/`,
		description: SITE_DESCRIPTION,
	};
	return escapeJsonLd(JSON.stringify(graph));
}

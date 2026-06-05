/// Per-route `<head>` meta-tag builder for the share-route page.
/// Pure string helpers — used by the production share-route Lambda
/// (which injects these into the SPA-shell HTML at request time). The
/// dev-server +page.svelte renders the equivalent tags via Svelte's
/// `<svelte:head>` using the same underlying share_meta builders, so
/// the two paths stay in lockstep.
///
/// Mirror of share_run_meta.ts. Kept in apps/web/src/lib so the Lambda
/// build can pull this + the related helpers from a single tree
/// without dragging in $env or SvelteKit-only modules.

import {
	buildRouteShareTitle,
	buildRouteShareDescription,
	buildRouteShareCanonical,
	buildRouteJsonLd,
	normaliseSiteUrl,
	type ShareRouteMeta as ShareRouteMetaFields,
} from './share_meta';
import { escapeHtml } from '../util/html_escape';

export interface ShareRouteMetaInput {
	id: string;
	route: ShareRouteMetaFields | null;
	siteUrl: string;
}

export interface ShareRouteHead {
	title: string;
	description: string;
	/// Absolute canonical URL — also serves as og:url so search engines
	/// fold the in-app /routes/[id] surface onto this single page.
	canonical: string;
	ogImageUrl: string;
	/// Pre-escaped JSON-LD payload, ready to drop inside a
	/// `<script type="application/ld+json">` (buildRouteJsonLd escapes
	/// the < / > / & that could terminate the script element early).
	jsonLd: string;
}

export function buildShareRouteHead(input: ShareRouteMetaInput): ShareRouteHead {
	const { id, route, siteUrl } = input;
	const base = normaliseSiteUrl(siteUrl);
	return {
		title: buildRouteShareTitle(route),
		description: buildRouteShareDescription(route),
		canonical: buildRouteShareCanonical(siteUrl, id),
		ogImageUrl: `${base}/og/route/${id}.png`,
		jsonLd: buildRouteJsonLd(route, { id, base: siteUrl }),
	};
}

/// Render the `<head>` tags the share-route Lambda injects into the
/// SPA shell. Output is a single string — caller is responsible for
/// finding the right insertion point in the index.html template. Each
/// value is HTML-attribute-escaped (the `content=` / `href=` value is
/// the realistic injection surface) so a malicious route name can't
/// break out of its attribute. The JSON-LD payload is already escaped
/// for the script-element context by buildRouteJsonLd.
export function renderShareRouteHeadTags(head: ShareRouteHead): string {
	const e = escapeHtml;
	return [
		`<title>${e(head.title)}</title>`,
		`<meta name="description" content="${e(head.description)}">`,
		`<link rel="canonical" href="${e(head.canonical)}">`,
		`<meta property="og:title" content="${e(head.title)}">`,
		`<meta property="og:description" content="${e(head.description)}">`,
		`<meta property="og:type" content="website">`,
		`<meta property="og:url" content="${e(head.canonical)}">`,
		`<meta property="og:image" content="${e(head.ogImageUrl)}">`,
		`<meta property="og:image:width" content="1200">`,
		`<meta property="og:image:height" content="630">`,
		`<meta property="og:site_name" content="Threkir">`,
		`<meta name="twitter:card" content="summary_large_image">`,
		`<meta name="twitter:title" content="${e(head.title)}">`,
		`<meta name="twitter:description" content="${e(head.description)}">`,
		`<meta name="twitter:image" content="${e(head.ogImageUrl)}">`,
		`<script type="application/ld+json">${head.jsonLd}</script>`,
	].join('\n\t');
}

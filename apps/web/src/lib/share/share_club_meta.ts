/// Per-club `<head>` meta-tag + JSON-LD builders for the public
/// share-club page. Pure string helpers — used by the SvelteKit
/// +page.svelte (dev-server SSR) and the production entity-SSR Lambda,
/// the same split as the sibling share_*_meta.ts modules.

import { normaliseSiteUrl } from './share_meta';
import { escapeHtml } from '../util/html_escape';
import type { SharedClub } from './share_club_lookup';

const SITE_NAME = 'Threkir';

function escapeJsonLd(json: string): string {
	return json
		.replace(/</g, '\\u003c')
		.replace(/>/g, '\\u003e')
		.replace(/&/g, '\\u0026');
}

function clean(raw: string | null | undefined, max: number): string {
	const collapsed = (raw ?? '').replace(/\s+/g, ' ').trim();
	if (!collapsed) return '';
	return collapsed.length > max ? `${collapsed.slice(0, max - 1).trimEnd()}…` : collapsed;
}

export function buildClubShareTitle(club: SharedClub | null | undefined): string {
	const n = clean(club?.name, 80);
	return n ? `${n} — ${SITE_NAME}` : `Club — ${SITE_NAME}`;
}

export function buildClubShareDescription(club: SharedClub | null | undefined): string {
	if (!club) return `A running club on ${SITE_NAME}.`;
	const desc = clean(club.description, 160);
	if (desc) return desc;
	const loc = clean(club.location_label, 60);
	return loc
		? `A running club in ${loc} on ${SITE_NAME}.`
		: `A running club on ${SITE_NAME}.`;
}

/// Canonical for a public club share page. Keyed by slug (mirrors the
/// in-app /clubs/[slug] URL).
export function buildClubShareCanonical(
	base: string | null | undefined,
	slug: string,
): string {
	return `${normaliseSiteUrl(base)}/share/club/${slug}`;
}

/// schema.org JSON-LD for a public club: a `SportsOrganization` (the
/// running-club-appropriate Organization subtype) with name,
/// description, logo, and — only the coarse `location_label` as an
/// `areaServed`. Name / description are user-controlled, so the output
/// is escaped for the script-element context.
export function buildClubJsonLd(
	club: SharedClub | null | undefined,
	opts: { slug: string; base: string | null | undefined },
): string {
	const base = normaliseSiteUrl(opts.base);
	const canonical = `${base}/share/club/${opts.slug}`;
	const graph: Record<string, unknown> = {
		'@context': 'https://schema.org',
		'@type': 'SportsOrganization',
		name: clean(club?.name, 120) || 'Club',
		description: buildClubShareDescription(club),
		url: canonical,
		sport: 'Running',
	};
	if (club?.avatar_url) {
		graph.logo = club.avatar_url;
		graph.image = club.avatar_url;
	}
	if (club?.location_label) graph.areaServed = clean(club.location_label, 120);
	return escapeJsonLd(JSON.stringify(graph));
}

export interface ShareClubMetaInput {
	slug: string;
	club: SharedClub | null;
	siteUrl: string;
}

export interface ShareClubHead {
	title: string;
	description: string;
	canonical: string;
	ogImageUrl: string;
	jsonLd: string;
}

export function buildShareClubHead(input: ShareClubMetaInput): ShareClubHead {
	const { slug, club, siteUrl } = input;
	const base = normaliseSiteUrl(siteUrl);
	return {
		title: buildClubShareTitle(club),
		description: buildClubShareDescription(club),
		canonical: buildClubShareCanonical(siteUrl, slug),
		ogImageUrl: club?.avatar_url || `${base}/og-default.png`,
		jsonLd: buildClubJsonLd(club, { slug, base: siteUrl }),
	};
}

export function renderShareClubHeadTags(head: ShareClubHead): string {
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
		`<meta property="og:site_name" content="Threkir">`,
		`<meta name="twitter:card" content="summary">`,
		`<meta name="twitter:title" content="${e(head.title)}">`,
		`<meta name="twitter:description" content="${e(head.description)}">`,
		`<meta name="twitter:image" content="${e(head.ogImageUrl)}">`,
		`<script type="application/ld+json">${head.jsonLd}</script>`,
	].join('\n\t');
}

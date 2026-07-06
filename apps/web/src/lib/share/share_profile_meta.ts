/// Per-profile `<head>` meta-tag + JSON-LD builders for the public
/// share-profile page. Pure string helpers — used by the SvelteKit
/// +page.svelte (dev-server SSR) and the production entity-SSR Lambda,
/// the same split as share_route_meta.ts / share_event_meta.ts.

import { normaliseSiteUrl } from './share_meta';
import { escapeHtml } from '../util/html_escape';
import type { SharedProfile } from './share_profile_lookup';

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

/// Display name with a safe fallback (a profile may have no name set).
export function profileDisplayName(profile: SharedProfile | null | undefined): string {
	return clean(profile?.display_name, 80) || 'Runner';
}

export function buildProfileShareTitle(profile: SharedProfile | null | undefined): string {
	if (!profile) return `Runner — ${SITE_NAME}`;
	return `${profileDisplayName(profile)} — ${SITE_NAME}`;
}

export function buildProfileShareDescription(profile: SharedProfile | null | undefined): string {
	if (!profile) return `A runner on ${SITE_NAME}.`;
	return `Follow ${profileDisplayName(profile)}'s running on ${SITE_NAME} — runs, routes, and achievements.`;
}

export function buildProfileShareCanonical(
	base: string | null | undefined,
	id: string,
): string {
	return `${normaliseSiteUrl(base)}/share/profile/${id}`;
}

/// schema.org JSON-LD for a public profile: a `ProfilePage` whose
/// `mainEntity` is a `Person` (name + avatar image). No email, location,
/// or any private field — only the anon-safe display name + avatar the
/// public_profile_by_id RPC exposes. Display name is user-controlled, so
/// the output is escaped for the script-element context.
export function buildProfileJsonLd(
	profile: SharedProfile | null | undefined,
	opts: { id: string; base: string | null | undefined },
): string {
	const base = normaliseSiteUrl(opts.base);
	const canonical = `${base}/share/profile/${opts.id}`;
	const name = profileDisplayName(profile);
	const person: Record<string, unknown> = { '@type': 'Person', name };
	if (profile?.avatar_url) person.image = profile.avatar_url;
	const graph = {
		'@context': 'https://schema.org',
		'@type': 'ProfilePage',
		name: `${name} on ${SITE_NAME}`,
		url: canonical,
		mainEntity: person,
	};
	return escapeJsonLd(JSON.stringify(graph));
}

export interface ShareProfileMetaInput {
	id: string;
	profile: SharedProfile | null;
	siteUrl: string;
}

export interface ShareProfileHead {
	title: string;
	description: string;
	canonical: string;
	ogImageUrl: string;
	jsonLd: string;
}

export function buildShareProfileHead(input: ShareProfileMetaInput): ShareProfileHead {
	const { id, profile, siteUrl } = input;
	const base = normaliseSiteUrl(siteUrl);
	// Prefer the runner's avatar as the OG image when present (a personal
	// face-card unfurls better than the generic brand card); fall back to
	// the branded 1200x630 card otherwise.
	const ogImageUrl = profile?.avatar_url || `${base}/og-default.png`;
	return {
		title: buildProfileShareTitle(profile),
		description: buildProfileShareDescription(profile),
		canonical: buildProfileShareCanonical(siteUrl, id),
		ogImageUrl,
		jsonLd: buildProfileJsonLd(profile, { id, base: siteUrl }),
	};
}

export function renderShareProfileHeadTags(head: ShareProfileHead): string {
	const e = escapeHtml;
	return [
		`<title>${e(head.title)}</title>`,
		`<meta name="description" content="${e(head.description)}">`,
		`<link rel="canonical" href="${e(head.canonical)}">`,
		`<meta property="og:title" content="${e(head.title)}">`,
		`<meta property="og:description" content="${e(head.description)}">`,
		`<meta property="og:type" content="profile">`,
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

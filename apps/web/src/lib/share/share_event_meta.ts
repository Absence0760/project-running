/// Per-event `<head>` meta-tag + JSON-LD builders for the public
/// share-event page. Pure string helpers — used by the SvelteKit
/// +page.svelte (dev-server SSR) and the production entity-SSR Lambda
/// (which injects these into the SPA-shell HTML at request time), the
/// same split as share_route_meta.ts.
///
/// Stable across viewers (a Slack unfurl must not change based on who
/// scraped it): distances default to km + dates render in UTC, ignoring
/// the viewer's unit/locale preference — reusing the share_meta
/// formatters so the wire shape can't drift from the run/route pages.

import {
	formatKmStable,
	formatDateStable,
	normaliseSiteUrl,
} from './share_meta';
import { escapeHtml } from '../util/html_escape';
import type { SharedEvent } from './share_event_lookup';

const SITE_NAME = 'Threkir';

/// Escape the three characters that could break out of a
/// `<script type="application/ld+json">` when injected verbatim.
function escapeJsonLd(json: string): string {
	return json
		.replace(/</g, '\\u003c')
		.replace(/>/g, '\\u003e')
		.replace(/&/g, '\\u0026');
}

/// Collapse + truncate a user-set string for a meta tag so a
/// pathological title/description can't blow out the head.
function clean(raw: string | null | undefined, max: number): string {
	const collapsed = (raw ?? '').replace(/\s+/g, ' ').trim();
	if (!collapsed) return '';
	return collapsed.length > max ? `${collapsed.slice(0, max - 1).trimEnd()}…` : collapsed;
}

export function buildEventShareTitle(event: SharedEvent | null | undefined): string {
	const t = clean(event?.title, 80);
	return t ? `${t} — ${SITE_NAME}` : `Event — ${SITE_NAME}`;
}

export function buildEventShareDescription(event: SharedEvent | null | undefined): string {
	if (!event) return `A public event on ${SITE_NAME}.`;
	const bits: string[] = [];
	const date = formatDateStable(event.starts_at);
	if (date) bits.push(date);
	const km = formatKmStable(event.distance_m);
	if (km) bits.push(km);
	if (event.club_name) bits.push(`hosted by ${clean(event.club_name, 60)}`);
	if (event.club_location) bits.push(`in ${clean(event.club_location, 60)}`);
	const lead = bits.length ? `${bits.join(' · ')}. ` : '';
	const desc = clean(event.description, 160);
	return `${lead}${desc || `A public event on ${SITE_NAME}.`}`.trim();
}

/// Absolute canonical URL for a public event share page.
export function buildEventShareCanonical(
	base: string | null | undefined,
	id: string,
): string {
	return `${normaliseSiteUrl(base)}/share/event/${id}`;
}

/// schema.org JSON-LD for a public event. Athletic categories (run /
/// cycle) map to `SportsEvent`; class / social map to the generic
/// `Event`. Emits `startDate` (+ `endDate` when a duration is known),
/// an offline attendance mode, the host club as `organizer` (linked to
/// its public /clubs/[slug] page) and — only the club's COARSE
/// `location_label` as the `location` Place. The precise meet
/// coordinate is deliberately never emitted (privacy — decisions §147).
///
/// Event title / club name / description are user-controlled, so the
/// output is escaped for the script-element context.
export function buildEventJsonLd(
	event: SharedEvent | null | undefined,
	opts: { id: string; base: string | null | undefined },
): string {
	const base = normaliseSiteUrl(opts.base);
	const canonical = `${base}/share/event/${opts.id}`;
	const isAthletic = event?.category === 'run' || event?.category === 'cycle' || event?.category == null;
	const graph: Record<string, unknown> = {
		'@context': 'https://schema.org',
		'@type': isAthletic ? 'SportsEvent' : 'Event',
		name: clean(event?.title, 120) || 'Event',
		description: buildEventShareDescription(event),
		url: canonical,
		eventAttendanceMode: 'https://schema.org/OfflineEventAttendanceMode',
		eventStatus: 'https://schema.org/EventScheduled',
	};
	if (event?.starts_at) {
		graph.startDate = event.starts_at;
		if (event.duration_min && event.duration_min > 0) {
			const end = new Date(new Date(event.starts_at).getTime() + event.duration_min * 60_000);
			if (!Number.isNaN(end.getTime())) graph.endDate = end.toISOString();
		}
	}
	if (event?.club_name) {
		graph.organizer = {
			'@type': 'Organization',
			name: clean(event.club_name, 120),
			...(event.club_slug ? { url: `${base}/clubs/${event.club_slug}` } : {}),
		};
	}
	if (event?.club_location) {
		graph.location = {
			'@type': 'Place',
			name: clean(event.club_location, 120),
		};
	}
	return escapeJsonLd(JSON.stringify(graph));
}

export interface ShareEventMetaInput {
	id: string;
	event: SharedEvent | null;
	siteUrl: string;
}

export interface ShareEventHead {
	title: string;
	description: string;
	canonical: string;
	ogImageUrl: string;
	jsonLd: string;
}

export function buildShareEventHead(input: ShareEventMetaInput): ShareEventHead {
	const { id, event, siteUrl } = input;
	const base = normaliseSiteUrl(siteUrl);
	return {
		title: buildEventShareTitle(event),
		description: buildEventShareDescription(event),
		canonical: buildEventShareCanonical(siteUrl, id),
		// Events have no dedicated OG renderer yet — use the branded card.
		ogImageUrl: `${base}/og-default.png`,
		jsonLd: buildEventJsonLd(event, { id, base: siteUrl }),
	};
}

/// Render the `<head>` tags the entity-SSR Lambda injects into the SPA
/// shell for an event. Each value is HTML-attribute-escaped; the JSON-LD
/// is already escaped for the script context by buildEventJsonLd.
export function renderShareEventHeadTags(head: ShareEventHead): string {
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

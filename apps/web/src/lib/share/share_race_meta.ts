/// Per-race `<head>` meta-tag + JSON-LD builders for the public
/// share-race page. Pure string helpers — used by the SvelteKit
/// +page.svelte (dev-server SSR) and the production entity-SSR Lambda.

import { formatKmStable, formatDateStable, normaliseSiteUrl } from './share_meta';
import { escapeHtml } from '../util/html_escape';
import type { SharedRace } from './share_race_lookup';

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

export function buildRaceShareTitle(race: SharedRace | null | undefined): string {
	const n = clean(race?.name, 90);
	return n ? `${n} — ${SITE_NAME}` : `Race — ${SITE_NAME}`;
}

export function buildRaceShareDescription(race: SharedRace | null | undefined): string {
	if (!race) return `A race on the ${SITE_NAME} calendar.`;
	const bits: string[] = [];
	const date = formatDateStable(race.race_date);
	if (date) bits.push(date);
	const km = formatKmStable(race.distance_m);
	if (km) bits.push(km);
	if (race.location_label) bits.push(clean(race.location_label, 60));
	const lead = bits.length ? `${bits.join(' · ')}. ` : '';
	return `${lead}Find it on the ${SITE_NAME} race calendar.`.trim();
}

export function buildRaceShareCanonical(
	base: string | null | undefined,
	id: string,
): string {
	return `${normaliseSiteUrl(base)}/share/race/${id}`;
}

/// schema.org JSON-LD for a public race listing: a `SportsEvent` with
/// name, startDate (the race date), coarse location Place, and offline
/// attendance. Name / location are user-submitted, so the output is
/// escaped for the script-element context.
export function buildRaceJsonLd(
	race: SharedRace | null | undefined,
	opts: { id: string; base: string | null | undefined },
): string {
	const base = normaliseSiteUrl(opts.base);
	const canonical = `${base}/share/race/${opts.id}`;
	const graph: Record<string, unknown> = {
		'@context': 'https://schema.org',
		'@type': 'SportsEvent',
		name: clean(race?.name, 120) || 'Race',
		description: buildRaceShareDescription(race),
		url: canonical,
		sport: 'Running',
		eventAttendanceMode: 'https://schema.org/OfflineEventAttendanceMode',
		eventStatus: 'https://schema.org/EventScheduled',
	};
	if (race?.race_date) graph.startDate = race.race_date;
	if (race?.location_label) {
		graph.location = { '@type': 'Place', name: clean(race.location_label, 120) };
	}
	return escapeJsonLd(JSON.stringify(graph));
}

export interface ShareRaceMetaInput {
	id: string;
	race: SharedRace | null;
	siteUrl: string;
}

export interface ShareRaceHead {
	title: string;
	description: string;
	canonical: string;
	ogImageUrl: string;
	jsonLd: string;
}

export function buildShareRaceHead(input: ShareRaceMetaInput): ShareRaceHead {
	const { id, race, siteUrl } = input;
	const base = normaliseSiteUrl(siteUrl);
	return {
		title: buildRaceShareTitle(race),
		description: buildRaceShareDescription(race),
		canonical: buildRaceShareCanonical(siteUrl, id),
		ogImageUrl: `${base}/og-default.png`,
		jsonLd: buildRaceJsonLd(race, { id, base: siteUrl }),
	};
}

export function renderShareRaceHeadTags(head: ShareRaceHead): string {
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

/// Per-plan `<head>` meta-tag + JSON-LD builders for the public
/// share-session page. Pure string helpers — used by the SvelteKit
/// +page.svelte (dev-server SSR) and the production entity-SSR Lambda.
///
/// Privacy boundary: every field read here comes from what
/// `share_session_lookup` selects, which is the plan's authored shape only
/// (title / discipline / equipment / est_duration_min plus the blocks and
/// items). A session plan carries no author fitness or body data at all —
/// but the per-item `cue` and `tempo` are the author's free-text teaching
/// notes, and those stay out of the meta: an og:description is handed to
/// every unfurler that touches the link, so it says how many movements and
/// how long, never what the author wrote in them.
///
/// The estimated duration and the movement count are stable integers and the
/// strings are English, deliberately ignoring the viewer's locale: an unfurl
/// must not change with who triggered the scrape. See share_meta.ts's header
/// for the full argument.

import { normaliseSiteUrl } from './share_meta';
import { escapeHtml } from '../util/html_escape';
import { expandSessionSteps } from '../social/session_steps';
import type { SharedSession } from './share_session_lookup';

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

/// The plan's length in whole minutes: the author's own estimate when set,
/// otherwise the expanded step sequence's total. Routed through the shared
/// `expandSessionSteps` parity helper so the share page's summary tile and
/// the og:description can't disagree about the number.
export function sessionEstimatedMinutes(session: SharedSession | null | undefined): number {
	if (!session) return 0;
	if (session.est_duration_min != null && session.est_duration_min > 0) {
		return session.est_duration_min;
	}
	const { totalS } = expandSessionSteps({
		blocks: session.blocks.map((b) => ({ id: b.id, position: b.position, name: b.name })),
		items: session.items.map((it) => ({
			id: it.id,
			block_id: it.block_id,
			position: it.position,
			movement_name: it.movement_name,
			kind: it.kind,
			duration_s: it.duration_s,
			reps: it.reps,
			per_side: it.per_side,
			tempo: it.tempo,
			cue: it.cue,
		})),
	});
	return Math.round(totalS / 60);
}

export function buildSessionShareTitle(
	session: SharedSession | null | undefined,
	displayName?: string | null,
): string {
	if (!session) return `Session — ${SITE_NAME}`;
	const custom = clean(session.title, 80);
	if (custom) return `${custom} — ${SITE_NAME}`;
	const by = clean(displayName, 60);
	return by ? `Session by ${by} — ${SITE_NAME}` : `Session — ${SITE_NAME}`;
}

export function buildSessionShareDescription(
	session: SharedSession | null | undefined,
	displayName?: string | null,
): string {
	if (!session) return `View a public session plan on ${SITE_NAME}.`;
	const bits: string[] = [];
	const discipline = clean(session.discipline, 40);
	if (discipline) bits.push(discipline);
	const movements = session.items.length;
	if (movements > 0) bits.push(`${movements} ${movements === 1 ? 'movement' : 'movements'}`);
	const minutes = sessionEstimatedMinutes(session);
	if (minutes > 0) bits.push(`about ${minutes} min`);
	const equipment = clean(session.equipment, 40);
	if (equipment) bits.push(equipment);
	const by = clean(displayName, 60);
	if (by) bits.push(`by ${by}`);
	const lead = bits.length ? `${bits.join(' · ')}. ` : '';
	return `${lead}Follow the sequence on ${SITE_NAME}.`.trim();
}

/// Absolute canonical URL for a public session-plan share page. The in-app
/// /sessions/[id] surface points its canonical here — and builds its
/// copyable share link from the same helper — so search engines consolidate
/// onto the single public page and the two URLs can never drift apart.
export function buildSessionShareCanonical(
	base: string | null | undefined,
	id: string,
): string {
	return `${normaliseSiteUrl(base)}/share/session/${id}`;
}

function sessionShareName(
	session: SharedSession | null | undefined,
	displayName?: string | null,
): string {
	const full = buildSessionShareTitle(session, displayName);
	const suffix = ` — ${SITE_NAME}`;
	return full.endsWith(suffix) ? full.slice(0, -suffix.length) : full;
}

/// schema.org JSON-LD for a public session-plan share page: a `WebPage` + a
/// `BreadcrumbList` (Home → session), mirroring `buildRunJsonLd`.
///
/// `ExercisePlan` is the tailored type and is still refused: its supertype
/// chain runs through `MedicalEntity`, so adopting it would publish a yoga
/// or pilates sequence as medical structured data. `WebPage` + breadcrumb is
/// the honest, broadly-supported choice, and keeps this surface consistent
/// with the workout twin beside it. No `primaryImageOfPage`: there is no
/// per-plan OG PNG, and pointing it at the brand card would misdescribe the
/// page.
///
/// Title, discipline, equipment, and display name are user-controlled, so
/// the output goes through `escapeJsonLd` before it reaches the DOM.
export function buildSessionJsonLd(
	session: SharedSession | null | undefined,
	opts: { id: string; base: string | null | undefined; displayName?: string | null },
): string {
	const base = normaliseSiteUrl(opts.base);
	const canonical = buildSessionShareCanonical(base, opts.id);
	const name = sessionShareName(session, opts.displayName);
	const graph = {
		'@context': 'https://schema.org',
		'@type': 'WebPage',
		name,
		description: buildSessionShareDescription(session, opts.displayName),
		url: canonical,
		breadcrumb: {
			'@type': 'BreadcrumbList',
			itemListElement: [
				{ '@type': 'ListItem', position: 1, name: SITE_NAME, item: `${base}/` },
				{ '@type': 'ListItem', position: 2, name },
			],
		},
	};
	return escapeJsonLd(JSON.stringify(graph));
}

export interface ShareSessionMetaInput {
	id: string;
	session: SharedSession | null;
	displayName: string | null;
	siteUrl: string;
}

export interface ShareSessionHead {
	title: string;
	description: string;
	canonical: string;
	ogImageUrl: string;
	jsonLd: string;
}

export function buildShareSessionHead(input: ShareSessionMetaInput): ShareSessionHead {
	const { id, session, displayName, siteUrl } = input;
	const base = normaliseSiteUrl(siteUrl);
	return {
		title: buildSessionShareTitle(session, displayName),
		description: buildSessionShareDescription(session, displayName),
		canonical: buildSessionShareCanonical(siteUrl, id),
		ogImageUrl: `${base}/og-default.png`,
		jsonLd: buildSessionJsonLd(session, { id, base: siteUrl, displayName }),
	};
}

export function renderShareSessionHeadTags(head: ShareSessionHead): string {
	const e = escapeHtml;
	return [
		`<title>${e(head.title)}</title>`,
		`<meta name="description" content="${e(head.description)}">`,
		`<link rel="canonical" href="${e(head.canonical)}">`,
		`<meta property="og:title" content="${e(head.title)}">`,
		`<meta property="og:description" content="${e(head.description)}">`,
		`<meta property="og:type" content="article">`,
		`<meta property="og:url" content="${e(head.canonical)}">`,
		`<meta property="og:image" content="${e(head.ogImageUrl)}">`,
		`<meta property="og:image:width" content="1200">`,
		`<meta property="og:image:height" content="630">`,
		`<meta property="og:site_name" content="${SITE_NAME}">`,
		`<meta name="twitter:card" content="summary_large_image">`,
		`<meta name="twitter:title" content="${e(head.title)}">`,
		`<meta name="twitter:description" content="${e(head.description)}">`,
		`<meta name="twitter:image" content="${e(head.ogImageUrl)}">`,
		`<script type="application/ld+json">${head.jsonLd}</script>`,
	].join('\n\t');
}

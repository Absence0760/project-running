/// Per-recap `<head>` meta-tag builder for the public recap share page.
/// Pure string helpers — shared between the SvelteKit +page.svelte
/// (dev-server SSR via $lib reads) and the production share-recap Lambda
/// (which injects these into the SPA-shell HTML). Kept in apps/web/src/lib
/// so the Lambda build pulls it without dragging in $env / SvelteKit-only
/// modules. Mirrors share_run_meta.ts.

import type { SharedRecap } from './share_recap_lookup';
import { recapPeriodLabel } from './recap_period_label';
import { normaliseSiteUrl } from './share_meta';
import { escapeHtml } from '../util/html_escape';

/// Absolute URL of a frozen recap's public share page. Note the path shape:
/// the recap share page predates the `/share/<entity>/[id]` family and lives
/// at `/recap/share/[id]`, so it is the one entity whose public URL is not
/// under `/share/`. The one definition of it — resolve against
/// `PUBLIC_SITE_URL` for a `<head>`, against `location.origin` for a
/// copy-link (§ 520).
export function buildRecapShareCanonical(
	base: string | null | undefined,
	id: string,
): string {
	return `${normaliseSiteUrl(base)}/recap/share/${id}`;
}

/// Absolute URL of the per-recap `og:image` PNG. Note that this one DOES sit
/// under `/og/<entity>/` like the rest of the family even though the share
/// page above does not — the two paths are independent and flattening either
/// onto the other's shape 404s.
export function buildRecapOgImageUrl(
	base: string | null | undefined,
	id: string,
): string {
	return `${normaliseSiteUrl(base)}/og/recap/${id}.png`;
}

export interface ShareRecapMetaInput {
	id: string;
	recap: SharedRecap | null;
	siteUrl: string;
}

export interface ShareRecapMeta {
	title: string;
	description: string;
	ogUrl: string;
	ogImageUrl: string;
}

export function buildShareRecapMeta(input: ShareRecapMetaInput): ShareRecapMeta {
	const { id, recap, siteUrl } = input;
	const base = siteUrl.replace(/\/$/, '');
	let title = 'Year in running — Threkir';
	let description = 'A year-in-running recap on Threkir.';
	if (recap) {
		const period = recapPeriodLabel(recap.periodKind, recap.periodKey);
		const name = recap.displayName?.trim();
		title = name
			? `${name}'s ${period} in running — Threkir`
			: `${period} in running — Threkir`;
		description = `A year-in-running recap for ${period} — total distance, longest run, best streak and more on Threkir.`;
	}
	return {
		title,
		description,
		ogUrl: buildRecapShareCanonical(base, id),
		ogImageUrl: buildRecapOgImageUrl(base, id),
	};
}

/// Render the `<head>` tags the share-recap Lambda injects into the SPA
/// shell. Each value is HTML-attribute-escaped so a malicious display name
/// can't break out of the `content=` attribute.
export function renderShareRecapHeadTags(meta: ShareRecapMeta): string {
	const e = escapeHtml;
	return [
		`<title>${escapeHtml(meta.title)}</title>`,
		`<meta name="description" content="${e(meta.description)}">`,
		`<meta property="og:title" content="${e(meta.title)}">`,
		`<meta property="og:description" content="${e(meta.description)}">`,
		`<meta property="og:type" content="article">`,
		`<meta property="og:url" content="${e(meta.ogUrl)}">`,
		`<meta property="og:image" content="${e(meta.ogImageUrl)}">`,
		`<meta property="og:image:width" content="1200">`,
		`<meta property="og:image:height" content="630">`,
		`<meta property="og:site_name" content="Threkir">`,
		`<meta name="twitter:card" content="summary_large_image">`,
		`<meta name="twitter:title" content="${e(meta.title)}">`,
		`<meta name="twitter:description" content="${e(meta.description)}">`,
		`<meta name="twitter:image" content="${e(meta.ogImageUrl)}">`,
	].join('\n\t');
}

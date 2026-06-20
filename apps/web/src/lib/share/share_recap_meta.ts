/// Per-recap `<head>` meta-tag builder for the public recap share page.
/// Pure string helpers — shared between the SvelteKit +page.svelte
/// (dev-server SSR via $lib reads) and the production share-recap Lambda
/// (which injects these into the SPA-shell HTML). Kept in apps/web/src/lib
/// so the Lambda build pulls it without dragging in $env / SvelteKit-only
/// modules. Mirrors share_run_meta.ts.

import type { SharedRecap } from './share_recap_lookup';
import { recapPeriodLabel } from './recap_period_label';
import { escapeHtml } from '../util/html_escape';

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
		ogUrl: `${base}/recap/share/${id}`,
		ogImageUrl: `${base}/og/recap/${id}.png`,
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

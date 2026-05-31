/// Per-run `<head>` meta-tag builder for the share-run page.
/// Pure string helpers — shared between the SvelteKit +page.svelte
/// (dev-server SSR) and the production share-run Lambda (which
/// injects these into the SPA-shell HTML).
///
/// Persona-hunt finding Casual #4. Kept in apps/web/src/lib so the
/// Lambda build can pull this and the related helpers from a single
/// tree without dragging in $env or SvelteKit-only modules.

import { buildRunShareTitle, buildRunShareDescription } from './share_meta';
import type { SharedRun } from './share_run_lookup';

/// Public site origin used as the `og:url` base. Read from
/// `PUBLIC_SITE_URL` env var with a `https://threkir.com` fallback so
/// the Lambda has a sane default even if the env var is missed at
/// deploy time. Pure here — caller passes the resolved string.
export interface ShareRunMetaInput {
	id: string;
	run: SharedRun | null;
	displayName: string | null;
	siteUrl: string;
}

export interface ShareRunMeta {
	title: string;
	description: string;
	ogUrl: string;
	ogImageUrl: string;
}

export function buildShareRunMeta(input: ShareRunMetaInput): ShareRunMeta {
	const { id, run, displayName, siteUrl } = input;
	const base = siteUrl.replace(/\/$/, '');
	const runMeta = run
		? {
				distance_m: run.distance_m,
				started_at: run.started_at,
				title: typeof run.metadata?.title === 'string' ? run.metadata.title : null,
			}
		: null;
	const title = buildRunShareTitle(runMeta, displayName);
	const description = buildRunShareDescription(runMeta, displayName);
	return {
		title,
		description,
		ogUrl: `${base}/share/run/${id}`,
		ogImageUrl: `${base}/og/run/${id}.png`,
	};
}

/// Render the `<head>` tags that the share-run Lambda injects into the
/// SPA shell. Output is a single string — caller is responsible for
/// finding the right insertion point in the index.html template.
/// Each value is HTML-attribute-escaped so a malicious display_name or
/// run id can't break out of the attribute (the `content=` value is
/// the realistic injection surface).
export function renderShareRunHeadTags(meta: ShareRunMeta): string {
	const e = htmlAttrEscape;
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

function htmlAttrEscape(s: string): string {
	return s
		.replace(/&/g, '&amp;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&#39;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;');
}

function escapeHtml(s: string): string {
	return s
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;');
}

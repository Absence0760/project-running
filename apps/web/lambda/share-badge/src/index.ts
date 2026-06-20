// AWS Lambda Function URL handler for the share-badge surface.
//
// Owns two paths, both routed to this Lambda's Function URL by CloudFront
// (mirror the share-run behaviours in infra/modules/web-stack/main.tf):
//   - /share/badge/<id>     per-badge SPA-shell HTML with OG tags
//   - /og/badge/<id>.png    per-badge og:image PNG
//
// Both render at request time so a badge earned after the last build still
// unfurls with the right per-badge head + a matching image. Same fail-open
// posture as share-run: a private / missing badge yields a 404 HTML (clean
// crawler signal) but a 200 generic-card PNG (an unfurl image must never 404).

import type { LambdaFunctionURLEvent, LambdaFunctionURLResult } from 'aws-lambda';

import { lookupSharedBadge } from '../../../src/lib/share/share_badge_lookup';
import { buildShareBadgeMeta } from '../../../src/lib/share/share_badge_meta';
import { injectShareRunMeta } from '../../../src/lib/share/share_run_spa_shell';
import { renderBadgeOgPng } from '../../../src/lib/share/og_badge_png';

declare const __SPA_SHELL_HTML__: string;

const CACHE_CONTROL = 'public, max-age=300, s-maxage=300, stale-while-revalidate=60';

const HTML_PATH_RE = /^\/share\/badge\/([^/]+)\/?$/;
const PNG_PATH_RE = /^\/og\/badge\/([^/]+)\.png$/;

export const handler = async (
	event: LambdaFunctionURLEvent,
): Promise<LambdaFunctionURLResult> => {
	try {
		const supabaseUrl = process.env.PUBLIC_SUPABASE_URL ?? '';
		const supabaseAnonKey = process.env.PUBLIC_SUPABASE_ANON_KEY ?? '';
		const siteUrl = process.env.PUBLIC_SITE_URL ?? 'https://threkir.com';

		const path = event.rawPath || '/';
		const htmlMatch = path.match(HTML_PATH_RE);
		if (htmlMatch) {
			return await handleHtml(htmlMatch[1], { supabaseUrl, supabaseAnonKey, siteUrl });
		}
		const pngMatch = path.match(PNG_PATH_RE);
		if (pngMatch) {
			return await handlePng(pngMatch[1], { supabaseUrl, supabaseAnonKey });
		}
		return jsonResponse(404, { error: 'not found' });
	} catch (err) {
		console.error('[share-badge lambda] unhandled_error', {
			path: event.rawPath,
			message: err instanceof Error ? err.message : String(err),
			stack: err instanceof Error ? err.stack : undefined,
		});
		return jsonResponse(503, { error: 'temporarily unavailable' });
	}
};

interface HtmlConfig {
	supabaseUrl: string;
	supabaseAnonKey: string;
	siteUrl: string;
}

async function handleHtml(id: string, config: HtmlConfig): Promise<LambdaFunctionURLResult> {
	const lookup = await lookupSharedBadge(id, {
		supabaseUrl: config.supabaseUrl,
		supabaseAnonKey: config.supabaseAnonKey,
	});
	if (!lookup.badge) {
		return {
			statusCode: 404,
			headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': CACHE_CONTROL },
			body: notFoundHtml(),
		};
	}
	const meta = buildShareBadgeMeta({
		id,
		badge: lookup.badge,
		displayName: lookup.displayName,
		siteUrl: config.siteUrl,
	});
	const body = injectShareRunMeta(__SPA_SHELL_HTML__, meta);
	return {
		statusCode: 200,
		headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': CACHE_CONTROL },
		body,
	};
}

async function handlePng(
	id: string,
	config: { supabaseUrl: string; supabaseAnonKey: string },
): Promise<LambdaFunctionURLResult> {
	const png = await renderBadgeOgPng(
		id,
		config.supabaseUrl && config.supabaseAnonKey
			? { supabaseUrl: config.supabaseUrl, supabaseAnonKey: config.supabaseAnonKey }
			: null,
	);
	return {
		statusCode: 200,
		isBase64Encoded: true,
		headers: { 'content-type': 'image/png', 'cache-control': CACHE_CONTROL },
		body: png.toString('base64'),
	};
}

function notFoundHtml(): string {
	return '<!doctype html><html><head><meta charset="utf-8"><title>Achievements — Threkir</title><meta name="robots" content="noindex"></head><body><p>This badge isn’t available.</p></body></html>';
}

function jsonResponse(statusCode: number, body: unknown): LambdaFunctionURLResult {
	return {
		statusCode,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body),
	};
}

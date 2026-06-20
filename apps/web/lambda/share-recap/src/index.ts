// AWS Lambda Function URL handler for the share-recap surface.
//
// Owns two paths, both routed to this Lambda's Function URL by CloudFront
// (see infra/modules/web-stack/main.tf for the behaviours):
//   - /recap/share/<id>     per-recap SPA-shell HTML with OG tags
//   - /og/recap/<id>.png    per-recap og:image PNG
//
// Both render at request time. Under adapter-static the SvelteKit routes
// would otherwise only exist for ids known at build time, so a recap
// published after the last build would serve the generic SPA `<head>` for
// the HTML and a 404 for the PNG — a posted link would unfurl as the
// homepage card with a broken image. This Lambda fetches the frozen snapshot
// + display name per request so every link gets the right per-recap head AND
// a matching image regardless of build cadence. Mirrors the share-run Lambda.
//
// The @resvg native binary is bundled into the zip by build.mjs; the function
// runs on arm64 / Node 24 with 512 MB headroom for the rasteriser.

import type { LambdaFunctionURLEvent, LambdaFunctionURLResult } from 'aws-lambda';

import { lookupSharedRecap } from '../../../src/lib/share/share_recap_lookup';
import {
	buildShareRecapMeta,
	type ShareRecapMeta,
} from '../../../src/lib/share/share_recap_meta';
import { injectShareRecapMeta } from '../../../src/lib/share/share_recap_spa_shell';
import { renderRecapOgPng } from '../../../src/lib/share/og_recap_png';

declare const __SPA_SHELL_HTML__: string;

const CACHE_CONTROL = 'public, max-age=300, s-maxage=300, stale-while-revalidate=60';

const HTML_PATH_RE = /^\/recap\/share\/([^/]+)\/?$/;
const PNG_PATH_RE = /^\/og\/recap\/([^/]+)\.png$/;

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
		console.error('[share-recap lambda] unhandled_error', {
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

async function handleHtml(
	id: string,
	config: HtmlConfig,
): Promise<LambdaFunctionURLResult> {
	const { recap } = await lookupSharedRecap(id, {
		supabaseUrl: config.supabaseUrl,
		supabaseAnonKey: config.supabaseAnonKey,
	});
	if (!recap) {
		return {
			statusCode: 404,
			headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': CACHE_CONTROL },
			body: notFoundHtml(),
		};
	}
	const meta: ShareRecapMeta = buildShareRecapMeta({ id, recap, siteUrl: config.siteUrl });
	const body = injectShareRecapMeta(__SPA_SHELL_HTML__, meta);
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
	// renderRecapOgPng renders a generic branded card when the recap can't be
	// loaded (never published / revoked / never existed), so this always
	// resolves to a valid PNG and returns 200 — an unfurl must never break.
	const png = await renderRecapOgPng(
		id,
		config.supabaseUrl && config.supabaseAnonKey
			? { supabaseUrl: config.supabaseUrl, supabaseAnonKey: config.supabaseAnonKey }
			: null,
	);
	return {
		statusCode: 200,
		headers: { 'content-type': 'image/png', 'cache-control': CACHE_CONTROL },
		isBase64Encoded: true,
		body: png.toString('base64'),
	};
}

function jsonResponse(statusCode: number, body: unknown): LambdaFunctionURLResult {
	return {
		statusCode,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body),
	};
}

function notFoundHtml(): string {
	return [
		'<!DOCTYPE html>',
		'<html lang="en"><head><meta charset="utf-8">',
		'<title>Recap not found — Threkir</title>',
		'<meta name="robots" content="noindex">',
		'</head><body><h1>Recap not found</h1>',
		'<p>This share link is no longer available.</p>',
		'</body></html>',
	].join('\n');
}

// AWS Lambda Function URL handler for the share-route surface.
//
// Owns two paths, both routed to this Lambda's Function URL by
// CloudFront (see infra/modules/web-stack/main.tf for the behaviours):
//   - /share/route/<id>     per-route SPA-shell HTML with OG + JSON-LD
//   - /og/route/<id>.png    per-route og:image PNG (privacy-clipped track)
//
// Both are rendered at request time. Pre-fix, both were prerendered at
// build time via adapter-static with a 5k cap; a route made public
// post-build (or beyond the cap) served the SPA-shell fallback `<head>`
// (generic "Threkir" title, no per-route OG) and a 404 og:image until
// the next deploy, and a public→private flip stayed served from S3
// until overwritten. This Lambda fetches the route + clipped track at
// request time so every URL gets the right OG head AND a matching
// image, regardless of build cadence. Symmetric mirror of the
// share-run Lambda (persona Casual #4 + round-5 very-social).
//
// The @resvg native binary is bundled into the Lambda zip by
// build.mjs (esbuild keeps the `.node` arm64 addon as an asset); the
// function runs on arm64 / Node 24 with 512 MB to give the rasteriser
// headroom.

import type { LambdaFunctionURLEvent, LambdaFunctionURLResult } from 'aws-lambda';

import { lookupSharedRoute } from '../../../src/lib/share/share_route_lookup';
import {
	buildShareRouteHead,
	type ShareRouteHead,
} from '../../../src/lib/share/share_route_meta';
import { injectShareRouteMeta } from '../../../src/lib/share/share_route_spa_shell';
import { renderRouteOgPng } from '../../../src/lib/share/og_route_png';

// SPA-shell HTML embedded at build time by lambda/share-route/build.mjs.
// The bundler substitutes `__SPA_SHELL_HTML__` with the contents of
// `apps/web/build/index.html` so the Lambda has the exact SvelteKit
// fallback that S3 would otherwise serve. Each web release rebuilds
// the Lambda artifact so the embedded shell stays in lockstep with
// the deployed bundle.
declare const __SPA_SHELL_HTML__: string;

// 5-min CloudFront cache + 60s stale-while-revalidate. Matches the
// share-run Lambda's TTL: a public→private flip must propagate to the
// OG unfurl within minutes, not the previous hours-long window. The
// CloudFront cache policy's default_ttl/max_ttl are pinned to 300 to
// match — either ceiling clamps the stale window.
const CACHE_CONTROL =
	'public, max-age=300, s-maxage=300, stale-while-revalidate=60';

const HTML_PATH_RE = /^\/share\/route\/([^/]+)\/?$/;
const PNG_PATH_RE = /^\/og\/route\/([^/]+)\.png$/;

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
			return await handleHtml(htmlMatch[1], {
				supabaseUrl,
				supabaseAnonKey,
				siteUrl,
			});
		}

		const pngMatch = path.match(PNG_PATH_RE);
		if (pngMatch) {
			return await handlePng(pngMatch[1], { supabaseUrl, supabaseAnonKey });
		}

		// Anything else routed to this Lambda is a misconfiguration
		// (CloudFront behaviour should never send us paths other than
		// the patterns above). Return a 404 rather than guess.
		return jsonResponse(404, { error: 'not found' });
	} catch (err) {
		console.error('[share-route lambda] unhandled_error', {
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
	// withTrack: false — the <head> meta only needs the route's name +
	// distance + surface; the clipped track is the PNG path's concern.
	const lookup = await lookupSharedRoute(
		id,
		{ supabaseUrl: config.supabaseUrl, supabaseAnonKey: config.supabaseAnonKey },
		{ withTrack: false },
	);
	// 404 for routes that don't exist or aren't public. A human who
	// follows the link gets the not-found shell; crawlers get a clean
	// signal. Same short TTL as the 200 path — a route flipping public
	// must un-404 within the same propagation window as a public→private
	// flip stales the existing unfurl.
	if (!lookup.route) {
		return {
			statusCode: 404,
			headers: {
				'content-type': 'text/html; charset=utf-8',
				'cache-control': CACHE_CONTROL,
			},
			body: notFoundHtml(),
		};
	}
	const head: ShareRouteHead = buildShareRouteHead({
		id,
		route: lookup.route,
		siteUrl: config.siteUrl,
	});
	const body = injectShareRouteMeta(__SPA_SHELL_HTML__, head);
	return {
		statusCode: 200,
		headers: {
			'content-type': 'text/html; charset=utf-8',
			'cache-control': CACHE_CONTROL,
		},
		body,
	};
}

async function handlePng(
	id: string,
	config: { supabaseUrl: string; supabaseAnonKey: string },
): Promise<LambdaFunctionURLResult> {
	// renderRouteOgPng renders a generic branded card when the route
	// can't be loaded (private / deleted / never existed), so this
	// always resolves to a valid PNG and we return 200 — a social
	// unfurl must never break with a 404 image.
	const png = await renderRouteOgPng(
		id,
		config.supabaseUrl && config.supabaseAnonKey
			? {
					supabaseUrl: config.supabaseUrl,
					supabaseAnonKey: config.supabaseAnonKey,
				}
			: null,
	);
	return {
		statusCode: 200,
		headers: {
			'content-type': 'image/png',
			'cache-control': CACHE_CONTROL,
		},
		// Function URL binary responses must be base64-encoded.
		isBase64Encoded: true,
		body: png.toString('base64'),
	};
}

function jsonResponse(
	statusCode: number,
	body: unknown,
): LambdaFunctionURLResult {
	return {
		statusCode,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body),
	};
}

function notFoundHtml(): string {
	// Minimal not-found shell. Doesn't try to load the SPA bundle — the
	// route doesn't exist, so loading the SPA would just render its own
	// 404. Generic title so the crawler's unfurl is honest.
	return [
		'<!DOCTYPE html>',
		'<html lang="en"><head><meta charset="utf-8">',
		'<title>Route not found — Threkir</title>',
		'<meta name="robots" content="noindex">',
		'</head><body><h1>Route not found</h1>',
		'<p>This share link is no longer available.</p>',
		'</body></html>',
	].join('\n');
}

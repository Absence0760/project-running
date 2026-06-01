// AWS Lambda Function URL handler for the share-run surface.
//
// Owns two paths, both routed to this Lambda's Function URL by
// CloudFront (see infra/modules/web-stack/main.tf for the behaviours):
//   - /share/run/<id>     per-run SPA-shell HTML with OG tags
//   - /og/run/<id>.png    per-run og:image PNG
//
// Both are rendered at request time. Pre-fix, both were prerendered
// at build time via adapter-static with a 50k cap; a public run
// created post-build (or beyond the cap) served the SPA-shell
// fallback `<head>` for the HTML and a 404 for the PNG, so Slack /
// FB / X / LinkedIn unfurls of a brand-new share showed the homepage
// card with a broken image. This Lambda fetches the run + display
// name at request time so every URL gets the right per-run head AND
// a matching image, regardless of build cadence. Persona-hunt
// finding Casual #4 (HTML) + round-5 very-social (PNG).
//
// The @resvg native binary is bundled into the Lambda zip by
// build.mjs (esbuild keeps the `.node` arm64 addon as an asset); the
// function runs on arm64 / Node 24 with 512 MB to give the
// rasteriser headroom.

import type { LambdaFunctionURLEvent, LambdaFunctionURLResult } from 'aws-lambda';

import { lookupSharedRun } from '../../../src/lib/share/share_run_lookup';
import {
	buildShareRunMeta,
	type ShareRunMeta,
} from '../../../src/lib/share/share_run_meta';
import { injectShareRunMeta } from '../../../src/lib/share/share_run_spa_shell';
import { renderRunOgPng } from '../../../src/lib/share/og_run_png';

// SPA-shell HTML embedded at build time by lambda/share-run/build.mjs.
// The bundler substitutes `__SPA_SHELL_HTML__` with the contents of
// `apps/web/build/index.html` so the Lambda has the exact SvelteKit
// fallback that S3 would otherwise serve. Each web release rebuilds
// the Lambda artifact so the embedded shell stays in lockstep with
// the deployed bundle.
declare const __SPA_SHELL_HTML__: string;

// 5-min CloudFront cache + 60s stale-while-revalidate. Trades a bit
// of crawler-storm protection for fast-propagating visibility flips —
// persona-hunt Round 3 finding Privacy #3. Pre-fix the 1h TTL meant a
// public→private flip still surfaced the OG unfurl for up to an hour
// after the user had hidden the run; the same window applied to a
// new public run waiting for the unfurl to appear. 5 min + SWR keeps
// the Lambda invocation cost bounded (one call every ~5 min per hot
// URL, with the prior response served for the next 60 s while the
// revalidation completes) while bringing the worst-case stale-image
// window down by 12x.
const CACHE_CONTROL =
	'public, max-age=300, s-maxage=300, stale-while-revalidate=60';

const HTML_PATH_RE = /^\/share\/run\/([^/]+)\/?$/;
const PNG_PATH_RE = /^\/og\/run\/([^/]+)\.png$/;

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
		console.error('[share-run lambda] unhandled_error', {
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
	const lookup = await lookupSharedRun(id, {
		supabaseUrl: config.supabaseUrl,
		supabaseAnonKey: config.supabaseAnonKey,
	});
	// 404 for runs that don't exist or aren't public. The browser
	// will fall back to the SPA's 404 surface if a human follows the
	// link; crawlers get a clean signal. Same short TTL as the 200
	// path — a brand-new run flipping public must un-404 within the
	// same propagation window as a public→private flip stales the
	// existing unfurl. Persona-hunt Round 3 finding Privacy #3.
	if (!lookup.run) {
		return {
			statusCode: 404,
			headers: {
				'content-type': 'text/html; charset=utf-8',
				'cache-control': CACHE_CONTROL,
			},
			body: notFoundHtml(),
		};
	}
	const meta: ShareRunMeta = buildShareRunMeta({
		id,
		run: lookup.run,
		displayName: lookup.displayName,
		siteUrl: config.siteUrl,
	});
	const body = injectShareRunMeta(__SPA_SHELL_HTML__, meta);
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
	// renderRunOgPng renders a generic branded card when the run can't
	// be loaded (private / deleted / never existed), so this always
	// resolves to a valid PNG and we return 200 — a social unfurl must
	// never break with a 404 image. Persona-hunt round-5 very-social.
	const png = await renderRunOgPng(
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
	// Minimal not-found shell. Doesn't try to load the SPA bundle —
	// the route doesn't exist, so loading the SPA would just render
	// its own 404. Generic title so the crawler's unfurl is honest.
	return [
		'<!DOCTYPE html>',
		'<html lang="en"><head><meta charset="utf-8">',
		'<title>Run not found — Threkir</title>',
		'<meta name="robots" content="noindex">',
		'</head><body><h1>Run not found</h1>',
		'<p>This share link is no longer available.</p>',
		'</body></html>',
	].join('\n');
}

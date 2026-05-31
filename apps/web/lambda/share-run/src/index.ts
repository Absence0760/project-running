// AWS Lambda Function URL handler for the share-run surface.
//
// Owns /share/run/<id> (per-run SPA-shell HTML with OG tags).
// CloudFront routes that path to this Lambda's Function URL — see
// infra/modules/web-stack/main.tf for the behaviour.
//
// /og/run/<id>.png stays adapter-static-prerendered at build time
// with a 50k cap (apps/web/src/routes/og/run/[id].png/+server.ts).
// Rendering PNGs in this Lambda would require shipping the @resvg
// native arm64 binary as a Lambda Layer or via a build-time install
// with `--arch=arm64 --platform=linux`; that's a separate slice
// without enough product impact to fold in here. The realistic
// failure mode for an over-cap run is og:image returning 404 —
// crawlers degrade to no-image unfurls but the per-run title +
// description (from THIS Lambda) still land correctly. The HTML
// fix is the critical-path fix; the missing image is cosmetic.
//
// Persona-hunt finding Casual #4. Pre-fix, the HTML route was
// prerendered at build time; a public run created post-build served
// the SPA-shell fallback `<head>` (generic title) so Slack / FB / X
// / LinkedIn unfurls of a brand-new share showed the homepage card.
// This Lambda fetches the run + display name at request time so
// every URL gets the right per-run head, regardless of build cadence.

import type { LambdaFunctionURLEvent, LambdaFunctionURLResult } from 'aws-lambda';

import { lookupSharedRun } from '../../../src/lib/share/share_run_lookup';
import {
	buildShareRunMeta,
	type ShareRunMeta,
} from '../../../src/lib/share/share_run_meta';
import { injectShareRunMeta } from '../../../src/lib/share/share_run_spa_shell';

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

		// Anything else routed to this Lambda is a misconfiguration
		// (CloudFront behaviour should never send us paths other than
		// the pattern above). Return a 404 rather than guess.
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

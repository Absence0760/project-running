// AWS Lambda Function URL handler for the "Generate a route by distance"
// endpoint.
//
// Production entry point for `/api/routes/generate` — CloudFront routes that
// path to this Lambda's Function URL (see infra/modules/web-stack/main.tf and
// decisions §53). The transport-agnostic core lives at
// `apps/web/src/lib/routes/generate/handler.ts` and is also wrapped (for dev
// only) by the SvelteKit `+server.ts`. This file:
//   1. Parses the Function-URL event body (string, maybe base64).
//   2. Reads GRAPHHOPPER_URL from process.env (Terraform sets it).
//   3. Calls the shared core, which fans out round_trip seeds to the
//      self-hosted GraphHopper engine and returns a finished loop polyline.
//
// Non-streaming JSON (unlike the coach Lambda) — the response is one small
// GeoJSON line, so the simple LambdaFunctionURLResult shape is enough.

import type { LambdaFunctionURLEvent, LambdaFunctionURLResult } from 'aws-lambda';
import { Buffer } from 'node:buffer';
import { handleGenerate } from '../../../src/lib/routes/generate/handler';

// Bound on the inbound body — only a coordinate + distance + optional seed
// count, a few dozen bytes. Mirrors the dev wrapper's cap.
const BODY_LIMIT_BYTES = 4 * 1024;

function json(statusCode: number, body: unknown): LambdaFunctionURLResult {
	return {
		statusCode,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body),
	};
}

export const handler = async (
	event: LambdaFunctionURLEvent,
): Promise<LambdaFunctionURLResult> => {
	// Outer fail-closed envelope (mirrors the coach Lambda Medium #6 fix): any
	// unexpected throw becomes a generic 503 to the wire and a tagged operator
	// log line, never the runtime's default error envelope.
	try {
		const raw = event.body ?? '';
		const decoded = event.isBase64Encoded === true ? Buffer.from(raw, 'base64') : Buffer.from(raw, 'utf-8');
		if (decoded.byteLength > BODY_LIMIT_BYTES) {
			return json(413, { error: 'request body too large' });
		}
		let rawBody: unknown;
		try {
			const text = decoded.toString('utf-8');
			rawBody = text.length === 0 ? null : JSON.parse(text);
		} catch {
			return json(400, { error: 'invalid JSON' });
		}

		const result = await handleGenerate(rawBody, {
			graphhopperUrl: process.env.GRAPHHOPPER_URL,
			graphhopperApiKey: process.env.GRAPHHOPPER_API_KEY,
			// OSRM for the polygon-loop generator (tried first when set), parity
			// with the SvelteKit wrapper: OSRM_URL override else PUBLIC_OSRM_URL.
			osrmUrl: process.env.OSRM_URL || process.env.PUBLIC_OSRM_URL,
		});
		if (result.status === 502) {
			// Engine unreachable / failing. A 502 here is a CLEAN handled
			// response, not a Lambda throw, so the Errors metric never sees
			// it — without this tagged line a GraphHopper outage silently
			// degrades every user to the OSRM fallback and no operator is
			// paged. The engine-unreachable CloudWatch alarm keys off it.
			console.error('[generate-route] engine_unreachable');
		}
		return json(result.status, result.body);
	} catch (e) {
		console.error('[generate-route lambda] unhandled_error', {
			message: e instanceof Error ? e.message : String(e),
			stack: e instanceof Error ? e.stack : undefined,
		});
		return json(503, { error: 'route generation is temporarily unavailable' });
	}
};

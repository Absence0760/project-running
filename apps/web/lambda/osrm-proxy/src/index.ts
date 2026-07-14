// AWS Lambda Function URL handler for the OSRM waypoint-routing proxy.
//
// Production entry point for `/api/routes/osrm/*` — CloudFront routes that
// path to this Lambda's Function URL (see infra/modules/web-stack/main.tf and
// decisions §242). The transport-agnostic core lives at
// `apps/web/src/lib/routes/osrm_proxy/handler.ts` and is also wrapped (for
// dev only) by the SvelteKit `+server.ts`. This file:
//   1. Strips the `/api/routes/osrm` prefix off the Function-URL event path
//      and hands the OSRM-shaped remainder + query params to the core.
//   2. Reads OSRM_URL (server-only — the whole point of the proxy, issue
//      #198) plus PUBLIC_SUPABASE_URL + PUBLIC_SUPABASE_ANON_KEY for the
//      auth gate from process.env (Terraform sets them).
//   3. Hard-codes `allowDemoFallback: false`: production must never leak
//      user waypoints to the uncontracted router.project-osrm.org demo, so
//      an unset OSRM_URL answers 501 here. The viewer JWT arrives in
//      `x-supabase-authorization` — CloudFront's OAC owns `Authorization`
//      for its sigv4 signature, so the client JWT rides the custom header.
//
// Non-streaming JSON (like generate-route) — the response is one OSRM JSON
// document, so the simple LambdaFunctionURLResult shape is enough.

import type { LambdaFunctionURLEvent, LambdaFunctionURLResult } from 'aws-lambda';
import { handleOsrmProxy } from '../../../src/lib/routes/osrm_proxy/handler';

const PATH_PREFIX = '/api/routes/osrm';

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
	// Outer fail-closed envelope (mirrors the generate-route Lambda): any
	// unexpected throw becomes a generic 503 to the wire and a tagged operator
	// log line, never the runtime's default error envelope.
	try {
		if (event.requestContext.http.method !== 'GET') {
			return json(405, { error: 'method not allowed' });
		}
		const rawPath = event.rawPath ?? '';
		if (!rawPath.startsWith(PATH_PREFIX)) {
			return json(400, { error: 'unsupported OSRM path' });
		}

		const result = await handleOsrmProxy(
			event.headers?.['x-supabase-authorization'] ??
				event.headers?.['X-Supabase-Authorization'] ??
				null,
			rawPath.slice(PATH_PREFIX.length),
			event.queryStringParameters ?? {},
			{
				osrmUrl: process.env.OSRM_URL,
				allowDemoFallback: false,
				// Missing envs fail closed inside the handler (500 auth-check
				// error), so a partial Terraform apply can't skip the gate.
				publicSupabaseUrl: process.env.PUBLIC_SUPABASE_URL ?? '',
				publicSupabaseAnonKey: process.env.PUBLIC_SUPABASE_ANON_KEY ?? '',
			},
		);
		if (result.status === 502) {
			// Engine unreachable / failing. A 502 here is a CLEAN handled
			// response, not a Lambda throw, so the Errors metric never sees it —
			// this tagged line is what the engine-unreachable CloudWatch alarm
			// keys off, mirroring generate-route.
			console.error('[osrm-proxy] engine_unreachable');
		}
		return json(result.status, result.body);
	} catch (e) {
		console.error('[osrm-proxy lambda] unhandled_error', {
			message: e instanceof Error ? e.message : String(e),
			stack: e instanceof Error ? e.stack : undefined,
		});
		return json(503, { error: 'waypoint routing is temporarily unavailable' });
	}
};

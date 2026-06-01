// AWS Lambda Function URL handler for the coach endpoint.
//
// This is the production entry point for `/api/coach/*` — CloudFront
// routes that path to this Lambda's Function URL (see
// `apps/web/deployment.md` and decisions.md § 53).
//
// The transport-agnostic core lives at `apps/web/src/lib/coach/handler.ts`
// and is also wrapped (for dev only) by the SvelteKit `+server.ts`.
// This file:
//   1. Parses the API Gateway-shaped event from Function URL.
//   2. Reads runtime config from process.env (Terraform sets it from the
//      sops-encrypted file).
//   3. Calls the shared core.
//   4. Adapts the result to Lambda response streaming via
//      `awslambda.streamifyResponse` + `awslambda.HttpResponseStream`.

import type { LambdaFunctionURLEvent } from 'aws-lambda';
import { Buffer } from 'node:buffer';
import { handleCoach } from '../../../src/lib/coach/handler';
import type { CoachConfig } from '../../../src/lib/coach/types';

// Provided by the Node.js managed Lambda runtime; declared inline
// because @types/aws-lambda doesn't ship a definition for it (the API
// is Lambda-specific, not part of node:* or AWS SDK).
declare const awslambda: {
	streamifyResponse: <E>(
		handler: (event: E, responseStream: ResponseStream, context: unknown) => Promise<void>,
	) => unknown;
	HttpResponseStream: {
		from(
			responseStream: ResponseStream,
			metadata: { statusCode: number; headers?: Record<string, string> },
		): ResponseStream;
	};
};

interface ResponseStream {
	write(chunk: string | Uint8Array): boolean;
	end(): void;
	setContentType?: (ct: string) => void;
}

// Body decoder + byte-count limit. Single source of truth shared with
// the SvelteKit dev wrapper (apps/web/src/routes/api/coach/+server.ts)
// so the two surfaces can't drift on size enforcement.
import {
	decodeLambdaBody,
	COACH_BODY_LIMIT_BYTES,
} from '../../../src/lib/coach/body';

export const handler = awslambda.streamifyResponse<LambdaFunctionURLEvent>(
	async (event, responseStream) => {
	// Outer fail-closed envelope. Audit/coach May 2026 Medium #6 —
	// a `requireEnv` throw (or any other unexpected error inside the
	// streamifyResponse body) used to bubble up to the Lambda runtime
	// and surface in the 502 response with the runtime's default
	// error envelope, leaking the env-var name to the wire. Wrap the
	// whole handler so the operator-facing error stays in the logs
	// while the client gets a generic 503.
	try {
		const provider = (process.env.COACH_PROVIDER ?? 'anthropic').toLowerCase();
		if (provider !== 'anthropic' && provider !== 'openai') {
			console.error(`[coach lambda] invalid COACH_PROVIDER value: '${provider}'`);
			writeJson(responseStream, 503, { error: 'Coach is not configured.' });
			return;
		}

		// Parse the request body. Function URL events deliver `body` as
		// a string, base64-encoded for binary content types. The size
		// cap is enforced against the decoded byte count, not the JS
		// string length — see $lib/coach/body.ts for the regression
		// this guards against (multi-byte UTF-8 chars).
		const decoded = decodeLambdaBody(
			event.body,
			event.isBase64Encoded === true,
			COACH_BODY_LIMIT_BYTES,
		);
		if (!decoded.ok) {
			writeJson(responseStream, decoded.status, { error: decoded.error });
			return;
		}
		let rawBody: unknown;
		try {
			rawBody = decoded.body ? JSON.parse(decoded.body) : null;
		} catch {
			writeJson(responseStream, 400, { error: 'invalid JSON' });
			return;
		}

		// The user's Supabase JWT is passed in `X-Supabase-Authorization`,
		// not `Authorization`. CloudFront's Lambda OAC sigv4-signs every
		// origin request in the `Authorization` header — forwarding the
		// viewer's `Authorization` would collide with that signature and
		// break IAM auth on the Function URL.
		const authHeader =
			event.headers?.['x-supabase-authorization'] ??
			event.headers?.['X-Supabase-Authorization'] ??
			null;

		// BYPASS_PAYWALL is a dev-only escape hatch, never honoured in
		// the production Lambda. Hard-coding `false` here is the
		// belt-and-braces defence even if BYPASS_PAYWALL leaked into
		// the Lambda env.
		const config: CoachConfig = {
			provider,
			anthropicApiKey: process.env.ANTHROPIC_API_KEY,
			openaiBaseUrl: process.env.OPENAI_BASE_URL,
			openaiApiKey: process.env.OPENAI_API_KEY,
			openaiModel: process.env.OPENAI_MODEL,
			publicSupabaseUrl: requireEnv('PUBLIC_SUPABASE_URL'),
			publicSupabaseAnonKey: requireEnv('PUBLIC_SUPABASE_ANON_KEY'),
			// Used only to persist the assistant message (handler.ts):
			// since migration 20261122_001 the coach_messages INSERT policy
			// confines the user-JWT client to role='user' rows, so the
			// assistant turn needs an RLS-bypassing writer. Provisioned via
			// the env's sops secrets file (see infra/modules/web-stack).
			supabaseServiceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
			bypassPaywallEnabled: false,
		};

		const result = await handleCoach(authHeader, rawBody, config);

		if (result.kind === 'json') {
			const stream = awslambda.HttpResponseStream.from(responseStream, {
				statusCode: result.status,
				headers: result.headers,
			});
			stream.write(result.body);
			stream.end();
			return;
		}

		const stream = awslambda.HttpResponseStream.from(responseStream, {
			statusCode: result.status,
			headers: result.headers,
		});
		try {
			for await (const chunk of result.body) {
				stream.write(Buffer.from(chunk));
			}
		} catch (e) {
			console.error('[coach lambda] stream pump failed', e);
		} finally {
			stream.end();
		}
	} catch (e) {
		// Outer envelope from the audit/coach Medium #6 fix. Anything
		// that escapes the inner handler path (env-var throws, JSON
		// parse anomalies, native module load failures) becomes a
		// generic 503 to the client and a tagged log line on the
		// operator side.
		console.error('[coach lambda] unhandled_error', {
			message: e instanceof Error ? e.message : String(e),
			stack: e instanceof Error ? e.stack : undefined,
		});
		try {
			writeJson(responseStream, 503, { error: 'Coach is temporarily unavailable.' });
		} catch (writeErr) {
			console.error('[coach lambda] failed to write 503 envelope', writeErr);
		}
	}
	},
);

function writeJson(responseStream: ResponseStream, status: number, body: unknown): void {
	const stream = awslambda.HttpResponseStream.from(responseStream, {
		statusCode: status,
		headers: { 'content-type': 'application/json' },
	});
	stream.write(JSON.stringify(body));
	stream.end();
}

function requireEnv(name: string): string {
	const v = process.env[name];
	if (!v) throw new Error(`required env var ${name} not set`);
	return v;
}

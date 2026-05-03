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

export const handler = awslambda.streamifyResponse<LambdaFunctionURLEvent>(
	async (event, responseStream) => {
		const provider = (process.env.COACH_PROVIDER ?? 'anthropic').toLowerCase();
		if (provider !== 'anthropic' && provider !== 'openai') {
			writeJson(responseStream, 503, {
				error: `Unknown COACH_PROVIDER='${provider}'. Use 'anthropic' or 'openai'.`,
			});
			return;
		}

		// Parse the request body. Function URL events deliver `body` as
		// a string, base64-encoded for binary content types. JSON is
		// always plain UTF-8.
		let rawBody: unknown;
		try {
			const bodyStr = event.isBase64Encoded
				? Buffer.from(event.body ?? '', 'base64').toString('utf8')
				: (event.body ?? '');
			rawBody = bodyStr ? JSON.parse(bodyStr) : null;
		} catch {
			writeJson(responseStream, 400, { error: 'invalid JSON' });
			return;
		}

		// Function URL header keys are normalised lowercase per the
		// HTTP/2 spec — but the AWS docs caution that case can vary, so
		// check both forms defensively.
		const authHeader =
			event.headers?.['authorization'] ?? event.headers?.['Authorization'] ?? null;

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

// Shared body-decode + size-limit helper for the /api/coach endpoint.
//
// Two wrappers drive the same handler core: the SvelteKit dev server
// (`src/routes/api/coach/+server.ts`) and the production AWS Lambda
// Function URL (`lambda/coach/src/index.ts`). Both must enforce the
// same byte-count limit BEFORE JSON.parse — otherwise an attacker can
// send a gigabyte of nested JSON and crash the worker before the
// limit kicks in.
//
// The historical bug this guards against:
//   `bodyStr.length` counts UTF-16 code units, not bytes. A body of
//   ~85 KB of three-byte UTF-8 characters (U+0800–U+FFFF) reports
//   length ~85K and passes a 256 KB code-unit cap, even though the
//   actual byte size is ~256 KB. We size-check the bytes.

export const COACH_BODY_LIMIT_BYTES = 256 * 1024;

export type BodyDecodeResult =
	| { ok: true; body: string }
	| { ok: false; status: 413; error: 'request too large' }
	| { ok: false; status: 400; error: 'invalid body encoding' };

/**
 * Decode a Lambda Function URL body (base64 or UTF-8 string) into a
 * UTF-8 string, enforcing a byte-count cap before any allocation past
 * the raw input. Returns a 413 sentinel when the cap is exceeded and
 * a 400 sentinel when base64 decoding fails.
 *
 * The limit is checked against the *byte* count of the request payload,
 * not the JS string length — see the module comment above for why.
 */
export function decodeLambdaBody(
	rawBody: string | null | undefined,
	isBase64Encoded: boolean,
	limit: number = COACH_BODY_LIMIT_BYTES,
): BodyDecodeResult {
	const raw = rawBody ?? '';
	let buf: Buffer;
	try {
		buf = isBase64Encoded
			? Buffer.from(raw, 'base64')
			: Buffer.from(raw, 'utf8');
	} catch {
		return { ok: false, status: 400, error: 'invalid body encoding' };
	}
	if (buf.byteLength > limit) {
		return { ok: false, status: 413, error: 'request too large' };
	}
	return { ok: true, body: buf.toString('utf8') };
}

/**
 * Size-check an already-decoded raw byte buffer (the SvelteKit dev
 * wrapper gets the body as an ArrayBuffer from `request.arrayBuffer()`
 * and doesn't go through the base64 path).
 */
export function checkBodyByteLimit(
	bytes: ArrayBuffer | Uint8Array,
	limit: number = COACH_BODY_LIMIT_BYTES,
): { ok: true } | { ok: false; status: 413; error: 'request too large' } {
	const size =
		bytes instanceof ArrayBuffer ? bytes.byteLength : bytes.byteLength;
	if (size > limit) {
		return { ok: false, status: 413, error: 'request too large' };
	}
	return { ok: true };
}

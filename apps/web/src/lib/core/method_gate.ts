/**
 * The 405 every Lambda in this tree answers with, in one place.
 *
 * Eight handlers gate their own method (`security_guards.test.ts` derives that
 * from the directory rather than listing them). The five share ones went
 * through `shareMethodRefusal` from § 1005; the three API ones each spelled the
 * comparison, the status, the `Allow` header and the body inline, and the four
 * copies had already drifted — only the share one sent `cache-control`, so a
 * 405 from `/api/coach` was cacheable by anything between the client and the
 * edge and would have outlived its own fix.
 *
 * What differs per caller is the allowed-method SET and nothing else, so that
 * is the parameter. The response SHAPE differs too — the coach writes through
 * a stream rather than returning an object — which is why this returns the
 * parts rather than a `LambdaFunctionURLResult`: a stream caller passes
 * `statusCode` and `headers` to `HttpResponseStream.from` and writes `body`.
 *
 * `Allow` is required on a 405 (RFC 9110 15.5.6). `no-store` because a refusal
 * is not a document.
 */

export interface MethodRefusal {
	statusCode: number;
	headers: Record<string, string>;
	body: string;
}

/**
 * The 405 to answer with, or null when the method may proceed. Fail-closed: an
 * absent method is refused rather than waved through.
 */
export function methodRefusal(
	method: string | undefined,
	allowed: readonly string[],
): MethodRefusal | null {
	if (method !== undefined && allowed.includes(method)) return null;
	return {
		statusCode: 405,
		headers: {
			'content-type': 'application/json',
			allow: allowed.join(', '),
			'cache-control': 'no-store',
		},
		body: JSON.stringify({ error: 'method not allowed' }),
	};
}

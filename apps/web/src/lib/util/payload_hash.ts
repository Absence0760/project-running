/**
 * Hex SHA-256 of a request body, for the `x-amz-content-sha256` header.
 *
 * CloudFront's Lambda OAC sigv4-signs every origin request but cannot
 * hash a request body it streams through, and OAC-signed Lambda Function
 * URLs reject unsigned payloads — so the CLIENT must supply the payload
 * hash on any request that carries a body, or the Function URL answers
 * 403 before invocation (issue #590 defect 3). Every fetch that POSTs
 * through a CloudFront Lambda behavior (`/api/coach*`,
 * `/api/routes/generate`) must send this header over the exact bytes of
 * the body it posts. GETs carry no body and need nothing. The SvelteKit
 * dev endpoints ignore the header, so dev and prod clients stay
 * identical.
 */
export async function payloadSha256Hex(body: string): Promise<string> {
	const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(body));
	return Array.from(new Uint8Array(digest))
		.map((b) => b.toString(16).padStart(2, '0'))
		.join('');
}

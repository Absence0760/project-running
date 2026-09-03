/**
 * The method gate the five share Lambdas share.
 *
 * These surfaces are crawler-facing documents and images: an unfurl fetches
 * them with GET, a link checker with HEAD, and nothing else has a reason to
 * touch them. Their CloudFront behaviours declare
 * `allowed_methods = ["GET", "HEAD", "OPTIONS"]`, which is what refuses a
 * mutating method at the edge (`share_lambda_handlers.test.ts` pins that list).
 * OPTIONS is the one that gets through, and `cached_methods` is `["GET",
 * "HEAD"]` — so every OPTIONS misses the edge cache, reaches the origin, and on
 * an `/og/*` path runs a full resvg render before answering `200 image/png`
 * (decisions § 972 measured ~50 ms). GET and HEAD are absorbed by the cache
 * after the first; OPTIONS is the only method on these paths that is not, and
 * they are outside every WAF rate-limit rule, which scope `/api/coach`,
 * `/api/routes/generate` and `/api/routes/osrm` only.
 *
 * Nothing can be relying on today's answer. A 200 to a CORS preflight is only
 * useful if it carries `Access-Control-Allow-Origin`, and neither these
 * handlers nor the distribution's response-headers policy emits any
 * `access-control-*` header at all — so a browser preflight against these paths
 * already fails, and a crawler never sends one. Replacing the render with a
 * 405 therefore removes no working behaviour (decisions § 1005).
 *
 * The refusal itself is `core/method_gate`'s, which every Lambda in the tree
 * now answers through; `no-store` matters here because these behaviours are
 * the cached ones, and a cached 405 would outlive a fix.
 */

import { methodRefusal, type MethodRefusal } from '../core/method_gate';

export const SHARE_ALLOWED_METHODS = ['GET', 'HEAD'] as const;

export type ShareMethodRefusal = MethodRefusal;

/** This surface's instantiation of the shared refusal: GET and HEAD, nothing else. */
export function shareMethodRefusal(method: string | undefined): MethodRefusal | null {
	return methodRefusal(method, SHARE_ALLOWED_METHODS);
}

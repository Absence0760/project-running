import type { RequestHandler } from './$types';
import { coachEnabled } from '$lib/coach/coach_flag';
import { routeGenEnabled } from '$lib/routes/route_gen_flag';

// Build-time capability manifest for the native clients. `adapter-static`
// prerenders this once (like /sitemap.xml) into a plain file in `build/`,
// so CloudFront serves it from S3 with no Lambda invocation.
//
// Why it exists: the Pro storefront is only honest when at least one Pro
// perk is actually live, and the two flags that decide that
// (PUBLIC_COACH_ENABLED, PUBLIC_ROUTE_GEN_ENABLED) are web-deploy env —
// baked into the web bundle, invisible to a Flutter binary sitting in the
// App Store. Without a channel the mobile storefront would sell a
// subscription the deploy can't deliver (decisions §466). This endpoint is
// that channel: the SAME two gate functions the /settings/upgrade card
// reads, published as JSON on the origin the app already talks to for
// /api/coach. There is no second flag to keep in sync — flipping the env
// and redeploying web moves both storefronts at once.
//
// Public by construction: both values are already PUBLIC_ flags present in
// the client bundle every visitor downloads. Nothing here is a secret.
//
// The release workflow gives this file the short HTML-style cache-control
// rather than the immutable asset one, so turning a perk off propagates.
export const prerender = true;

export const GET: RequestHandler = () =>
	new Response(
		JSON.stringify({ coach: coachEnabled(), route_gen: routeGenEnabled() }),
		{
			headers: {
				'content-type': 'application/json',
				'cache-control': 'public, max-age=60, must-revalidate',
			},
		},
	);

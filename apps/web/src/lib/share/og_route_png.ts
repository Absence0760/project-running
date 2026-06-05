/// Request-time PNG renderer for /og/route/<id>.png. Shared by the
/// production share-route Lambda (apps/web/lambda/share-route/src/
/// index.ts) and the SvelteKit endpoint (apps/web/src/routes/og/route/
/// [id].png/+server.ts) so the SVG card + the missing-route fallback
/// behave identically in dev and prod. Mirror of og_run_png.ts.
///
/// A route that doesn't resolve (private, deleted, or never existed)
/// renders a generic branded card rather than throwing — the caller
/// returns it with HTTP 200 so a social unfurl never shows a broken
/// image.

import { Resvg } from '@resvg/resvg-js';

import { buildRouteOgSvg } from './og_route_image';
import {
	lookupSharedRoute,
	type SharedRouteLookupConfig,
} from './share_route_lookup';

/// A 1x1 transparent PNG. Last-ditch fallback when the native @resvg
/// rasteriser itself fails (e.g. the `.node` binary can't load on a host,
/// or the SVG is malformed) — the only failure mode `lookupSharedRoute`'s
/// own swallow doesn't already cover. An og:image MUST be image bytes with
/// HTTP 200; a 5xx/JSON body would unfurl as a broken image, which is the
/// very bug this endpoint exists to fix. A blank 1x1 degrades to "no image",
/// not "broken image".
const FALLBACK_PNG = Buffer.from(
	'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
	'base64',
);

export async function renderRouteOgPng(
	id: string,
	config: SharedRouteLookupConfig | null,
): Promise<Buffer> {
	const lookup = await lookupSharedRoute(id, config);
	try {
		const svg = buildRouteOgSvg({
			name: lookup.route?.name,
			distance_m: lookup.route?.distance_m,
			surface: lookup.route?.surface,
			track: lookup.track,
		});
		const resvg = new Resvg(svg, {
			fitTo: { mode: 'width', value: 1200 },
			font: { loadSystemFonts: true },
		});
		return resvg.render().asPng();
	} catch (_) {
		return FALLBACK_PNG;
	}
}

/// Request-time PNG renderer for /og/run/<id>.png. Shared by the
/// production share-run Lambda (apps/web/lambda/share-run/src/index.ts)
/// and the SvelteKit endpoint (apps/web/src/routes/og/run/[id].png/
/// +server.ts) so the SVG card + the missing-run fallback behave
/// identically in dev and prod.
///
/// A run that doesn't resolve (private, deleted, or never existed)
/// renders a generic branded card rather than throwing — the caller
/// returns it with HTTP 200 so a social unfurl never shows a broken
/// image. Persona-hunt round-5 finding very-social.

import { Resvg } from '@resvg/resvg-js';

import { buildRunOgSvg } from './og_run_image';
import {
	lookupSharedRun,
	type SharedRunLookupConfig,
} from './share_run_lookup';

/// A 1x1 transparent PNG. Last-ditch fallback when the native @resvg
/// rasteriser itself fails (e.g. the `.node` binary can't load on a host,
/// or the SVG is malformed) — the only failure mode `lookupSharedRun`'s
/// own swallow doesn't already cover. An og:image MUST be image bytes with
/// HTTP 200; a 5xx/JSON body would unfurl as a broken image, which is the
/// very bug this endpoint exists to fix. A blank 1x1 degrades to "no image",
/// not "broken image".
const FALLBACK_PNG = Buffer.from(
	'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
	'base64',
);

export async function renderRunOgPng(
	id: string,
	config: SharedRunLookupConfig | null,
): Promise<Buffer> {
	const lookup = await lookupSharedRun(id, config);
	try {
		const svg = buildRunOgSvg({
			distance_m: lookup.run?.distance_m,
			duration_s: lookup.run?.duration_s,
			started_at: lookup.run?.started_at,
			source: lookup.run?.source,
			displayName: lookup.displayName,
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

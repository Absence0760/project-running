/// Request-time PNG renderer for /og/recap/<id>.png. Shared by the
/// production share-recap Lambda (apps/web/lambda/share-recap/src/index.ts)
/// and the SvelteKit endpoint (apps/web/src/routes/og/recap/[id].png/
/// +server.ts) so the SVG card + the missing-recap fallback behave
/// identically in dev and prod.
///
/// A recap that doesn't resolve (never published, revoked, or never existed)
/// renders a generic branded card rather than throwing — the caller returns
/// it with HTTP 200 so a social unfurl never shows a broken image.

import { Resvg } from '@resvg/resvg-js';

import { buildRecapOgSvg } from './og_recap_image';
import {
	lookupSharedRecap,
	recapPeriodLabel,
	type SharedRecapLookupConfig,
} from './share_recap_lookup';

const FALLBACK_PNG = Buffer.from(
	'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
	'base64',
);

export async function renderRecapOgPng(
	id: string,
	config: SharedRecapLookupConfig | null,
): Promise<Buffer> {
	const { recap } = await lookupSharedRecap(id, config);
	try {
		const snap = recap?.snapshot ?? {};
		const svg = buildRecapOgSvg({
			year: snap.year,
			month: snap.month,
			totalDistanceM: snap.totalDistanceM,
			runCount: snap.runCount,
			longestRunM: snap.longestRunM,
			bestStreakDays: snap.bestStreakDays,
			topWeekDistanceM: snap.topWeek?.distanceM ?? null,
			totalElevationM: snap.totalElevationM,
			displayName: recap?.displayName ?? null,
			periodLabel: recap ? recapPeriodLabel(recap.periodKind, recap.periodKey) : null,
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

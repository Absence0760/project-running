/// Pure helpers that build the og:title / og:description strings
/// for the public share pages. Split out from the +page.svelte
/// files so unit tests can pin the wire shape without booting
/// SvelteKit, and so the same builder can be used by the eventual
/// per-run track-preview PNG renderer (server-side og:image, still
/// pending per `docs/followups.md § #15`).
///
/// Why not `formatDistance` from `units.svelte`: that helper reads
/// the viewer's `preferred_unit` reactively, which is per-viewer
/// state. The share-page <title> + Open Graph tags must be stable
/// across viewers (a Slack unfurl shouldn't change based on who
/// triggered the scrape), so we default to km here and ignore the
/// viewer-side preference entirely.

const SITE_NAME = 'Run Onward';

export type ShareRunMeta = {
	distance_m?: number | null;
	duration_s?: number | null;
	started_at?: string | null;
	source?: string | null;
};

export type ShareRouteMeta = {
	name?: string | null;
	distance_m?: number | null;
	surface?: string | null;
	elevation_m?: number | null;
};

/// "5.0 km" / "850 m" / "42.20 km" — stable across viewer prefs.
/// Whole-km values still get one decimal so "5 km" doesn't read
/// as a rounding artifact.
export function formatKmStable(metres: number | null | undefined): string {
	if (metres == null || !Number.isFinite(metres) || metres < 0) return '';
	if (metres < 1000) return `${Math.round(metres)} m`;
	const km = metres / 1000;
	// One decimal for short distances, two for marathon+ to keep
	// "42.20 km" precise without growing all titles to 4 digits.
	const digits = km >= 21 ? 2 : 1;
	return `${km.toFixed(digits)} km`;
}

/// "11 May 2026" — UTC + en-GB so the title is identical for every
/// crawler / build environment / viewer locale. Node's ICU bundle
/// returns the same string everywhere when both locale and
/// timeZone are pinned.
export function formatDateStable(iso: string | null | undefined): string {
	if (!iso) return '';
	const d = new Date(iso);
	if (Number.isNaN(d.getTime())) return '';
	return d.toLocaleDateString('en-GB', {
		day: 'numeric',
		month: 'short',
		year: 'numeric',
		timeZone: 'UTC',
	});
}

export function buildRunShareTitle(
	run: ShareRunMeta | null | undefined,
	displayName?: string | null,
): string {
	if (!run) return `Run — ${SITE_NAME}`;
	const km = formatKmStable(run.distance_m);
	const date = formatDateStable(run.started_at);
	const by = displayName ? ` by ${displayName}` : '';
	if (km && date) return `${km} run${by} on ${date} — ${SITE_NAME}`;
	if (km) return `${km} run${by} — ${SITE_NAME}`;
	if (date) return `Run${by} on ${date} — ${SITE_NAME}`;
	return displayName ? `Run by ${displayName} — ${SITE_NAME}` : `Run — ${SITE_NAME}`;
}

export function buildRunShareDescription(
	run: ShareRunMeta | null | undefined,
	displayName?: string | null,
): string {
	if (!run) return 'View a public run on Run Onward — map, splits, elevation, kudos.';
	const km = formatKmStable(run.distance_m);
	const date = formatDateStable(run.started_at);
	const by = displayName ? ` by ${displayName}` : '';
	const bits: string[] = [];
	if (km) bits.push(`${km}${by}`);
	else if (by.trim()) bits.push(`Run${by}`);
	if (date) bits.push(`on ${date}`);
	const lead = bits.length > 0 ? `${bits.join(' ')}.` : '';
	return `${lead} Map, splits, and elevation on Run Onward.`.trim();
}

export function buildRouteShareTitle(route: ShareRouteMeta | null | undefined): string {
	if (!route?.name) return `Route — ${SITE_NAME}`;
	return `${route.name} — ${SITE_NAME}`;
}

export function buildRouteShareDescription(
	route: ShareRouteMeta | null | undefined,
): string {
	if (!route) return 'A public route on Run Onward.';
	const km = formatKmStable(route.distance_m);
	const surface = route.surface ?? '';
	const elev = route.elevation_m
		? ` with ${Math.round(route.elevation_m)} m elevation`
		: '';
	if (km && surface) return `${km} ${surface} route${elev}.`;
	if (km) return `${km} route${elev}.`;
	if (surface) return `${surface} route${elev}.`;
	return 'A public route on Run Onward.';
}

/// Every colour a map overlay paints, keyed on the RESOLVED basemap.
///
/// WCAG 1.4.11 asks a non-text element that carries meaning for 3:1 against
/// what it is adjacent to, and for a map overlay that neighbour is the
/// basemap — not the page, and not the theme. Before this module the six map
/// surfaces branched on `prefers-color-scheme`, which is neither: since
/// § 489 the basemap follows the map-style *preference*, so `outdoors` under
/// a dark OS drew light-ground overlays on light ground. `basemapIsDark`
/// (`map-style-url.ts`) is the honest input; this module is the palette.
///
/// **A translucent casing cannot carry the bar.** Measured at the opacities
/// the surfaces actually use, a white casing at 0.25 over the dark sample
/// reads 2.273:1 and a `#1E1B4B` casing at 0.45 over the light sample
/// 2.710:1 — both under the floor. So every LINE here clears the floor
/// against its own basemap directly, and the casing is registered as
/// decoration that sharpens an already-compliant line rather than as the
/// thing making it visible.
///
/// A pin is the one place a separator does the work: a ring in
/// [mapOverlayOutline] clears the floor against the ground, which makes the
/// pin's boundary discernible, and the FILL inside it is then free to stay
/// a fixed identity hue (route orange, club cyan) per § 480's data line.
///
/// The samples are lifted verbatim from mobile's
/// `live_run_map_tile_url_test.dart` so the two platforms grade against the
/// same ground rather than each against a convenient one (§ 503).

/// Representative land fill of every light basemap we resolve to —
/// MapTiler `streets-v2` and `outdoor-v2`, and the OSM raster fallback.
export const LIGHT_BASEMAP_SAMPLE = '#F2EFE9';

/// Representative land fill of MapTiler `streets-v2-dark`. Also stands in
/// for `satellite`, which `basemapIsDark` classifies as dark.
export const DARK_BASEMAP_SAMPLE = '#1A1B20';

/// Land is the PALE end of a light basemap. An overlay that clears only the
/// land fill is not legible where a riverside route actually runs, so every
/// light rung is held against this too (§ 491).
export const LIGHT_BASEMAP_WATER_SAMPLE = '#AAD3DF';

/// `osm-fallback-style.json`'s own `background-color`, which shows through
/// wherever an OSM raster tile has not arrived yet.
export const OSM_FALLBACK_BACKDROP = '#DCDCDC';

/// WCAG 1.4.11's floor for a non-text element that carries meaning.
export const MAP_OVERLAY_FLOOR = 3;

/// Separator between an overlay and the ground: the ring around a pin, and
/// the casing under a track. Twin of mobile's `mapOverlayOutline`.
export function mapOverlayOutline(darkBasemap: boolean): string {
	return darkBasemap ? '#FFFFFF' : '#1E1B4B';
}

/// The recorded / saved track line.
export function mapTrackLine(darkBasemap: boolean): string {
	return darkBasemap ? '#818CF8' : '#4F46E5';
}

/// Transient amber accent — the selected-segment highlight, the animated
/// replay trace, and a coarse (privacy-clipped) last-seen position. Twin of
/// mobile's `mapAccentColour`, same two rungs.
export function mapAccentColour(darkBasemap: boolean): string {
	return darkBasemap ? '#F59E0B' : '#B45309';
}

/// Start and finish caps. These are `maplibregl.Marker` fills, and
/// MapLibre's default marker sets `stroke: none`, so the fill IS the
/// silhouette against the ground and owes the floor on its own.
export function mapStartColour(darkBasemap: boolean): string {
	return darkBasemap ? '#22C55E' : '#15803D';
}

export function mapFinishColour(darkBasemap: boolean): string {
	return darkBasemap ? '#EF4444' : '#B91C1C';
}

/// The privacy-zone circle in the zone picker: its 2 px boundary, the marker
/// at its centre, and the 0.18 wash inside it.
///
/// This is the one overlay on the map whose job is to tell the runner what is
/// being REDACTED, so a circle they cannot see is a privacy setting they
/// cannot check. It was a single fixed `#dc2626`, and that value does clear
/// 1.4.11's 3:1 on every ground the picker resolves — 4.208:1 on the light
/// land sample, 3.560 on the dark, 3.522 on the keyless OSM backdrop, and
/// **3.011 over light-basemap water**. A 0.4 % margin is not a pass (§ 535's
/// "a margin of 2 px is not a pass", one unit over), and the reason no single
/// red does better is structural: a red dark enough for the pale grounds is
/// too dark for the dark one and vice versa, which is § 541's finding that a
/// mark owing 3:1 twice cannot be paid by one colour.
///
/// So it splits. The light rung is held against the WORST of the three light
/// grounds — water, not land, because a zone over a riverside home is the
/// ordinary case — and the dark rung against the dark land sample. Both are
/// measured in `basemap_contrast.test.ts`; the numbers here are the worst
/// ground each rung faces, not its best.
///
/// The 0.18 wash is decoration on the same footing as the track casing: it
/// reads 1.14–1.31:1 against every ground, so it cannot be counted as the
/// zone's contrast and the boundary clears the floor unaided. The centre
/// marker takes the same rung because MapLibre's default marker sets
/// `stroke: none` — its fill IS the silhouette.
export function mapZoneBoundary(darkBasemap: boolean): string {
	return darkBasemap ? '#EF4444' : '#991B1B';
}

/// The hovered-route preview line on the routes heatmap.
export function mapHoverLine(darkBasemap: boolean): string {
	return darkBasemap ? '#22D3EE' : '#0E7490';
}

/// A pinned ("kept on map") route line, deliberately distinct from
/// [mapHoverLine].
export function mapPinnedLine(darkBasemap: boolean): string {
	return darkBasemap ? '#A78BFA' : '#6D28D9';
}

/// The route being drafted in the route builder.
export function mapDraftLine(darkBasemap: boolean): string {
	return darkBasemap ? '#60A5FA' : '#1D4ED8';
}

/// The stretch of a drafted route that doubles back over itself.
export function mapOverlapLine(darkBasemap: boolean): string {
	return darkBasemap ? '#C084FC' : '#7E22CE';
}

/// A live spectator trace.
export function mapLiveLine(darkBasemap: boolean): string {
	return darkBasemap ? '#7FB3C2' : '#2C5F6E';
}

/// A dashed hint line — the un-snapped preview, the waypoint tethers.
export function mapHintLine(darkBasemap: boolean): string {
	return darkBasemap ? '#94A3B8' : '#475569';
}

/// The thicker halo marking a featured route's pin. On the light basemap
/// this lands on `--color-crown`'s value, which is the deliberately dark
/// gold minted for light grounds (§ 495).
export function mapFeaturedHalo(darkBasemap: boolean): string {
	return darkBasemap ? '#FACC15' : '#7A5C10';
}

/// Ink for a map label, held to AA against the ground DIRECTLY. The halo
/// below is ground-coloured on purpose and so cannot be counted as the
/// label's contrast.
export function mapLabelInk(darkBasemap: boolean): string {
	return darkBasemap ? '#F1F5F9' : '#1E293B';
}

/// Halo around a map label. Near the ground on both sides (1.038:1 dark,
/// 1.148:1 light) because its job is to hold the glyph apart from mid-tone
/// map FEATURES it crosses — road casings, building fills, other labels —
/// not from the flat land fill.
export function mapLabelHalo(darkBasemap: boolean): string {
	return darkBasemap ? '#0F172A' : '#FFFFFF';
}

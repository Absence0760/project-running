// Every map-overlay colour is held to WCAG 1.4.11's 3:1 floor against the
// basemap it is actually drawn over — measured here rather than asserted
// from a remembered figure, so a rung that drifts fails instead of aging
// into a stale comment (§ 503).
//
// Invocation:
//   npx tsx --test src/lib/routes/basemap_contrast.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { basemapIsDark } from './map-style-url';
import {
	DARK_BASEMAP_SAMPLE,
	LIGHT_BASEMAP_SAMPLE,
	LIGHT_BASEMAP_WATER_SAMPLE,
	MAP_OVERLAY_FLOOR,
	OSM_FALLBACK_BACKDROP,
	mapAccentColour,
	mapDraftLine,
	mapFeaturedHalo,
	mapFinishColour,
	mapHintLine,
	mapHoverLine,
	mapLabelHalo,
	mapLabelInk,
	mapLiveLine,
	mapOverlapLine,
	mapOverlayOutline,
	mapPinnedLine,
	mapStartColour,
	mapTrackLine,
} from './basemap_contrast';

function channels(hex: string): [number, number, number] {
	const s = hex.replace('#', '');
	return [0, 2, 4].map((i) => parseInt(s.slice(i, i + 2), 16) / 255) as [
		number,
		number,
		number,
	];
}

function relativeLuminance(hex: string): number {
	const [r, g, b] = channels(hex).map((c) =>
		c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4),
	);
	return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(a: string, b: string): number {
	const la = relativeLuminance(a);
	const lb = relativeLuminance(b);
	return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

/// Composite [fg] over [bg] at [alpha] — how a translucent casing actually
/// reaches the eye.
function composite(fg: string, bg: string, alpha: number): string {
	const f = channels(fg);
	const b = channels(bg);
	return (
		'#' +
		f
			.map((v, i) => Math.round((v * alpha + b[i] * (1 - alpha)) * 255))
			.map((v) => v.toString(16).padStart(2, '0'))
			.join('')
	);
}

// Every rung whose job is to be visible ON the ground. The pair is (name,
// resolver) and each side is graded against its own basemap only — grading
// a light rung against the dark sample is exactly the mistake this module
// exists to stop, in reverse.
const GROUND_RUNGS: Array<[string, (dark: boolean) => string]> = [
	['overlay outline', mapOverlayOutline],
	['track line', mapTrackLine],
	['accent', mapAccentColour],
	['start cap', mapStartColour],
	['finish cap', mapFinishColour],
	['hover line', mapHoverLine],
	['pinned line', mapPinnedLine],
	['draft line', mapDraftLine],
	['overlap line', mapOverlapLine],
	['live line', mapLiveLine],
	['hint line', mapHintLine],
	['featured halo', mapFeaturedHalo],
];

test('every overlay rung clears 1.4.11 against the basemap it lands on', () => {
	for (const [name, resolve] of GROUND_RUNGS) {
		const onDark = contrast(resolve(true), DARK_BASEMAP_SAMPLE);
		assert.ok(
			onDark >= MAP_OVERLAY_FLOOR,
			`${name} on the dark basemap: ${resolve(true)} reads ${onDark.toFixed(3)}:1`,
		);
		// Land is the pale end of a light basemap; water and the OSM
		// backdrop are darker, and an overlay legible only on land is not
		// legible where a riverside route runs.
		for (const ground of [
			LIGHT_BASEMAP_SAMPLE,
			LIGHT_BASEMAP_WATER_SAMPLE,
			OSM_FALLBACK_BACKDROP,
		]) {
			const onLight = contrast(resolve(false), ground);
			assert.ok(
				onLight >= MAP_OVERLAY_FLOOR,
				`${name} on light basemap fill ${ground}: ${resolve(false)} reads ${onLight.toFixed(3)}:1`,
			);
		}
	}
});

test('no rung is the same colour on both basemaps', () => {
	// The defect class: one frozen hue serving both grounds, which is how
	// `#F59E0B` came to read 1.871:1 on a light basemap while looking fine
	// on the dark one it was eyeballed against.
	for (const [name, resolve] of GROUND_RUNGS) {
		assert.notEqual(
			resolve(true),
			resolve(false),
			`${name} paints one frozen hue on both grounds`,
		);
	}
});

test('a label reads AA on the halo it is drawn against', () => {
	for (const dark of [true, false]) {
		const ratio = contrast(mapLabelInk(dark), mapLabelHalo(dark));
		assert.ok(
			ratio >= 4.5,
			`label ink ${mapLabelInk(dark)} on halo ${mapLabelHalo(dark)} reads ${ratio.toFixed(3)}:1`,
		);
	}
});

test('the halo is ground-coloured on BOTH grounds, so the ink carries itself', () => {
	// Symmetric and deliberate, and the reason it is pinned rather than
	// "fixed": a text halo's job is to hold the glyph apart from mid-tone
	// map FEATURES it crosses — road casings, building fills, other labels
	// — not from the flat land fill, so it is drawn near the ground on
	// purpose and reads ~1:1 against it (1.038:1 dark, 1.148:1 light).
	// What that forbids is treating the halo as the label's contrast: the
	// ink has to clear the ground unaided, on both.
	for (const [dark, ground] of [
		[true, DARK_BASEMAP_SAMPLE],
		[false, LIGHT_BASEMAP_SAMPLE],
	] as Array<[boolean, string]>) {
		assert.ok(
			contrast(mapLabelHalo(dark), ground) < MAP_OVERLAY_FLOOR,
			`halo ${mapLabelHalo(dark)} is not the thing making the label visible`,
		);
		assert.ok(
			contrast(mapLabelInk(dark), ground) >= 4.5,
			`label ink ${mapLabelInk(dark)} must clear ${ground} on its own: ` +
				`${contrast(mapLabelInk(dark), ground).toFixed(3)}:1`,
		);
	}
});

test('a translucent casing cannot carry the floor, which is why the line does', () => {
	// Measured at the opacities the surfaces really use. Recorded as a test
	// rather than a comment because it is the reason no rung above is
	// justified by "it has a casing".
	const casingOnDark = composite(mapOverlayOutline(true), DARK_BASEMAP_SAMPLE, 0.25);
	const casingOnLight = composite(mapOverlayOutline(false), LIGHT_BASEMAP_SAMPLE, 0.45);
	assert.ok(
		contrast(casingOnDark, DARK_BASEMAP_SAMPLE) < MAP_OVERLAY_FLOOR,
		'a 0.25 casing over the dark basemap is below the floor',
	);
	assert.ok(
		contrast(casingOnLight, LIGHT_BASEMAP_SAMPLE) < MAP_OVERLAY_FLOOR,
		'a 0.45 casing over the light basemap is below the floor',
	);
	// …and the line it sits under clears it unaided, on both grounds.
	assert.ok(contrast(mapTrackLine(true), DARK_BASEMAP_SAMPLE) >= MAP_OVERLAY_FLOOR);
	assert.ok(contrast(mapTrackLine(false), LIGHT_BASEMAP_SAMPLE) >= MAP_OVERLAY_FLOOR);
});

test('basemapIsDark follows the resolved basemap, not the OS preference', () => {
	// The two directions of the defect. `outdoors` is a light basemap even
	// under a dark OS; `dark` and `satellite` are dark ones even under a
	// light OS. An overlay keyed on `prefersDark` gets both backwards.
	assert.equal(basemapIsDark('outdoors', 'KEY', true), false);
	assert.equal(basemapIsDark('satellite', 'KEY', false), true);
	assert.equal(basemapIsDark('dark', 'KEY', false), true);
	// The default `streets` choice is the one case where the OS preference
	// really does decide, because the slug does.
	assert.equal(basemapIsDark('streets', 'KEY', true), true);
	assert.equal(basemapIsDark('streets', 'KEY', false), false);
});

test('the keyless OSM raster fallback is a light basemap', () => {
	// No MapTiler key → `OSM_FALLBACK_STYLE_URL`, whose own background is
	// `#dcdcdc` under light OSM tiles. Classifying it by the OS preference
	// would paint light-ground overlays on it for every dark-mode user.
	for (const prefersDark of [true, false]) {
		assert.equal(basemapIsDark('dark', '', prefersDark), false);
		assert.equal(basemapIsDark('satellite', '  ', prefersDark), false);
	}
});

test('a self-hosted override is classified by its URL', () => {
	assert.equal(basemapIsDark('streets', 'KEY', false, 'http://localhost:8080/dark.json'), true);
	assert.equal(basemapIsDark('streets', 'KEY', true, 'http://localhost:8080/light.json'), false);
	// Blank is absent, matching `resolveStyleOverride` / `buildMapStyleUrl`.
	assert.equal(basemapIsDark('dark', 'KEY', false, '   '), true);
});

test('the pre-fix figures reproduce, so the mismatch was real', () => {
	// `outdoors` under a dark OS: the old code took the dark-basemap track
	// line and painted it on light ground.
	const wrongOnLight = contrast(mapTrackLine(true), LIGHT_BASEMAP_SAMPLE);
	assert.ok(wrongOnLight < 2.7, `was ${wrongOnLight.toFixed(3)}:1`);
	// `satellite` under a light OS: the mirror image.
	const wrongOnDark = contrast(mapTrackLine(false), DARK_BASEMAP_SAMPLE);
	assert.ok(wrongOnDark < 2.8, `was ${wrongOnDark.toFixed(3)}:1`);
	// The frozen amber every surface shared, on the light basemap § 489
	// made reachable.
	assert.ok(contrast('#F59E0B', LIGHT_BASEMAP_SAMPLE) < 2);
});

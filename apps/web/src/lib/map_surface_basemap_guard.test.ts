// Guard-rail: a map surface's overlay paint resolves off the BASEMAP, and the
// OS colour preference is only ever allowed to choose the basemap itself.
//
// §526 measured what happens when those two are conflated: the map-style
// preference decouples basemap luminance from the OS in both directions
// (`outdoors` is light ground under a dark OS, `dark` and `satellite` are dark
// ground under a light one), and all six map surfaces branched on
// `prefers-color-scheme`. 35 of 49 cartographic literals failed the basemap
// they were actually drawn over, missing by roughly a factor of two either
// way. Five surfaces were routed through `basemapIsDark`; `basemap_contrast.ts`
// is the palette that resolver feeds.
//
// Nothing stopped a sixth. So the register below is the list of map surfaces,
// and it is checked in both directions: a new file that instantiates MapLibre
// must be added to it, and every entry must resolve its ground through the
// shared resolver rather than the OS. The load-bearing check is the third one
// — the OS-preference symbol may reach a style URL, a basemap classifier, or a
// slug table, and nothing else. That is the mechanical form of "the OS may
// pick the basemap; it may not pick the paint".
//
// Deliberately NOT checked: `prefers-color-scheme` in a surface's <style>
// block. A map component's CSS also styles its list rows and chrome, which
// ARE theme surfaces — §526's own violet `--kept-accent` on RouteHeatmap is
// exactly that, keyed on the theme on purpose. A guard that banned the media
// query outright would be wrong about half its matches.
//
// Invocation:
//   npx tsx --test src/lib/map_surface_basemap_guard.test.ts

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { relative, resolve } from 'node:path';

import { maptilerStyleUrl, type MaptilerSlug } from './routes/map-style-url';

const libRoot = import.meta.dirname;
const srcRoot = resolve(libRoot, '..');

/// How each map surface establishes the ground its overlays land on.
///   'shared'   — calls basemapIsDarkFromEnv / basemapIsDarkForSlug.
///   'unkeyed'  — paints no basemap-dependent colour at all.
const MAP_SURFACES: Record<string, ['shared' | 'unkeyed', string]> = {
	'lib/components/RunMap.svelte': ['shared', 'the recorded-track map'],
	'lib/components/RouteBuilder.svelte': ['shared', 'own slug table, shared classifier'],
	'lib/components/RouteHeatmap.svelte': ['shared', 'the routes-discovery heatmap'],
	'lib/components/PersonalHeatmap.svelte': ['shared', 'the personal run heatmap'],
	'routes/live/[id]/+page.svelte': ['shared', 'the spectator live map'],
	'routes/live/event/[id]/[instance]/+page.svelte': ['shared', 'the event live hub map'],
	// The privacy-zone circle is one fixed danger hue on both grounds, not a
	// keyed pair: `#dc2626` clears 1.4.11 on every basemap this app resolves
	// to (4.208:1 light land, 3.560 dark, 3.011 over light-basemap water,
	// 3.522 on the OSM backdrop), which no darker or lighter red does. It
	// therefore has no basemap question to get wrong — but the margin over
	// water is the thinnest in the literal register, and is asserted there.
	'lib/components/PrivacyZonePicker.svelte': ['unkeyed', 'one hue that clears every ground'],
};

/// Infrastructure, not a surface: the MapLibre re-export and the resize
/// observer instantiate no map and paint nothing.
const NOT_SURFACES = new Set(['lib/routes/maplibre.ts', 'lib/routes/map_resize.ts']);

function sourceFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = resolve(dir, entry.name);
		if (entry.isDirectory()) {
			sourceFiles(full, out);
			continue;
		}
		if (!/\.(ts|svelte)$/.test(entry.name) || entry.name.endsWith('.test.ts')) continue;
		out.push(full);
	}
	return out;
}

function rel(file: string): string {
	return relative(srcRoot, file).split('\\').join('/');
}

function read(key: string): string {
	return readFileSync(resolve(srcRoot, key), 'utf-8');
}

test('every file that instantiates MapLibre is a registered map surface', () => {
	const unregistered = sourceFiles(srcRoot)
		.filter((f) => /routes\/maplibre'|from 'maplibre-gl'/.test(readFileSync(f, 'utf-8')))
		.map(rel)
		.filter((key) => !NOT_SURFACES.has(key) && !(key in MAP_SURFACES));
	assert.deepEqual(
		unregistered,
		[],
		`these files render a MapLibre map but are not in MAP_SURFACES: ${unregistered.join(', ')}. ` +
			'Add the entry and resolve the ground through basemapIsDarkFromEnv (or ' +
			'basemapIsDarkForSlug if the surface owns its slug table) — a sixth surface ' +
			'keying overlay paint on prefers-color-scheme is what § 526 measured as 35 of ' +
			'49 literals failing the basemap they were drawn over.',
	);
});

test('every registered surface resolves the ground the way its entry claims', () => {
	for (const [key, [how]] of Object.entries(MAP_SURFACES)) {
		const source = read(key);
		const resolves = /basemapIsDark(FromEnv|ForSlug)\(/.test(source);
		const paints = /\bmap(TrackLine|AccentColour|OverlayOutline|StartColour|FinishColour|HoverLine|PinnedLine|DraftLine|OverlapLine|LiveLine|HintLine|FeaturedHalo|LabelInk|LabelHalo)\(/.test(
			source,
		);
		if (how === 'shared') {
			assert.ok(resolves, `${key} is registered 'shared' but calls no basemap resolver`);
			assert.ok(paints, `${key} is registered 'shared' but paints no basemap-keyed colour`);
		} else {
			assert.ok(
				!paints,
				`${key} is registered 'unkeyed' but calls a basemap_contrast rung — it has a ` +
					'ground question after all, so register it as shared and resolve it.',
			);
		}
	}
});

/// Sinks the OS colour preference may legitimately flow into: the basemap
/// style URL, the basemap classifier, and a slug table (where the preference
/// picks WHICH basemap, which is its job). Anything else is the preference
/// reaching the paint.
const ALLOWED_OS_PREFERENCE_SINK =
	/mapStyleUrl|basemapIsDark|'streets-v2|'satellite'|'hybrid'|'outdoor-v2/;

/// Blank out a component's `<style>` block, keeping line numbering. The CSS is
/// out of scope for the reason in the header — a map component's stylesheet
/// also dresses list rows, which are theme surfaces — while the markup stays
/// in, because a `class:` or `style:` binding fed by the OS preference would
/// be the same defect wearing a different hat.
function withoutStyleBlock(source: string): string {
	const open = source.indexOf('<style');
	if (open === -1) return source;
	const head = source.slice(0, open);
	const tail = source.slice(open);
	return head + tail.replace(/[^\n]/g, '');
}

/// The symbol each surface stores its media query in, found by walking back
/// from the query to its nearest enclosing declaration — so the check reads
/// whatever the surface calls it rather than pinning one spelling (§ 528).
function osPreferenceSymbols(key: string, lines: string[]): string[] {
	const symbols = new Set<string>();
	lines.forEach((line, i) => {
		if (!line.includes('prefers-color-scheme')) return;
		for (let j = i; j >= Math.max(0, i - 3); j--) {
			const declaration = lines[j].match(/(?:const|let|function)\s+(\w+)/);
			if (declaration) {
				symbols.add(declaration[1]);
				return;
			}
		}
		assert.fail(`${key}:${i + 1} reads prefers-color-scheme into no named binding`);
	});
	return [...symbols];
}

test('the OS colour preference reaches the basemap and nothing else', () => {
	const offenders: string[] = [];
	for (const key of Object.keys(MAP_SURFACES)) {
		const lines = withoutStyleBlock(read(key)).split('\n');
		const symbols = osPreferenceSymbols(key, lines);
		assert.ok(
			symbols.length > 0,
			`${key} reads no prefers-color-scheme value; if that changed, drop it from this check`,
		);
		for (const symbol of symbols) {
			const declaration = new RegExp(`(?:const|let|function)\\s+${symbol}\\b`);
			const use = new RegExp(`\\b${symbol}\\b`);
			lines.forEach((line, i) => {
				if (!use.test(line)) return;
				if (/^\s*(\/\/|\/?\*)/.test(line)) return;
				if (declaration.test(line)) return;
				if (ALLOWED_OS_PREFERENCE_SINK.test(line)) return;
				offenders.push(`${key}:${i + 1} ${line.trim()}`);
			});
		}
	}
	assert.deepEqual(
		offenders,
		[],
		`the OS colour preference flows somewhere other than the basemap:\n${offenders.join('\n')}\n` +
			'A map overlay owes 3:1 to the ground it is drawn over, and the map-style ' +
			'preference decouples that ground from the OS in both directions. Resolve ' +
			'basemapIsDark* and paint off that.',
	);
});

/// The route builder's own slug table, read out of its source rather than
/// remembered. § 526 declined to route this surface through the shared
/// resolver because doing so would have changed which satellite tiles it
/// requests; this proves the reconciliation did not.
const BUILDER_EXPECTED_SLUGS: Record<string, MaptilerSlug> = {
	satellite: 'hybrid',
	terrain: 'outdoor-v2',
};

test('the route builder still requests exactly the tiles it did before', () => {
	const source = read('lib/components/RouteBuilder.svelte');
	for (const [rung, slug] of Object.entries(BUILDER_EXPECTED_SLUGS)) {
		assert.match(
			source,
			new RegExp(`${rung}:\\s*'${slug}'`),
			`the route builder's ${rung} rung must stay on the '${slug}' slug. Pointing it ` +
				"at the preference union's slug would silently change the imagery — the " +
				'reason § 526 left this surface alone.',
		);
	}
	// The streets rung is the one place the OS preference legitimately picks
	// the basemap, and it is the same pair the shared resolver uses.
	assert.match(source, /streets:\s*prefersDark \? 'streets-v2-dark' : 'streets-v2'/);
	// The URLs those slugs produce, spelled out, so a change to the shared
	// template is visible here as well as in map-style.test.ts.
	assert.equal(
		maptilerStyleUrl('hybrid', 'K'),
		'https://api.maptiler.com/maps/hybrid/style.json?key=K',
	);
	assert.equal(
		maptilerStyleUrl('outdoor-v2', 'K'),
		'https://api.maptiler.com/maps/outdoor-v2/style.json?key=K',
	);
});

test('no MapLibre paint value is a CSS expression MapLibre cannot parse', () => {
	const offenders: string[] = [];
	for (const key of Object.keys(MAP_SURFACES)) {
		read(key)
			.split('\n')
			.forEach((line, i) => {
				if (!/'[a-z-]*(color|colour)'\s*:/.test(line)) return;
				if (!/var\(--|color-mix\(/.test(line)) return;
				offenders.push(`${key}:${i + 1} ${line.trim()}`);
			});
	}
	assert.deepEqual(
		offenders,
		[],
		`a MapLibre paint property was given a CSS-only value:\n${offenders.join('\n')}\n` +
			'MapLibre parses paint values itself and throws out of addLayer on a var() or ' +
			'color-mix(), taking the whole map down with it (§ 528). Resolve the colour in ' +
			'JS and pass a literal.',
	);
});

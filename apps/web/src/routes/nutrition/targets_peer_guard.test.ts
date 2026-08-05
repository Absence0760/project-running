import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { en } from '../../lib/i18n/locales/en';
import { SUPPORTED_LOCALES } from '../../lib/i18n/locale';
import { CATALOGUE_LOADERS } from '../../lib/i18n/catalogues';

const DAY = readFileSync(new URL('./+page.svelte', import.meta.url), 'utf8');
const TARGETS = readFileSync(new URL('./targets/+page.svelte', import.meta.url), 'utf8');
const PREFS = readFileSync(
	new URL('../settings/preferences/+page.svelte', import.meta.url),
	'utf8',
);

// Targets is a first-class peer of the Nutrition surface: reachable from
// /nutrition in one click, editable at its own URL, and — because the Art 9
// consent gate on height/weight lives in Settings — deliberately NOT a second
// place those can be entered. Each assertion below pins one half of that
// contract; between them they are what stops the peer decaying back into a
// number you can see but not reach.

function headerBlock(src: string): string {
	const open = src.indexOf('<header class="page-header">');
	const close = src.indexOf('</header>', open);
	assert.ok(open >= 0 && close > open, 'page-header block not found');
	return src.slice(open, close);
}

test('/nutrition links to the targets peer, ungated', () => {
	const head = headerBlock(DAY);
	assert.match(head, /href="\/nutrition\/targets"/);
	// A data gate here would hide the peer from exactly the user with no
	// targets yet — the one who needs it. Keep the header branch-free.
	assert.doesNotMatch(head, /\{#if/);
});

test('both body-metrics CTAs deep-link to a section the preferences page still carries', () => {
	for (const [name, src] of [
		['nutrition', DAY],
		['nutrition/targets', TARGETS],
	] as const) {
		assert.match(
			src,
			/href="\/settings\/preferences#body-metrics"/,
			`${name} lost its body-metrics deep link`,
		);
	}
	assert.match(PREFS, /id="body-metrics"/, 'preferences dropped the body-metrics anchor');
});

test('the targets peer does not become a second Art 9 entry point', () => {
	for (const banned of [
		'healthDataConsent',
		'grantHealthDataConsent',
		'withdrawHealthDataConsent',
		'setMyHeightCm',
		'recordWeightKg',
		'clearWeightHistory',
	]) {
		assert.doesNotMatch(
			TARGETS,
			new RegExp(banned),
			`${banned} on /nutrition/targets duplicates the consent-gated surface`,
		);
	}
	// Read-only display of the metrics is the point; an input is not.
	assert.doesNotMatch(TARGETS, /<input/);
});

test('the targets peer reuses the parity-paired engine instead of re-deriving it', () => {
	assert.match(TARGETS, /from '\$lib\/nutrition\/nutrition_targets'/);
	for (const named of [
		'computeNutritionTargets',
		'mifflinStJeorBmr',
		'ACTIVITY_LEVELS',
		'GOAL_KCAL_DELTA',
		'PROTEIN_G_PER_KG',
		'FAT_KCAL_FRACTION',
		'MIN_CALORIE_TARGET',
	]) {
		assert.match(TARGETS, new RegExp(`\\b${named}\\b`), `${named} not reused`);
	}
	// The engine's magic numbers must arrive as those exported constants —
	// a copy here would drift silently from the Dart twin. Scoped to the
	// script block; the same digits are legitimate CSS lengths below it.
	const script = TARGETS.slice(0, TARGETS.indexOf('</script>'));
	assert.ok(script.length > 0, 'script block not found');
	for (const literal of ['1.8', '0.3', '1200', '-500']) {
		assert.ok(
			!script.includes(literal),
			`literal ${literal} re-derives what nutrition_targets already exports`,
		);
	}
});

test('every message key the two pages reference exists in all six catalogues', async () => {
	const keys = new Set<string>();
	for (const src of [DAY, TARGETS]) {
		for (const [, key] of src.matchAll(/\bm\('([a-zA-Z0-9_.]+)'/g)) keys.add(key);
	}
	assert.ok(keys.has('nutrition.targets.link'), 'header link key not detected — regex drifted');
	const enRecord = en as Record<string, string>;
	for (const key of keys) {
		assert.ok(enRecord[key] !== undefined, `en is missing ${key}`);
	}
	for (const loc of SUPPORTED_LOCALES) {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		for (const key of keys) {
			assert.ok(dict[key] !== undefined, `${loc} is missing ${key}`);
		}
	}
});

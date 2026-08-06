// The `runs.activity_type` vocabulary, pinned end to end: SQL CHECK →
// `ACTIVITY_TYPES` → one catalogue key per value in all six locales → no
// surface naming an activity any other way.
//
// Before this existed there were SEVEN vocabularies for five values, and they
// disagreed WITHIN a locale: German `hike` was both "Wandern" and "Wanderung",
// German `run` both "Lauf" and "Laufen", Spanish `run` "Carrera" and "Correr",
// Spanish `stroller` "Cochecito" and "Carrito", Japanese `walk` "ウォーク" and
// "ウォーキング", Brazilian `cycle` "Ciclismo" and "Pedalada". Four of the seven
// omitted `stroller` entirely, so a stroller run's detail page rendered the raw
// token "stroller" in every language and neither settings surface could offer
// it. That is what a per-surface vocabulary decays into; the fix is one
// vocabulary, so this file's job is to keep it one.
//
// The tree-wide "no surface hand-capitalises an identifier instead of resolving
// a label" sweep is NOT duplicated here — `training/workout_labels.test.ts`
// already scans every source file for that shape against a named allowlist, and
// the entry it carried for `/coaching/athletes/[id]`'s `activityLabel` is gone
// because that call site now resolves. Two sweeps of one shape would drift.
//
// Invocation:
//   npx tsx --test src/lib/runs/activity_type_vocabulary.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

// Relative, not `$lib`: this suite runs under `tsx --test`, which resolves the
// alias only from the `.svelte-kit/tsconfig.json` a `svelte-kit sync` generates.
// CI's drift job runs the tests without syncing first, so a `$lib` import passes
// locally after any dev command and fails there with ERR_MODULE_NOT_FOUND.
import { SUPPORTED_LOCALES } from '../i18n/locale.js';
import { CATALOGUE_LOADERS } from '../i18n/catalogues.js';
import { ACTIVITY_TYPES, ACTIVITY_TYPE_ICONS, activityTypeKey } from './activity_type.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, '..', '..', '..', '..', '..');
const MIGRATIONS = join(REPO_ROOT, 'apps/backend/supabase/migrations');

// ── The authoritative value set, read from SQL ──────────────────────────────
// Derived, not restated: a migration that widens the CHECK must fail this file
// until the catalogues catch up, which is the whole point.
function checkValuesFromMigrations(): Set<string> {
	const re =
		/constraint\s+runs_activity_type_check\s*\n?\s*check\s*\(\s*activity_type\s+in\s*\(([^)]*)\)/i;
	const files = readdirSync(MIGRATIONS)
		.filter((f) => f.endsWith('.sql'))
		.sort();
	let found: Set<string> | null = null;
	for (const f of files) {
		const m = readFileSync(join(MIGRATIONS, f), 'utf-8').match(re);
		if (!m) continue;
		const vals = new Set<string>();
		for (const v of m[1].matchAll(/'([^']+)'/g)) vals.add(v[1]);
		found = vals; // later migration wins
	}
	assert.ok(found, 'no migration declares runs_activity_type_check');
	return found;
}

test('ACTIVITY_TYPES is exactly the CHECK-constraint value set', () => {
	const sql = checkValuesFromMigrations();
	assert.ok(sql.size > 0, 'parsed an EMPTY value set out of the CHECK constraint');
	assert.deepEqual(
		[...ACTIVITY_TYPES].sort(),
		[...sql].sort(),
		'ACTIVITY_TYPES drifted from runs_activity_type_check',
	);
	assert.deepEqual(Object.keys(ACTIVITY_TYPE_ICONS).sort(), [...sql].sort());
});

// ── Every value has a key, in every locale ──────────────────────────────────

test('every CHECK value carries a label in every locale, and no locale names two values the same', async () => {
	const sql = [...checkValuesFromMigrations()].sort();
	let checked = 0;
	for (const loc of SUPPORTED_LOCALES) {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		const seen = new Map<string, string>();
		for (const value of sql) {
			const key = `activityType.${value}`;
			const label = dict[key];
			assert.ok(
				typeof label === 'string' && label.trim().length > 0,
				`${loc} has no non-empty label for activity_type '${value}' (${key}). ` +
					`A missing key renders the English fallback — a runtime English leak.`,
			);
			// The failure mode being closed is two names for one thing. Its mirror —
			// one name for two things — is just as wrong: a picker with two
			// identically-labelled chips is unusable.
			const clash = seen.get(label);
			assert.equal(
				clash,
				undefined,
				`${loc} labels both '${clash}' and '${value}' as ${JSON.stringify(label)}`,
			);
			seen.set(label, value);
			checked++;
		}
	}
	assert.equal(
		checked,
		SUPPORTED_LOCALES.length * sql.length,
		`checked ${checked} labels, expected ${SUPPORTED_LOCALES.length * sql.length} ` +
			`(${SUPPORTED_LOCALES.length} locales x ${sql.length} values)`,
	);
});

test('activityTypeKey builds the key the catalogues actually carry', async () => {
	const en = (await CATALOGUE_LOADERS.en()) as Record<string, string>;
	for (const v of ACTIVITY_TYPES) assert.ok(en[activityTypeKey(v)], `en lacks ${activityTypeKey(v)}`);
});

// ── No catalogue re-grows a per-surface vocabulary ──────────────────────────
//
// A per-surface duplicate is any key OUTSIDE the canonical namespace that names
// one of the five values in the `<surface>.activity<Value>` /
// `<surface>.activity_<value>` shape all seven of the originals used. The
// matcher is over KEY NAMES (there is no other signal — two catalogue entries
// spelling `hike` differently are both valid strings), so it earns a fixture
// table in both directions like any other regex-shaped guard.

const DUPLICATE_KEY = new RegExp(
	`^(?!activityType\\.)[A-Za-z]+\\.activity_?(${ACTIVITY_TYPES.join('|')})$`,
	'i',
);

const KEY_FIXTURES: Array<[flagged: boolean, key: string]> = [
	// The seven that existed, one key each — including `prefs.activityRun`,
	// which a first pass of this guard is what surfaced (the hand audit had
	// found six).
	[true, 'profile.activityRun'],
	[true, 'runDetail.activityHike'],
	[true, 'runs.activityStroller'],
	[true, 'settingsDevices.activityCycle'],
	[true, 'socialFeed.activityWalk'],
	[true, 'runEditor.activity_run'],
	[true, 'prefs.activityRun'],
	// A surface nobody has built yet, same shape — the point of matching a shape
	// rather than a list.
	[true, 'someNewPage.activityStroller'],
	// The canonical namespace itself must be spared or the guard eats the fix.
	[false, 'activityType.run'],
	[false, 'activityType.stroller'],
	// `all` / `lift` are feed SCOPES, not activity_type values, so a surface may
	// legitimately own those words.
	[false, 'socialFeed.activityAll'],
	[false, 'socialFeed.activityLift'],
	[false, 'runs.activityTypeGroup'],
	[false, 'challenges.activityAny'],
	// `prefs.activity_*` is the body-metrics activity LEVEL — a different
	// concept that happens to share the word, and must not be swept up.
	[false, 'prefs.activity_sedentary'],
	[false, 'prefs.activityLevel'],
	// Not the shape: the value is not the whole tail.
	[false, 'runDetail.activityRunSplits'],
];

test('the duplicate-vocabulary matcher flags a surface-scoped value key and spares the canonical one', () => {
	for (const [flagged, key] of KEY_FIXTURES) {
		assert.equal(
			DUPLICATE_KEY.test(key),
			flagged,
			`must ${flagged ? 'flag' : 'spare'} ${JSON.stringify(key)}`,
		);
	}
});

test('no catalogue carries a second, surface-scoped activity vocabulary', async () => {
	let localesChecked = 0;
	let keysScanned = 0;
	for (const loc of SUPPORTED_LOCALES) {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		const keys = Object.keys(dict);
		keysScanned += keys.length;
		const strays = keys.filter((k) => DUPLICATE_KEY.test(k));
		assert.deepEqual(
			strays,
			[],
			`${loc} carries surface-scoped activity labels ${JSON.stringify(strays)}. ` +
				`Resolve through activityTypeLabel() instead — a second vocabulary is how the ` +
				`seven drifted apart.`,
		);
		localesChecked++;
	}
	// Assert the population: an empty catalogue would pass the loop above.
	assert.equal(localesChecked, SUPPORTED_LOCALES.length);
	assert.ok(keysScanned > 6 * 1000, `scanned only ${keysScanned} keys across all locales`);
});

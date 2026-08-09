// The narrow-union label vocabularies, pinned end to end: the `types.ts` union
// -> `ENUM_VOCABULARIES` -> one catalogue key per value in all six locales ->
// no surface naming a value any other way, and no surface printing the raw
// database token instead of a name.
//
// This is decisions § 547's `activity_type` guard generalised, because the same
// defect had re-grown four more times. Nine surfaces rendered a stored token
// directly — `{route.surface}` on /routes, /routes/[id], /segments/[id],
// /share/route/[id], the club route list, the explorer and the heatmap;
// `{club.join_policy}` and `{club.viewer_role}`; `{run.activity_type}` twice on
// a club event; `{a.status}` on its attendee list — so a German or Japanese
// reader got "road", "invite", "race_director", "stroller", "waitlisted" on an
// otherwise localized page. Where a vocabulary did exist it existed more than
// once and disagreed inside a locale: Spanish `road` was both "Asfalto"
// (route builder) and "Carretera" (routes filter), Brazilian `road` both
// "Asfalto" and "Estrada", French `going` both "J'y vais" (event) and
// "Participe" (club home), German both "Zugesagt" and "Nimmt teil", Japanese
// both "参加する" and "参加" — six measured within-locale disagreements.
//
// Three claims, each derived rather than restated:
//
//  1. The registry is exactly the union declared in `types.ts`. Widening a
//     union then fails here until the catalogues catch up.
//  2. Every value has a distinct, non-empty label in every locale. A missing
//     key renders the English fallback, which is the leak this closes.
//  3. No surface re-grows a second vocabulary, and none prints a raw value.
//     Both are shapes a type cannot forbid, so both are source-scanned with
//     must-flag / must-spare fixtures.
//
// Invocation:
//   npx tsx --test src/lib/i18n/enum_vocabulary.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

// Relative, not `$lib`: this suite runs under `tsx --test`, which resolves the
// alias only from the `.svelte-kit/tsconfig.json` a `svelte-kit sync` writes,
// and CI's drift job runs the tests without syncing first.
import { SUPPORTED_LOCALES } from './locale.js';
import { CATALOGUE_LOADERS } from './catalogues.js';
import {
	ENUM_VOCABULARIES,
	ENUM_UNION_NAMES,
	enumLabelKey,
	type EnumVocabulary,
} from './enum_labels.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC_ROOT = resolve(HERE, '..', '..');
const TYPES_FILE = join(SRC_ROOT, 'lib/types.ts');
const VOCABULARIES = Object.keys(ENUM_VOCABULARIES) as EnumVocabulary[];

// ── The authoritative value set, read from the union declaration ────────────

function unionValues(name: string): string[] {
	const src = readFileSync(TYPES_FILE, 'utf-8');
	const decl = src.match(new RegExp(`export type ${name}\\s*=([^;]*);`));
	assert.ok(decl, `types.ts no longer declares a \`${name}\` union`);
	const values = [...decl[1].matchAll(/'([^']+)'/g)].map((m) => m[1]);
	assert.ok(values.length > 0, `parsed an EMPTY value set out of ${name}`);
	return values;
}

test('every registered vocabulary is exactly its types.ts union', () => {
	for (const vocab of VOCABULARIES) {
		assert.deepEqual(
			[...ENUM_VOCABULARIES[vocab]].sort(),
			unionValues(ENUM_UNION_NAMES[vocab]).sort(),
			`${vocab} drifted from the ${ENUM_UNION_NAMES[vocab]} union`,
		);
	}
	assert.ok(VOCABULARIES.length >= 4, `only ${VOCABULARIES.length} vocabularies registered`);
});

// ── Every value has a distinct label, in every locale ───────────────────────

test('every value carries a label in every locale, and no locale names two values of one union the same', async () => {
	let checked = 0;
	let expected = 0;
	for (const loc of SUPPORTED_LOCALES) {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		for (const vocab of VOCABULARIES) {
			const seen = new Map<string, string>();
			for (const value of ENUM_VOCABULARIES[vocab]) {
				const key = enumLabelKey(vocab, value);
				const label = dict[key];
				assert.ok(
					typeof label === 'string' && label.trim().length > 0,
					`${loc} has no non-empty label for ${vocab} '${value}' (${key}). ` +
						`A missing key renders the English fallback — a runtime English leak.`,
				);
				// The failure mode being closed is two names for one value. Its
				// mirror — one name for two values — is just as wrong: a picker
				// with two identically-labelled options is unusable.
				const clash = seen.get(label);
				assert.equal(
					clash,
					undefined,
					`${loc} labels both ${vocab} '${clash}' and '${value}' as ${JSON.stringify(label)}`,
				);
				seen.set(label, value);
				checked++;
			}
			expected += ENUM_VOCABULARIES[vocab].length;
		}
	}
	assert.equal(checked, expected, `checked ${checked} labels, expected ${expected}`);
});

// ── No catalogue re-grows a per-surface vocabulary ──────────────────────────
//
// A per-surface duplicate is any key OUTSIDE the canonical namespace that names
// one of the values in the `<surface>.<token><Value>` shape the originals used
// (`routesPage.surfaceRoad`, `clubHome.roleOptionAdmin`, `clubEvent.maybe` was
// the tokenless variant and is caught by the value-alone arm). The matcher is
// over KEY NAMES — there is no other signal, since two catalogue entries
// spelling `trail` differently are both valid strings — so it earns a fixture
// table in both directions like any other regex-shaped guard.

const DUPLICATE_TOKENS: Record<EnumVocabulary, string[]> = {
	routeSurface: ['surface'],
	joinPolicy: ['policy', 'joinPolicy'],
	clubRole: ['role', 'clubRole'],
	rsvpStatus: ['rsvp', 'status'],
};

function duplicateKeyMatcher(vocab: EnumVocabulary): RegExp {
	const values = ENUM_VOCABULARIES[vocab].join('|');
	const tokens = DUPLICATE_TOKENS[vocab].join('|');
	// `<surface>.<token><anything><Value>` or the tokenless `<surface>.<Value>`.
	return new RegExp(`^(?!${vocab}\\.)[A-Za-z]+\\.(?:(?:${tokens})[A-Za-z]*)?_?(?:${values})$`, 'i');
}

const KEY_FIXTURES: Array<[flagged: boolean, key: string]> = [
	// The eleven that existed, one key each.
	[true, 'routesPage.surfaceRoad'],
	[true, 'routeExplorer.surfaceTrail'],
	[true, 'routeNew.trail'],
	[true, 'clubHome.roleOptionAdmin'],
	[true, 'clubHome.rsvpGoing'],
	[true, 'clubEvent.maybe'],
	[true, 'clubEvent.waitlisted'],
	// A surface nobody has built yet, same shape — the point of matching a
	// shape rather than a list.
	[true, 'someNewPage.surfaceMixed'],
	[true, 'someNewPage.policyInvite'],
	// The canonical namespaces must be spared or the guard eats the fix.
	[false, 'routeSurface.road'],
	[false, 'joinPolicy.invite'],
	[false, 'clubRole.race_director'],
	[false, 'rsvpStatus.waitlisted'],
	// Filter sentinels and headings are not value names.
	[false, 'routesPage.surfaceAny'],
	[false, 'routesPage.surfaceLabel'],
	[false, 'routeNew.surface'],
	[false, 'routeExplorer.filterSurface'],
	[false, 'clubEditor.whoCanJoin'],
	// Same word, different value domain.
	[false, 'plansPage.statusActive'],
	[false, 'coachingAthlete.statusDone'],
	[false, 'clubEvent.waitlistNoteOne'],
	// Whole sentences, not names: "You're the owner" cannot be resolved
	// through as a label, so it is not a second vocabulary.
	[false, 'clubHome.viewerRoleOwner'],
	[false, 'clubHome.viewerRoleMember'],
	// The measured blind spot, recorded rather than papered over: a key whose
	// tail ABBREVIATES the value is invisible to a matcher keyed on the value.
	// `clubHome.roleOptionDirector` named `race_director` and this scan would
	// have spared it; it was found by hand and deleted. Widening the tail to
	// any word would swallow `plansPage.statusActive` and `clubEvent.
	// waitlistNoteOne`, so the scan stays narrow and the hand sweep is what
	// covers abbreviations.
	[false, 'clubHome.roleOptionDirector'],
	[false, 'clubHome.roleOptionOrganiser'],
];

test('the duplicate-vocabulary matcher flags a surface-scoped value key and spares the canonical one', () => {
	const matchers = VOCABULARIES.map(duplicateKeyMatcher);
	for (const [flagged, key] of KEY_FIXTURES) {
		assert.equal(
			matchers.some((re) => re.test(key)),
			flagged,
			`must ${flagged ? 'flag' : 'spare'} ${JSON.stringify(key)}`,
		);
	}
});

test('no catalogue carries a second, surface-scoped vocabulary for a registered union', async () => {
	const matchers = VOCABULARIES.map(duplicateKeyMatcher);
	let localesChecked = 0;
	let keysScanned = 0;
	for (const loc of SUPPORTED_LOCALES) {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		const keys = Object.keys(dict);
		keysScanned += keys.length;
		const strays = keys.filter((k) => matchers.some((re) => re.test(k)));
		assert.deepEqual(
			strays,
			[],
			`${loc} carries surface-scoped value labels ${JSON.stringify(strays)}. ` +
				`Resolve through i18n/enum_labels.svelte.ts instead — a second vocabulary is ` +
				`how the surface and RSVP names drifted apart inside a locale.`,
		);
		localesChecked++;
	}
	// Assert the population: an empty catalogue would pass the loop above.
	assert.equal(localesChecked, SUPPORTED_LOCALES.length);
	assert.ok(keysScanned > 6 * 1000, `scanned only ${keysScanned} keys across all locales`);
});

// ── No surface renders a raw value ──────────────────────────────────────────
//
// The defect the vocabularies exist to remove is a template that interpolates
// the stored token straight into the DOM. Scanned over the enum-bearing column
// names, in TEXT position only: an attribute (`title={seg.role}`) or a class
// interpolation (`class="tl-{seg.role}"`) picks an icon or a colour off the
// value and never shows it, which is legitimate.
//
// `status` is deliberately NOT among the columns. It names an RSVP on one table
// and a plan, a report, an order, a projection and an HTTP response elsewhere,
// so a matcher keyed on it would be mostly false positives and would be
// silenced by an allowlist large enough to hide a real one. The `rsvpStatus`
// catalogue arm above is what guards that column.

const ENUM_COLUMNS = ['surface', 'join_policy', 'activity_type', 'role', 'viewer_role'];

const RAW_ENUM_RENDER = new RegExp(
	String.raw`(?:^|[>\s])\{\s*[A-Za-z_$][\w$]*(?:[?!]?\.[\w$]+|\[[^\]]*\])*[?!]?\.(?:${ENUM_COLUMNS.join('|')})\s*\}`,
);

const RENDER_FIXTURES: Array<[flagged: boolean, line: string]> = [
	// Every raw render this round removed, in its original spelling.
	[true, '<span class="surface-tag">{route.surface}</span>'],
	[true, '\t\t\t\t\t\t{segment.surface}'],
	[true, '<span class="policy-chip">{club.join_policy}</span>'],
	[true, '<span class="chip chip-mine">{club.viewer_role}</span>'],
	[true, '<span class="run-kind muted">{run.activity_type}</span>'],
	[true, '{#if r.surface}<span>· {r.surface}</span>{/if}'],
	[true, '<td>{member?.role}</td>'],
	// Spared: the resolved form, which is the whole point.
	[false, '<span class="surface-tag">{routeSurfaceLabel(route.surface)}</span>'],
	[false, '<span class="run-kind muted">{activityTypeLabel(run.activity_type)}</span>'],
	// Spared: the value picking an icon, a class or a prop — never shown.
	[false, "\t\t\t\t\t\t\t\t\t{route.surface === 'trail' ? 'terrain' : 'add_road'}"],
	[false, '<span class="material-symbols" title={seg.role}></span>'],
	[false, '<span class="tl-seg tl-{seg.role}"></span>'],
	[false, '<RunHeader activityType={run.activity_type} />'],
	[false, '<div data-surface={route.surface}></div>'],
	// Spared: control flow, not a render.
	[false, '{#if route.surface}'],
	[false, '{#each members as m (m.role)}'],
];

test('the raw-render scan flags a token interpolated into the DOM and spares an icon or attribute use', () => {
	for (const [flagged, line] of RENDER_FIXTURES) {
		assert.equal(
			RAW_ENUM_RENDER.test(line),
			flagged,
			`the scan must ${flagged ? 'flag' : 'spare'} ${JSON.stringify(line)}`,
		);
	}
});

// file -> exact number of raw-render sites, each named. Count-pinned so the
// list can only shrink and a new one fails wherever it lands.
const RAW_RENDER_ALLOWED: Record<string, number> = {};

const SKIP_DIRS = new Set(['node_modules', '.svelte-kit', 'build', 'dist']);

function svelteFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		if (SKIP_DIRS.has(entry)) continue;
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) svelteFiles(full, out);
		else if (entry.endsWith('.svelte')) out.push(full);
	}
	return out;
}

test('no template renders a narrow-union value raw, and every allowed site is named', () => {
	const files = svelteFiles(SRC_ROOT);
	assert.ok(files.length > 150, `scanned only ${files.length} .svelte files`);
	const found: Record<string, string[]> = {};
	for (const file of files) {
		const rel = relative(SRC_ROOT, file).split(sep).join('/');
		for (const line of readFileSync(file, 'utf-8').split('\n')) {
			if (RAW_ENUM_RENDER.test(line)) (found[rel] ??= []).push(line.trim());
		}
	}
	for (const [rel, lines] of Object.entries(found)) {
		assert.equal(
			lines.length,
			RAW_RENDER_ALLOWED[rel] ?? 0,
			`${rel} renders a stored enum value raw:\n  ${lines.join('\n  ')}\n` +
				`Resolve it through i18n/enum_labels.svelte.ts (or activityTypeLabel) — the raw ` +
				`token reads as English in all six locales.`,
		);
	}
	// The allowlist must not outlive what it names.
	for (const rel of Object.keys(RAW_RENDER_ALLOWED)) {
		assert.ok(found[rel], `${rel} is allowlisted but no longer renders a raw value — drop the entry`);
	}
});

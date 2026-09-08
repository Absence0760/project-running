// Guard-rail: every JSON-LD payload the tree builds is escaped for the
// raw-text `<script>` it is dropped into.
//
// The escape used to be nine private copies of one three-line function, which
// `check_shared_reimplementations.mjs` could not see: it reports a group only
// when one member is an exported `lib/` function, and none of them was. §1475
// made it one exported `serialiseJsonLd`, which brings a tenth COPY into that
// guard's reach — measured, both as a named private function and as an inline
// replace chain inside a builder.
//
// What no guard sees is a builder that stringifies and simply forgets, which
// is the dangerous shape: `JSON.stringify(graph)` alone, with a user-set club
// name spelling `</script>`, terminates the element and puts the rest of the
// value in the document as markup. Measured too — that builder passes
// `check_shared_reimplementations.mjs` clean, because omitting a step leaves
// nothing to match.
//
// So the property pinned here is a census plus a behaviour: the set of
// exported `*JsonLd` builders in the tree must equal REGISTER exactly, and
// each one must survive a hostile field. A thirteenth builder fails until it
// is listed, and it cannot be listed without an invocation that proves it
// escapes. A builder that is deleted fails too, so the register cannot rot.
//
// Invocation:
//   npx tsx --test src/lib/util/json_ld_escaping.test.ts

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { relative, resolve } from 'node:path';

import { buildGuideJsonLd, buildLearnCollectionJsonLd } from '../learn/learn_meta';
import { buildClubJsonLd } from '../share/share_club_meta';
import { buildEventJsonLd } from '../share/share_event_meta';
import { buildRouteJsonLd, buildRunJsonLd } from '../share/share_meta';
import { buildProfileJsonLd } from '../share/share_profile_meta';
import { buildRaceJsonLd } from '../share/share_race_meta';
import { buildSessionJsonLd } from '../share/share_session_meta';
import { buildWorkoutJsonLd } from '../share/share_workout_meta';
import { buildOrganizationJsonLd, buildWebSiteJsonLd } from '../share/site_meta';

const __dirname = resolve(new URL('.', import.meta.url).pathname);
const webRoot = resolve(__dirname, '../../..');

/// A payload that would close the block and open an element if it reached the
/// document unescaped. `&` is in it because the escape covers `&` too — see
/// `json_ld.ts` for why that is defence for an XHTML document and not for
/// this one.
const INJ = '</script ><img src=x onerror=alert(1)>&amp;';

/// Every field any builder reads for a name / title / caption, on one object.
/// The builders take mutually incompatible row types, so this is cast at each
/// call the way `share_head_escaping.test.ts` casts its own hostile head.
const hostileRow = {
	name: INJ,
	title: INJ,
	display_name: INJ,
	description: INJ,
	location_label: INJ,
	handle: INJ,
	avatar_url: INJ,
	discipline: INJ,
	surface: INJ,
	distance_m: 5000,
	duration_s: 1800,
	started_at: '2026-01-01T00:00:00.000Z',
	starts_at: '2026-01-01T00:00:00.000Z',
	race_date: '2026-01-01',
	set_count: 1,
	volume_kg: 100,
	sets: [],
	blocks: [],
	items: [],
};

const base = 'https://threkir.com';
/// The site-wide nodes read nothing but the base, so the base is where a
/// hostile value has to be put to reach their payload.
const hostileBase = `${base}/${INJ}`;

/** Every exported `*JsonLd` builder, and how to make it emit a hostile field. */
const REGISTER: Record<string, Record<string, () => string>> = {
	'src/lib/learn/learn_meta.ts': {
		buildGuideJsonLd: () =>
			buildGuideJsonLd({
				title: INJ,
				description: INJ,
				slug: INJ,
				updated: '2026-01-01',
				categoryId: INJ,
				categoryLabel: INJ,
				base,
			}),
		buildLearnCollectionJsonLd: () =>
			buildLearnCollectionJsonLd({
				title: INJ,
				description: INJ,
				category: { id: INJ, label: INJ },
				guides: [{ slug: INJ, title: INJ }],
				base,
			}),
	},
	'src/lib/share/share_club_meta.ts': {
		buildClubJsonLd: () => buildClubJsonLd(hostileRow as never, { slug: INJ, base }),
	},
	'src/lib/share/share_event_meta.ts': {
		buildEventJsonLd: () => buildEventJsonLd(hostileRow as never, { id: INJ, base }),
	},
	'src/lib/share/share_meta.ts': {
		buildRunJsonLd: () =>
			buildRunJsonLd(hostileRow as never, { id: INJ, base, displayName: INJ }),
		buildRouteJsonLd: () => buildRouteJsonLd(hostileRow as never, { id: INJ, base }),
	},
	'src/lib/share/share_profile_meta.ts': {
		buildProfileJsonLd: () => buildProfileJsonLd(hostileRow as never, { id: INJ, base }),
	},
	'src/lib/share/share_race_meta.ts': {
		buildRaceJsonLd: () => buildRaceJsonLd(hostileRow as never, { id: INJ, base }),
	},
	'src/lib/share/share_session_meta.ts': {
		buildSessionJsonLd: () =>
			buildSessionJsonLd(hostileRow as never, { id: INJ, base, displayName: INJ }),
	},
	'src/lib/share/share_workout_meta.ts': {
		buildWorkoutJsonLd: () =>
			buildWorkoutJsonLd(hostileRow as never, { id: INJ, base, displayName: INJ }),
	},
	'src/lib/share/site_meta.ts': {
		buildOrganizationJsonLd: () => buildOrganizationJsonLd(hostileBase),
		buildWebSiteJsonLd: () => buildWebSiteJsonLd(hostileBase),
	},
};

const EXPORTED_BUILDER = /export (?:function|const) (\w*JsonLd)\b/g;

/// The canonical serialiser is the thing every builder must reach; it is not
/// itself a builder, so it is the one export the census skips by name.
const CANONICAL = 'src/lib/util/json_ld.ts';

function walk(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		if (entry.name === 'node_modules' || entry.name.startsWith('.')) continue;
		const full = resolve(dir, entry.name);
		if (entry.isDirectory()) walk(full, out);
		else if (/\.(ts|svelte)$/.test(entry.name) && !entry.name.endsWith('.test.ts')) out.push(full);
	}
	return out;
}

function censusFromSource(): Record<string, string[]> {
	const found: Record<string, string[]> = {};
	for (const root of ['src', 'lambda']) {
		for (const file of walk(resolve(webRoot, root))) {
			const src = readFileSync(file, 'utf8');
			const names = [...src.matchAll(EXPORTED_BUILDER)].map((m) => m[1]);
			const rel = relative(webRoot, file);
			if (names.length > 0 && rel !== CANONICAL) found[rel] = names.sort();
		}
	}
	return found;
}

test('every exported *JsonLd builder in the tree is registered here', () => {
	const found = censusFromSource();
	const expected = Object.fromEntries(
		Object.entries(REGISTER).map(([file, cases]) => [file, Object.keys(cases).sort()]),
	);
	assert.deepEqual(
		found,
		expected,
		'a JSON-LD builder was added, moved or removed — register it with an invocation that proves it escapes',
	);
});

for (const [file, cases] of Object.entries(REGISTER)) {
	for (const [name, call] of Object.entries(cases)) {
		test(`${name} (${file}) — a hostile field cannot terminate the ld+json block`, () => {
			const payload = call();
			assert.ok(!payload.includes('<'), `${name}: a literal < reached the payload`);
			assert.ok(!payload.includes('>'), `${name}: a literal > reached the payload`);
			assert.ok(!payload.includes('&'), `${name}: a literal & reached the payload`);
			// Escaped, not stripped: the value must survive intact for a consumer.
			assert.ok(
				JSON.stringify(JSON.parse(payload)).includes(JSON.stringify(INJ).slice(1, -1)),
				`${name}: the hostile field was mangled rather than escaped`,
			);
		});
	}
}
